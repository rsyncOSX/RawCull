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
    var validationNotes: [String]? = nil
    var targetIdentified: Bool? = nil
    var criteria: ReviewCriterionObservations? = nil
    let regionID: String
    let observations: String
    let uncertainty: String
    let insufficientEvidence: Bool
}

/// Request-boundary strings/nulls avoid redundant support flags. All keys are required.
nonisolated struct ReviewNullableCriteria: Codable, Sendable {
    let composition: String?
    let exposure: String?
    let visibility: String?
    let detail: String?

    enum CodingKeys: String, CodingKey { case composition, exposure, visibility, detail }
    init(composition: String?, exposure: String?, visibility: String?, detail: String?) {
        self.composition = composition; self.exposure = exposure; self.visibility = visibility; self.detail = detail
    }
    init(from decoder: any Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        composition = try values.decode(String?.self, forKey: .composition)
        exposure = try values.decode(String?.self, forKey: .exposure)
        visibility = try values.decode(String?.self, forKey: .visibility)
        detail = try values.decode(String?.self, forKey: .detail)
    }
    func encode(to encoder: any Encoder) throws {
        var values = encoder.container(keyedBy: CodingKeys.self)
        try values.encode(composition, forKey: .composition)
        try values.encode(exposure, forKey: .exposure)
        try values.encode(visibility, forKey: .visibility)
        try values.encode(detail, forKey: .detail)
    }
    var observations: ReviewCriterionObservations {
        func entry(_ text: String?) -> ReviewCriterionObservation { .init(supported: text != nil, text: text ?? "") }
        return .init(composition: entry(composition), exposure: entry(exposure), visibility: entry(visibility), detail: entry(detail))
    }
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

    static func canRepair(_ issue: ReviewValidationIssue) -> Bool {
        [.json, .schema, .unknownID].contains(issue.code)
            || ["crop.supportedDomain", "crop.criterionLength", "crop.criterionTargetConsistency"].contains(issue.check)
    }

    static func repairInstruction(for issue: ReviewValidationIssue) -> String {
        let field = issue.fieldPath ?? "JSON"
        let action: String
        if field.hasPrefix("selection") || issue.check.hasPrefix("selection.") {
            action = "Return composition, exposure, visibility and detail keys, each an eligible row ID STRING or null. Use only the allowed IDs for that category. Never return claim prose or evidence objects."
        } else if field.hasPrefix("criteria") || issue.check.hasPrefix("crop.") {
            switch issue.check {
            case "crop.criterionLength": action = "Shorten each criterion to at most 120 characters; aim for 80. Preserve meaning; use null if unsupported."
            case "crop.criterionTargetConsistency": action = "Determine visible generic-target presence from the image, not species or individual identity. If absent or indistinguishable, targetIdentified=false and detail=null. No resolved target texture also requires detail=null. Never infer presence from Purpose."
            case "crop.supportedDomain": action = "Replace prohibited criterion text with permitted evidence or null. Never repeat anatomy or focus claims."
            case "crop.exposureEvidence": action = "criteria.exposure must describe illumination/tonal contrast, or be null; sky color alone is insufficient."
            case "crop.visibilityEvidence": action = "criteria.visibility must describe extent/occlusion, or be null; put identity uncertainty in uncertainty."
            case "crop.duplicateCriterionText": action = "Use different criterion-specific strings; set unsupported criteria to null."
            default: action = "criteria must contain composition, exposure, visibility and detail, each a string or null. No supported/text objects. Include targetIdentified Boolean and uncertainty string."
            }
        } else if field.hasPrefix("claims") || issue.check.hasPrefix("report.") || issue.check.hasPrefix("synthesis.") {
            action = "Each claim needs text STRING, type STRING, evidence ARRAY of supplied {kind,id} objects, uncertainty STRING and contradictions ARRAY. Observation prose belongs in text, never evidence. Omit unsupported claims."
        } else {
            action = "Return the complete original schema with every required field and exact type; use supplied IDs."
        }
        return "Previous response failed validation: " + issue.check + ", field " + field + ".\n" + action
    }

    static func inspection(_ response: String, regionID: String, requireCriteria: Bool = false, preserveValidCriteria: Bool = false) throws -> CombinedReviewInspection {
        let value: CombinedReviewInspection
        if requireCriteria {
            struct Payload: Decodable {
                let regionID: String
                let criteria: ReviewNullableCriteria
                let uncertainty: String
                let targetIdentified: Bool
            }
            let payload = try ObjectJSONEnvelope.decode(Payload.self, from: response)
            let rawCriteria = payload.criteria.observations
            var accepted: [String: ReviewCriterionObservation] = [:]
            var notes: [String] = []
            var seen = Set<String>()
            for type in ReviewCriterionObservations.types {
                let entry = rawCriteria[type]!
                do {
                    guard entry.supported == !entry.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                        throw ReviewValidationIssue(.schema, "crop.nullOrObservation", field: "criteria." + type)
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
                    if type == "detail", entry.supported {
                        guard payload.targetIdentified else {
                            throw ReviewValidationIssue(.grounding, "crop.criterionTargetConsistency", field: "criteria.detail")
                        }
                        let lower = entry.text.lowercased()
                        guard !["not resolved", "unresolved", "not clearly resolved", "no texture", "no surface texture", "not discernible", "not distinguishable", "background texture"].contains(where: lower.contains) else {
                            throw ReviewValidationIssue(.grounding, "crop.unresolvedDetail", field: "criteria.detail")
                        }
                    }
                    if entry.supported {
                        let normalized = entry.text.lowercased().trimmingCharacters(in: .whitespacesAndNewlines.union(.punctuationCharacters))
                        guard seen.insert(normalized).inserted else {
                            throw ReviewValidationIssue(.schema, "crop.duplicateCriterionText", field: "criteria." + type)
                        }
                    }
                    accepted[type] = entry
                } catch let issue as ReviewValidationIssue {
                    guard preserveValidCriteria else { throw issue }
                    accepted[type] = .init(supported: false, text: "")
                    notes.append("Rejected " + type + ": " + issue.check + "; criterion abstained")
                }
            }
            let criteria = ReviewCriterionObservations(composition: accepted["composition"]!, exposure: accepted["exposure"]!, visibility: accepted["visibility"]!, detail: accepted["detail"]!)
            let supported = ReviewCriterionObservations.types.compactMap { criteria[$0] }.filter(\.supported)
            // A wholly invalid response remains a failure eligible for bounded repair.
            if supported.isEmpty, !notes.isEmpty {
                return try inspection(response, regionID: regionID, requireCriteria: true)
            }
            value = .init(validationNotes: notes.isEmpty ? nil : notes, targetIdentified: payload.targetIdentified, criteria: criteria, regionID: payload.regionID,
                          observations: supported.map(\.text).joined(separator: " "), uncertainty: payload.uncertainty, insufficientEvidence: supported.isEmpty)
        } else {
            value = try ObjectJSONEnvelope.decode(CombinedReviewInspection.self, from: response)
        }
        let forbidden = containsForbiddenClaimDomain(value.observations)
        guard !forbidden else { throw ReviewValidationIssue(.unsupportedDomain, "crop.supportedDomain", field: "observations") }
        guard value.regionID == regionID else { throw ReviewValidationIssue(.unknownID, "crop.expectedRegionID", field: "regionID", reference: .init(kind: .region, id: regionID)) }
        if !requireCriteria || !value.insufficientEvidence { try validateText(value.observations, maximum: 500, field: "observations") }
        if !requireCriteria || !value.uncertainty.isEmpty { try validateText(value.uncertainty, maximum: 200, field: "uncertainty") }
        guard requireCriteria || !(value.insufficientEvidence && value.targetIdentified == true) else { throw ReviewValidationIssue(.grounding, "crop.targetSupportConsistency", field: "targetIdentified") }
        return value
    }

    static func validateSelectedClaim(_ claim: ReviewClaim) throws {
        try validateText(claim.text, maximum: 400, field: "claims.text")
        guard !containsForbiddenClaimDomain(claim.text) else {
            throw ReviewValidationIssue(.unsupportedDomain, "report.supportedDomain", field: "claims.text")
        }
    }

    /// The model chooses rows; validated evidence owns prose, type and stored IDs.
    static func selectedReport(_ response: String, imageID: ReviewImageID,
                               candidates: [String: [String: ReviewClaim]], limitations: [ReviewLimitation],
                               regions: [ReviewRegionID], uninspected: [ReviewRegionID], incomplete: Bool) throws -> ReviewImageReport {
        let choices = try ObjectJSONEnvelope.decode(ReviewNullableCriteria.self, from: response).observations
        var claims: [ReviewClaim] = []
        var rejected: [ReviewLimitation] = []
        var firstIssue: ReviewValidationIssue?
        for type in ReviewCriterionObservations.types {
            guard let choice = choices[type], choice.supported else { continue }
            guard let claim = candidates[type]?[choice.text], claim.type == type else {
                let issue = ReviewValidationIssue(.unknownID, "selection.eligibleCriterionRow", field: "selection." + type)
                firstIssue = firstIssue ?? issue
                rejected.append(.init(id: .init(rawValue: imageID.rawValue + ":rejected-selection:" + type),
                    reason: "Selected " + type + " rejected: " + issue.check, relatedEvidence: []))
                continue
            }
            claims.append(claim)
        }
        if claims.isEmpty, let firstIssue { throw firstIssue }
        return .init(id: .init(rawValue: imageID.rawValue + ":report"), imageID: imageID, claims: claims,
            limitations: limitations + rejected, incomplete: incomplete || claims.isEmpty || !rejected.isEmpty,
            inspectedRegions: regions, uninspectedRegions: uninspected)
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
