import Foundation

/// Model response compatibility stays at the request boundary; stored claims keep
/// their explicit reference schema. Shorthand never guesses an evidence kind.
nonisolated struct ReviewSynthesisPayload: Decodable {
    let claims: [Claim]

    struct Reference: Decodable {
        let explicit: ReviewEvidenceReference?
        let shorthand: String?

        init(from decoder: any Decoder) throws {
            let container = try decoder.singleValueContainer()
            if let id = try? container.decode(String.self) {
                explicit = nil; shorthand = id
            } else {
                explicit = try container.decode(ReviewEvidenceReference.self); shorthand = nil
            }
        }

        func resolve(allowed: Set<ReviewEvidenceReference>) throws -> ReviewEvidenceReference {
            if let explicit { return explicit }
            let matches = allowed.filter { $0.id == shorthand }
            guard matches.count == 1, let reference = matches.first, reference.kind == .observation else {
                throw ReviewValidationIssue(.unknownID, "report.shorthandObservationReference", field: "claims.evidence")
            }
            return reference
        }
    }

    struct Claim: Decodable {
        let subjectID: ReviewSubjectID?
        let regionID: ReviewRegionID?
        let text: String
        let type: String
        let evidence: [Reference]
        let uncertainty: String
        let contradictions: [Reference]

        private enum CodingKeys: String, CodingKey {
            case subjectID, regionID, text, type, evidence, uncertainty, contradictions
        }

        init(from decoder: any Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            subjectID = try container.decodeIfPresent(ReviewSubjectID.self, forKey: .subjectID)
            regionID = try container.decodeIfPresent(ReviewRegionID.self, forKey: .regionID)
            text = try container.decode(String.self, forKey: .text)
            type = try container.decode(String.self, forKey: .type)
            evidence = try container.decode([Reference].self, forKey: .evidence)
            uncertainty = try container.decode(String.self, forKey: .uncertainty)
            contradictions = container.contains(.contradictions) ? try container.decode([Reference].self, forKey: .contradictions) : []
        }

        func resolve(allowed: Set<ReviewEvidenceReference>) throws -> ReviewClaim {
            try .init(subjectID: subjectID, regionID: regionID, text: text, type: type,
                      evidence: evidence.map { try $0.resolve(allowed: allowed) }, uncertainty: uncertainty,
                      contradictions: contradictions.map { try $0.resolve(allowed: allowed) })
        }
    }
}
