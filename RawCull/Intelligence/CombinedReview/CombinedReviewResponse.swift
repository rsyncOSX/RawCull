import Foundation

nonisolated struct CombinedReviewOverview: Codable, Sendable {
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
    Use at most 3 concrete subject concepts. Do not invent unseen features, eye detail,
    RAW recovery or quality scores. A proposed subject is a candidate for segmentation.
    """

    static func overview(_ response: String) throws -> CombinedReviewOverview {
        struct Payload: Decodable { let observations: String; let uncertainty: String }
        let payload = try ObjectJSONEnvelope.decode(Payload.self, from: response)
        try validateText(payload.observations, maximum: 500)
        try validateText(payload.uncertainty, maximum: 200)
        let concepts = try ObjectConceptDiscovery.decode(response)
        guard concepts.count <= 3 else { throw ReviewRunError.invalidEvidence }
        return .init(observations: payload.observations, uncertainty: payload.uncertainty, concepts: concepts.map { $0.concept.query })
    }

    static func inspection(_ response: String, regionID: String) throws -> CombinedReviewInspection {
        let value = try ObjectJSONEnvelope.decode(CombinedReviewInspection.self, from: response)
        let lower = value.observations.lowercased()
        guard !lower.contains("eye"), !lower.contains("iris"), !lower.contains("recover"), value.regionID == regionID else { throw ReviewRunError.invalidEvidence }
        try validateText(value.observations, maximum: 500)
        try validateText(value.uncertainty, maximum: 200)
        return value
    }

    static func report(_ response: String, imageID: ReviewImageID, allowed: Set<ReviewEvidenceReference>,
                       limitations: [ReviewLimitation], regions: [ReviewRegionID], uninspected: [ReviewRegionID], incomplete: Bool) throws -> ReviewImageReport
    {
        struct Payload: Decodable { let claims: [ReviewClaim] }
        let payload = try ObjectJSONEnvelope.decode(Payload.self, from: response)
        guard payload.claims.count <= 6 else { throw ReviewRunError.invalidEvidence }
        for claim in payload.claims {
            try validateText(claim.text, maximum: 400)
            try claim.validate(allowed: allowed)
            let lower = claim.text.lowercased()
            guard !lower.contains("eye"), !lower.contains("iris"),
                  !lower.contains("recover"), !claim.type.isEmpty, claim.uncertainty.count <= 200 else { throw ReviewRunError.invalidEvidence }
        }
        return .init(id: .init(rawValue: imageID.rawValue + ":report"), imageID: imageID, claims: payload.claims,
                     limitations: limitations, incomplete: incomplete || payload.claims.isEmpty, inspectedRegions: regions, uninspectedRegions: uninspected)
    }

    /// A UTF-8 byte bound is conservative for the pinned byte-level tokenizer;
    /// reserve image tokens, output and 256 template tokens. Never truncate schema/IDs.
    static func admitted(_ instruction: String, model: ReviewModelSnapshot, outputTokens: Int) throws -> String {
        guard let context = model.contextTokens, let image = model.imageTokens,
              instruction.utf8.count + image + outputTokens + 256 <= context else { throw ReviewRunError.invalidEvidence }
        return instruction
    }

    private static func validateText(_ text: String, maximum: Int) throws {
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, text.count <= maximum else { throw ReviewRunError.invalidEvidence }
    }
}
