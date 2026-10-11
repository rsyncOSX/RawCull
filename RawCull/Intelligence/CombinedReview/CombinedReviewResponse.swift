import Foundation

nonisolated struct CombinedReviewOverview: Codable, Sendable {
    var primarySubjects: [ReviewPrimarySubjectCue]? = nil
    var contextualConcepts: [String]? = nil
    let observations: String
    let uncertainty: String
    let concepts: [String]
}

nonisolated struct CombinedReviewInspection: Codable, Sendable {
    let regionID: String
    let observations: String
    let uncertainty: String
    let insufficientEvidence: Bool
}

nonisolated enum CombinedReviewResponse {
    static let overviewInstruction = """
    Inspect this single photograph independently. Return JSON only:
    {"observations":"visible composition, exposure, subjects, obstructions; at most 500 characters",
    "uncertainty":"limits; at most 200 characters",
    "concepts":[{"query":"bird","displayName":"Bird","reason":"visible subject"}]}.
    Optionally include "primarySubjects":[{"concept":"bird","location":{"x":0.5,"y":0.5},"reason":"main photographic subject"}]
    and "contextualConcepts":["flower"]. Locations are normalized top-left points inside visible main subjects.
    Leave primarySubjects empty when importance or location is uncertain; multiple nominations may be equally important.
    Use at most 3 concrete subject concepts. Do not invent unseen features, eye detail,
    RAW recovery or quality scores. A proposed subject is a candidate for segmentation.
    """

    static func overview(_ response: String) throws -> CombinedReviewOverview {
        struct Payload: Decodable { let observations: String; let uncertainty: String; let primarySubjects: [ReviewPrimarySubjectCue]?; let contextualConcepts: [String]? }
        let payload = try ObjectJSONEnvelope.decode(Payload.self, from: response)
        try validateText(payload.observations, maximum: 500, field: "observations")
        try validateText(payload.uncertainty, maximum: 200, field: "uncertainty")
        let concepts = try ObjectConceptDiscovery.decode(response)
        guard concepts.count <= 3 else { throw ReviewValidationIssue(.responseLength, "overview.conceptCount", field: "concepts") }
        let queries = concepts.map { $0.concept.query }
        guard (payload.primarySubjects?.count ?? 0) <= 3, (payload.contextualConcepts?.count ?? 0) <= 3 else { throw ReviewValidationIssue(.responseLength, "overview.priorityCount", field: "primarySubjects") }
        for cue in payload.primarySubjects ?? [] {
            guard queries.contains(cue.concept), !cue.reason.isEmpty, cue.reason.count <= 120 else { throw ReviewValidationIssue(.grounding, "overview.discoveredPrimaryConcept", field: "primarySubjects") }
            if let point = cue.location {
                guard point.x.isFinite, point.y.isFinite, (0 ... 1).contains(point.x), (0 ... 1).contains(point.y) else { throw ReviewValidationIssue(.geometry, "overview.normalizedPrimaryLocation", field: "primarySubjects.location") }
            }
        }
        guard (payload.contextualConcepts ?? []).allSatisfy(queries.contains) else { throw ReviewValidationIssue(.grounding, "overview.discoveredContextualConcept", field: "contextualConcepts") }
        return .init(primarySubjects: payload.primarySubjects, contextualConcepts: payload.contextualConcepts, observations: payload.observations, uncertainty: payload.uncertainty, concepts: queries)
    }

    static func inspection(_ response: String, regionID: String) throws -> CombinedReviewInspection {
        let value = try ObjectJSONEnvelope.decode(CombinedReviewInspection.self, from: response)
        let forbidden = containsForbiddenClaimDomain(value.observations)
        guard !forbidden else { throw ReviewValidationIssue(.unsupportedDomain, "crop.supportedDomain", field: "observations") }
        guard value.regionID == regionID else { throw ReviewValidationIssue(.unknownID, "crop.expectedRegionID", field: "regionID", reference: .init(kind: .region, id: regionID)) }
        try validateText(value.observations, maximum: 500, field: "observations")
        try validateText(value.uncertainty, maximum: 200, field: "uncertainty")
        return value
    }

    static func report(_ response: String, imageID: ReviewImageID, allowed: Set<ReviewEvidenceReference>,
                       limitations: [ReviewLimitation], regions: [ReviewRegionID], uninspected: [ReviewRegionID], incomplete: Bool) throws -> ReviewImageReport {
        struct Payload: Decodable { let claims: [ReviewClaim] }
        let payload = try ObjectJSONEnvelope.decode(Payload.self, from: response)
        guard payload.claims.count <= 6 else { throw ReviewValidationIssue(.responseLength, "report.claimCount", field: "claims") }
        for claim in payload.claims {
            try validateText(claim.text, maximum: 400, field: "claims.text")
            guard !claim.evidence.isEmpty else { throw ReviewValidationIssue(.grounding, "report.evidenceRequired", field: "claims.evidence") }
            guard Set(claim.evidence + claim.contradictions).isSubset(of: allowed) else { throw ReviewValidationIssue(.unknownID, "report.requestLocalReference", field: "claims.evidence") }
            let forbidden = containsForbiddenClaimDomain(claim.text)
            guard !forbidden else { throw ReviewValidationIssue(.unsupportedDomain, "report.supportedDomain", field: "claims.text") }
            guard !claim.type.isEmpty else { throw ReviewValidationIssue(.schema, "report.claimTypeRequired", field: "claims.type") }
            guard claim.uncertainty.count <= 200 else { throw ReviewValidationIssue(.responseLength, "report.uncertaintyLength", field: "claims.uncertainty") }
        }
        return .init(id: .init(rawValue: imageID.rawValue + ":report"), imageID: imageID, claims: payload.claims,
                     limitations: limitations, incomplete: incomplete || payload.claims.isEmpty, inspectedRegions: regions, uninspectedRegions: uninspected)
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
