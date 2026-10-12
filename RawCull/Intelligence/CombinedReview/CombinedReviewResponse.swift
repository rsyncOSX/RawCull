import Foundation
import PhotoAIContracts

nonisolated struct CombinedReviewOverview: Codable, Sendable {
    var validationNotes: [String]? = nil
    var primarySubjects: [ReviewPrimarySubjectCue]? = nil
    var contextualConcepts: [String]? = nil
    let observations: String
    let uncertainty: String
    let concepts: [String]
}

nonisolated struct CombinedReviewInspection: Codable, Sendable {
    var targetIdentified: Bool? = nil
    var criteria: ReviewCriterionObservations? = nil
    let regionID: String
    let observations: String
    let uncertainty: String
    let insufficientEvidence: Bool
}

nonisolated enum CombinedReviewResponse {
    static let overviewInstruction = """
    Inspect this photograph. Return JSON only with three fields: observations, uncertainty, concepts.
    observations: one concise sentence about composition, lighting, visible subjects and obstructions (maximum 500 characters).
    uncertainty: one brief sentence about actual evidence limitations (maximum 500 characters; aim for 100).
    concepts: at most 3 objects, each with query, displayName and reason strings. Reasons maximum 500 characters; displayName maximum 80.
    query must be a short singular object noun phrase, preferably 1 to 3 words. Prefer visible subjects.
    Do not use actions, counts, scene descriptions or relationships as queries.
    Do not copy these instructions into observations or uncertainty. Do not invent unseen features, eye detail, RAW recovery or quality scores.
    """

    static func overview(_ response: String) throws -> CombinedReviewOverview {
        struct Payload: Decodable {
            struct Concept: Decodable { let query: String; let displayName: String; let reason: String }
            let observations: String
            let uncertainty: String
            let concepts: [Concept]
            let primarySubjects: [ReviewPrimarySubjectCue]?
            let contextualConcepts: [String]?
            let decodingNotes: [String]

            private enum CodingKeys: String, CodingKey {
                case observations, uncertainty, concepts, primarySubjects, contextualConcepts
            }

            init(from decoder: any Decoder) throws {
                let container = try decoder.container(keyedBy: CodingKeys.self)
                // Core discovery remains strict. Optional hints cannot prevent its decoding.
                observations = try container.decode(String.self, forKey: .observations)
                uncertainty = try container.decode(String.self, forKey: .uncertainty)
                concepts = try container.decode([Concept].self, forKey: .concepts)
                var notes: [String] = []
                func hints<Value: Decodable>(_ type: Value.Type, key: CodingKeys) -> [Value]? {
                    do {
                        return try container.decodeIfPresent([Value].self, forKey: key)
                    } catch {
                        notes.append("overview.optionalSchema: discarded malformed \(key.rawValue); priority metadata unavailable")
                        return nil
                    }
                }
                primarySubjects = hints(ReviewPrimarySubjectCue.self, key: .primarySubjects)
                contextualConcepts = hints(String.self, key: .contextualConcepts)
                decodingNotes = notes
            }
        }
        let payload = try ObjectJSONEnvelope.decode(Payload.self, from: response)
        try validateText(payload.observations, maximum: 500, field: "observations")
        try validateText(payload.uncertainty, maximum: 500, field: "uncertainty")
        guard !payload.observations.lowercased().contains("at most 500 characters"),
              !payload.observations.lowercased().contains("maximum 500 characters"),
              !payload.uncertainty.lowercased().contains("at most 200 characters"),
              !payload.uncertainty.lowercased().contains("maximum 200 characters"),
              !payload.uncertainty.lowercased().contains("maximum 500 characters") else {
            throw ReviewValidationIssue(.grounding, "overview.copiedInstruction", field: "observations")
        }
        guard payload.concepts.count <= 3 else { throw ReviewValidationIssue(.responseLength, "overview.conceptCount", field: "concepts") }
        var queries: [String] = []
        var names: [String: Set<String>] = [:]
        var notes = payload.decodingNotes
        func key(_ text: String) -> String { text.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
        for entry in payload.concepts {
            let query = try SegmentationConcept(entry.query).query
            try validateText(entry.displayName, maximum: 80, field: "concepts.displayName")
            try validateText(entry.reason, maximum: 500, field: "concepts.reason")
            // Actions are observations, not SAM object queries. Do not invent replacement objects.
            if ["motion", "flight", "lighting"].contains(key(query)) {
                notes.append("overview.objectQuery: discarded abstract action or lighting concept")
                continue
            }
            if !queries.contains(where: { key($0) == key(query) }) { queries.append(query) }
            let canonical = queries.first { key($0) == key(query) }!
            names[key(entry.displayName), default: []].insert(canonical)
        }
        func resolve(_ text: String) -> String? {
            if let query = queries.first(where: { key($0) == key(text) }) { return query }
            guard let matches = names[key(text)], matches.count == 1 else { return nil }
            notes.append("overview.conceptAlias: resolved unique display name to its discovered query")
            return matches.first
        }
        var primary: [ReviewPrimarySubjectCue] = []
        for cue in payload.primarySubjects ?? [] {
            guard let query = resolve(cue.concept), !cue.reason.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, cue.reason.count <= 120 else {
                notes.append("overview.discoveredPrimaryConcept: discarded unsupported or oversized optional nomination")
                continue
            }
            var point = cue.location
            if let location = point, !location.x.isFinite || !location.y.isFinite || !(0 ... 1).contains(location.x) || !(0 ... 1).contains(location.y) {
                point = nil
                notes.append("overview.normalizedPrimaryLocation: discarded invalid point; instance location is unverified")
            }
            guard primary.count < 3 else {
                notes.append("overview.priorityCount: omitted optional nominations beyond the three-cue limit")
                continue
            }
            primary.append(.init(concept: query, location: point, reason: cue.reason))
        }
        var contextual: [String] = []
        for concept in payload.contextualConcepts ?? [] {
            guard let query = resolve(concept) else {
                notes.append("overview.discoveredContextualConcept: discarded undiscovered or ambiguous optional context")
                continue
            }
            if !contextual.contains(query) { contextual.append(query) }
        }
        return .init(validationNotes: Array(Set(notes)).sorted(), primarySubjects: primary, contextualConcepts: contextual,
                     observations: payload.observations, uncertainty: payload.uncertainty, concepts: queries)
    }

    static func inspection(_ response: String, regionID: String, requireCriteria: Bool = false) throws -> CombinedReviewInspection {
        let value: CombinedReviewInspection
        if requireCriteria {
            struct Payload: Decodable {
                let regionID: String
                let criteria: ReviewCriterionObservations
                let uncertainty: String
                let insufficientEvidence: Bool
                let targetIdentified: Bool
            }
            let payload = try ObjectJSONEnvelope.decode(Payload.self, from: response)
            for type in ReviewCriterionObservations.types {
                let entry = payload.criteria[type]!
                guard entry.supported == !entry.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                    throw ReviewValidationIssue(.schema, "crop.criterionSupportConsistency", field: "criteria." + type)
                }
                guard entry.text.count <= 120 else { throw ReviewValidationIssue(.responseLength, "crop.criterionLength", field: "criteria." + type + ".text") }
                guard !containsForbiddenClaimDomain(entry.text) else { throw ReviewValidationIssue(.unsupportedDomain, "crop.supportedDomain", field: "criteria." + type + ".text") }
                let technicalWords = entry.text.lowercased().split(whereSeparator: { !$0.isLetter })
                guard !technicalWords.contains(where: { $0.hasPrefix("focus") || $0.hasPrefix("sharp") }) else {
                    throw ReviewValidationIssue(.unsupportedDomain, "crop.supportedDomain", field: "criteria." + type + ".text")
                }
                if entry.supported, type == "exposure", !ReviewSynthesisGrounding.hasLighting(entry.text) {
                    throw ReviewValidationIssue(.schema, "crop.exposureEvidence", field: "criteria.exposure.text")
                }
                if entry.supported, type == "visibility" {
                    let words = Set(entry.text.lowercased().split(whereSeparator: { !$0.isLetter }).map(String.init))
                    guard words.isDisjoint(with: ["species", "identity", "identification", "identifiable", "resolution"]) else {
                        throw ReviewValidationIssue(.schema, "crop.visibilityEvidence", field: "criteria.visibility.text")
                    }
                }
            }
            let supported = ReviewCriterionObservations.types.compactMap { payload.criteria[$0] }.filter(\.supported)
            guard payload.insufficientEvidence == supported.isEmpty,
                  payload.targetIdentified || !payload.criteria.detail.supported else {
                throw ReviewValidationIssue(.grounding, "crop.criterionTargetConsistency", field: "criteria")
            }
            // Identical prose under multiple labels is not criterion-specific evidence.
            let texts = supported.map { $0.text.lowercased().trimmingCharacters(in: .whitespacesAndNewlines.union(.punctuationCharacters)) }
            guard Set(texts).count == texts.count else { throw ReviewValidationIssue(.schema, "crop.duplicateCriterionText", field: "criteria") }
            value = .init(targetIdentified: payload.targetIdentified, criteria: payload.criteria, regionID: payload.regionID,
                          observations: supported.map(\.text).joined(separator: " "), uncertainty: payload.uncertainty, insufficientEvidence: payload.insufficientEvidence)
        } else {
            value = try ObjectJSONEnvelope.decode(CombinedReviewInspection.self, from: response)
        }
        let forbidden = containsForbiddenClaimDomain(value.observations)
        guard !forbidden else { throw ReviewValidationIssue(.unsupportedDomain, "crop.supportedDomain", field: "observations") }
        guard value.regionID == regionID else { throw ReviewValidationIssue(.unknownID, "crop.expectedRegionID", field: "regionID", reference: .init(kind: .region, id: regionID)) }
        try validateText(value.observations, maximum: 500, field: "observations")
        try validateText(value.uncertainty, maximum: 200, field: "uncertainty")
        guard !(value.insufficientEvidence && value.targetIdentified == true) else { throw ReviewValidationIssue(.grounding, "crop.targetSupportConsistency", field: "targetIdentified") }
        return value
    }

    static func report(_ response: String, imageID: ReviewImageID, allowed: Set<ReviewEvidenceReference>,
                       limitations: [ReviewLimitation], regions: [ReviewRegionID], uninspected: [ReviewRegionID], incomplete: Bool, qualify: ((ReviewClaim) throws -> ReviewClaim)? = nil) throws -> ReviewImageReport
    {
        let payload = try ObjectJSONEnvelope.decode(ReviewSynthesisPayload.self, from: response)
        guard payload.claims.count <= 6 else { throw ReviewValidationIssue(.responseLength, "report.claimCount", field: "claims") }
        var accepted: [ReviewClaim] = []
        var rejected: [ReviewLimitation] = []
        var firstIssue: ReviewValidationIssue?
        for (index, payloadClaim) in payload.claims.enumerated() {
            do {
                let claim = try payloadClaim.resolve(allowed: allowed)
                try validateText(claim.text, maximum: 400, field: "claims.text")
                guard !claim.evidence.isEmpty else { throw ReviewValidationIssue(.grounding, "report.evidenceRequired", field: "claims.evidence") }
                guard Set(claim.evidence + claim.contradictions).isSubset(of: allowed) else { throw ReviewValidationIssue(.unknownID, "report.requestLocalReference", field: "claims.evidence") }
                let forbidden = containsForbiddenClaimDomain(claim.text)
                guard !forbidden else { throw ReviewValidationIssue(.unsupportedDomain, "report.supportedDomain", field: "claims.text") }
                guard !claim.type.isEmpty else { throw ReviewValidationIssue(.schema, "report.claimTypeRequired", field: "claims.type") }
                guard claim.uncertainty.count <= 200 else { throw ReviewValidationIssue(.responseLength, "report.uncertaintyLength", field: "claims.uncertainty") }
                // These exact aliases are documented criterion names, not new claim domains.
                let type = ["lighting": "exposure", "subject visibility": "visibility", "behavior": "visibility", "texture": "detail"][claim.type] ?? claim.type
                let canonical = type != claim.type ? ReviewClaim(subjectID: claim.subjectID, regionID: claim.regionID, text: claim.text,
                                                                       type: type, evidence: claim.evidence, uncertainty: claim.uncertainty, contradictions: claim.contradictions) : claim
                accepted.append(try qualify?(canonical) ?? canonical)
            } catch {
                guard qualify != nil else { throw error }
                let issue = ReviewValidationIssue.classify(error)
                firstIssue = firstIssue ?? issue
                rejected.append(.init(id: .init(rawValue: imageID.rawValue + ":rejected-claim:\(index)"),
                                      reason: "Generated claim \(index + 1) rejected: \(issue.code.rawValue): \(issue.check)", relatedEvidence: []))
            }
        }
        if accepted.isEmpty, let firstIssue { throw firstIssue }
        return .init(id: .init(rawValue: imageID.rawValue + ":report"), imageID: imageID, claims: accepted,
                     limitations: limitations + rejected, incomplete: incomplete || accepted.isEmpty || !rejected.isEmpty, inspectedRegions: regions, uninspectedRegions: uninspected)
    }

    /// A UTF-8 byte bound is conservative for the pinned byte-level tokenizer;
    /// reserve image tokens, output and 256 template tokens. Never truncate schema/IDs.
    static func admitted(_ instruction: String, model: ReviewModelSnapshot, outputTokens: Int) throws -> String {
        guard let context = model.contextTokens, let image = model.imageTokens,
              instruction.utf8.count + image + outputTokens + 256 <= context else { throw ReviewValidationIssue(.responseLength, "prompt.contextAllowance", field: "instruction") }
        return instruction
    }

    /// Claim text remains outside these domains. Limitations belong in uncertainty
    /// or the report's explicit limitations, where the same words are allowed.
    private static func containsForbiddenClaimDomain(_ text: String) -> Bool {
        let words = Set(text.lowercased().split(whereSeparator: { !$0.isLetter }).map(String.init))
        return !words.isDisjoint(with: ["eye", "eyes", "iris", "irises", "gaze",
                                        "recover", "recovers", "recovered", "recovering", "recoverable", "recovery"])
    }

    private static func validateText(_ text: String, maximum: Int, field: String) throws {
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw ReviewValidationIssue(.schema, "text.nonempty", field: field) }
        guard text.count <= maximum else { throw ReviewValidationIssue(.responseLength, "text.characterAllowance", field: field) }
    }

    static func validated<Value>(_ response: String, _ validation: (String) throws -> Value) throws -> Value {
        do {
            guard response.utf8.count <= 65536 else { throw ReviewValidationIssue(.responseLength, "response.byteAllowance") }
            return try validation(response)
        } catch {
            throw ReviewResponseRejection(issue: .classify(error), response: response)
        }
    }
}
