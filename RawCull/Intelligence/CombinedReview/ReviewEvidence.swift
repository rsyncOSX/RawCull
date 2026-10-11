import Foundation

nonisolated enum ReviewEvidenceAvailability: String, Codable, Sendable {
    case available, unknown, unavailable
}

nonisolated struct ReviewEvidenceReference: Codable, Hashable, Sendable {
    enum Kind: String, Codable, Sendable { case image, subject, region, observation, measurement, limitation, report }
    let kind: Kind
    let id: String
}

nonisolated struct ReviewEvidenceProvenance: Codable, Equatable, Sendable {
    let workID: ReviewWorkID
    let imageID: ReviewImageID
    let sourceIdentity: String
    let renderPolicy: String
    let compatibility: ReviewCompatibility
    let modelIdentity: String?
    let inputReference: String?
}

nonisolated struct ReviewObservation: Codable, Sendable {
    var targetIdentified: Bool? = nil
    let id: ReviewObservationID
    let regionID: ReviewRegionID?
    let text: String
    let uncertainty: String
    let availability: ReviewEvidenceAvailability
    let provenance: ReviewEvidenceProvenance
}

nonisolated struct ReviewMeasurement: Codable, Sendable {
    var scorerVersion: String? = nil
    var maskContract: SubjectMaskContract? = nil
    var foregroundBounds: CGRect? = nil
    var hasCurrentMaskSemantics: Bool {
        availability == .available && scorerVersion == SubjectMaskFocusScorer.semanticsVersion
            && maskContract?.version == SubjectMaskContract.version
    }

    let id: ReviewMeasurementID
    let subjectID: ReviewSubjectID
    let values: [String: Double]
    let availability: ReviewEvidenceAvailability
    let reason: String?
    let provenance: ReviewEvidenceProvenance
}

nonisolated struct ReviewLimitation: Codable, Sendable {
    let id: ReviewLimitationID
    let reason: String
    let relatedEvidence: [ReviewEvidenceReference]
}

nonisolated struct ReviewClaim: Codable, Sendable {
    var subjectID: ReviewSubjectID? = nil
    var regionID: ReviewRegionID? = nil
    let text: String
    let type: String
    let evidence: [ReviewEvidenceReference]
    let uncertainty: String
    let contradictions: [ReviewEvidenceReference]

    private enum CodingKeys: String, CodingKey {
        case subjectID, regionID, text, type, evidence, uncertainty, contradictions
    }

    func validate(allowed: Set<ReviewEvidenceReference>) throws {
        guard !text.isEmpty, !evidence.isEmpty,
              Set(evidence + contradictions).isSubset(of: allowed) else { throw ReviewRunError.invalidEvidence }
    }
}

extension ReviewClaim {
    nonisolated init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        subjectID = try container.decodeIfPresent(ReviewSubjectID.self, forKey: .subjectID)
        regionID = try container.decodeIfPresent(ReviewRegionID.self, forKey: .regionID)
        text = try container.decode(String.self, forKey: .text)
        type = try container.decode(String.self, forKey: .type)
        evidence = try container.decode([ReviewEvidenceReference].self, forKey: .evidence)
        uncertainty = try container.decode(String.self, forKey: .uncertainty)
        // Absence asserts no conflict. Present null, malformed arrays and references remain errors.
        contradictions = container.contains(.contradictions) ? try container.decode([ReviewEvidenceReference].self, forKey: .contradictions) : []
    }
}

nonisolated struct ReviewImageReport: Codable, Sendable {
    let id: ReviewReportID
    let imageID: ReviewImageID
    let claims: [ReviewClaim]
    let limitations: [ReviewLimitation]
    let incomplete: Bool
    let inspectedRegions: [ReviewRegionID]
    let uninspectedRegions: [ReviewRegionID]
}

/// Payload type is explicit per stage; malformed photographic responses never
/// become findings. Stage consumers validate IDs against their own evidence set.
nonisolated struct ReviewStageArtifact: Codable, Sendable {
    let workID: ReviewWorkID
    let compatibility: ReviewCompatibility
    let payload: Data
    let created: Date
}

nonisolated struct ReviewSourceRecord: Codable, Sendable {
    let imageID: ReviewImageID
    let sourceIdentity: String
    let width: Int
    let height: Int
    let orientation: UInt32
    let fidelity: String
    let policy: String
    let colorSpace: String
    let renderSettings: [String: String]
    let limitations: [String]
}

nonisolated struct ReviewSubjectRecord: Codable, Sendable {
    var maskContract: SubjectMaskContract? = nil
    var registration: ReviewMaskRegistration? = nil
    var relevance: ReviewSubjectRelevance? = nil
    let id: ReviewSubjectID
    let imageID: ReviewImageID
    let concept: String
    let normalizedBounds: CGRect
    let maskConfidence: Float
    let aliases: [String]
    let maskInputReference: String?
    let availability: ReviewEvidenceAvailability
}

nonisolated struct ReviewRegionRecord: Codable, Sendable {
    var support: ReviewCropSupport? = nil
    let id: ReviewRegionID
    let imageID: ReviewImageID
    let subjectID: ReviewSubjectID?
    let sourceIdentity: String
    let purpose: String
    let requestedRect: CGRect
    let paddedRect: CGRect
    let sourceRect: CGRect
    let retainedSourceRect: CGRect
    let encoderSize: CGSize
    let scaleX: Double
    let scaleY: Double
    let edgeClipped: Bool
    let intendedRegionRetained: Bool
    let fidelity: String
    let policy: String
    let inputReference: String?
}

nonisolated enum ReviewComparability: String, Codable, Sendable {
    case comparable, unrelated, insufficient
}

nonisolated enum ReviewSelectionDecision: String, Codable, Sendable {
    case preferred, tie, abstain
}

nonisolated struct ReviewComparisonClaim: Codable, Sendable {
    var id = UUID().uuidString
    let imageIDs: [ReviewImageID]
    let claim: ReviewClaim
}

nonisolated struct ReviewBoardCell: Codable, Sendable {
    let imageID: ReviewImageID
    /// Top-left board coordinates, after orientation normalization.
    let rect: CGRect
    let sourceWidth: Int
    let sourceHeight: Int
}

nonisolated struct ReviewSelectionReport: Codable, Sendable {
    var id = UUID().uuidString
    let comparability: ReviewComparability
    let decision: ReviewSelectionDecision
    let preferred: [ReviewImageID]
    let claims: [ReviewComparisonClaim]
    let reason: String
    var cells: [ReviewBoardCell] = []
    var inputReference: String?
    var omittedPairs: Int = 0
    var contextPruned = false
    var pairReports: [ReviewSelectionReport] = []

    static func decode(_ response: String) throws -> Self {
        struct Payload: Decodable {
            let comparability: ReviewComparability
            let decision: ReviewSelectionDecision
            let preferred: [ReviewImageID]
            struct Entry: Decodable { let imageIDs: [ReviewImageID]; let claim: ReviewClaim }
            let claims: [Entry]
            let reason: String
        }
        let value = try ObjectJSONEnvelope.decode(Payload.self, from: response)
        return .init(comparability: value.comparability, decision: value.decision, preferred: value.preferred, claims: value.claims.map { .init(imageIDs: $0.imageIDs, claim: $0.claim) }, reason: value.reason)
    }

    func validate(results: [CombinedReviewResult]) throws {
        let ids = Set(results.map { $0.file.id })
        guard !reason.isEmpty else { throw ReviewValidationIssue(.schema, "comparison.reasonRequired", field: "reason") }
        guard reason.count <= 500, claims.count <= 6 else { throw ReviewValidationIssue(.responseLength, "comparison.responseAllowance") }
        guard Set(preferred).isSubset(of: ids), Set(preferred).count == preferred.count else { throw ReviewValidationIssue(.unknownID, "comparison.preferredImageIDs", field: "preferred") }
        guard decision != .preferred || (comparability == .comparable && preferred.count == 1),
              decision != .tie || (comparability == .comparable && preferred.count >= 2),
              decision != .abstain || preferred.isEmpty,
              comparability == .comparable || (decision == .abstain && preferred.isEmpty) else { throw ReviewValidationIssue(.grounding, "comparison.decisionConsistency", field: "decision") }
        guard results.allSatisfy({ value in
            value.observations.allSatisfy { $0.provenance.imageID == value.file.id } &&
                value.measurements.allSatisfy { measurement in
                    measurement.provenance.imageID == value.file.id && value.subjects.contains { $0.id == measurement.subjectID }
                }
        }) else { throw ReviewValidationIssue(.ownership, "comparison.imageSubjectOwnership", field: "claims.evidence") }
        let evidence = Dictionary(uniqueKeysWithValues: results.map { value in
            (value.file.id, Set(value.observations.filter { $0.availability == .available && !$0.provenance.workID.rawValue.contains(":reconcile") }.map { ReviewEvidenceReference(kind: .observation, id: $0.id.rawValue) }
                    + value.measurements.filter { $0.hasCurrentMaskSemantics }.map { ReviewEvidenceReference(kind: .measurement, id: $0.id.rawValue) }))
        })
        for entry in claims {
            let referenced = Set(entry.imageIDs)
            guard !referenced.isEmpty, referenced.count == entry.imageIDs.count, referenced.isSubset(of: ids) else { throw ReviewValidationIssue(.unknownID, "comparison.claimImageIDs", field: "claims.imageIDs") }
            guard ["composition", "exposure", "visibility", "detail", "suggestion"].contains(entry.claim.type) else { throw ReviewValidationIssue(.unsupportedDomain, "comparison.claimType", field: "claims.type") }
            let allowed = referenced.reduce(into: Set<ReviewEvidenceReference>()) { $0.formUnion(evidence[$1] ?? []) }
            let known = evidence.values.reduce(into: Set<ReviewEvidenceReference>()) { $0.formUnion($1) }
            guard !entry.claim.evidence.isEmpty else { throw ReviewValidationIssue(.grounding, "comparison.evidenceRequired", field: "claims.evidence") }
            guard Set(entry.claim.evidence + entry.claim.contradictions).isSubset(of: known) else { throw ReviewValidationIssue(.unknownID, "comparison.knownReference", field: "claims.evidence") }
            guard Set(entry.claim.evidence + entry.claim.contradictions).isSubset(of: allowed) else { throw ReviewValidationIssue(.ownership, "comparison.referenceOwnership", field: "claims.evidence") }
            // Each named image must contribute evidence; a finding from A cannot support a comparison about B.
            for id in referenced {
                guard entry.claim.evidence.contains(where: { evidence[id]?.contains($0) == true }) else { throw ReviewValidationIssue(.ownership, "comparison.eachImageContributes", field: "claims.imageIDs") }
            }
            guard entry.claim.text.count <= 500, entry.claim.uncertainty.count <= 200 else { throw ReviewValidationIssue(.responseLength, "comparison.claimTextAllowance", field: "claims.text") }
            let lower = entry.claim.text.lowercased()
            guard !["eye", "iris", "gaze", "recover", "same individual", "same animal", "same person"].contains(where: lower.contains) else { throw ReviewValidationIssue(.unsupportedDomain, "comparison.supportedDomain", field: "claims.text") }
            if entry.claim.type == "detail" || ["sharp", "blur", "soft", "focus"].contains(where: lower.contains) {
                let sources = results.filter { referenced.contains($0.file.id) }.compactMap(\.source)
                guard sources.count == referenced.count, Set(sources.map(\.fidelity)).count == 1, Set(sources.map(\.policy)).count == 1,
                      Set(sources.map { "\($0.width)x\($0.height)" }).count == 1 else { throw ReviewValidationIssue(.geometry, "comparison.matchedSourceFidelity", field: "claims.evidence") }
                var regions: [ReviewRegionRecord] = []
                for id in referenced {
                    guard let value = results.first(where: { $0.file.id == id }) else { throw ReviewValidationIssue(.unknownID, "comparison.existingImage", field: "claims.imageIDs") }
                    let detail = Set(value.observations.filter { $0.regionID != nil }.map { ReviewEvidenceReference(kind: .observation, id: $0.id.rawValue) })
                    guard entry.claim.evidence.contains(where: detail.contains) else { throw ReviewValidationIssue(.grounding, "comparison.detailNeedsCrop", field: "claims.evidence") }
                    let used = value.observations.filter { observation in
                        entry.claim.evidence.contains(.init(kind: .observation, id: observation.id.rawValue)) && observation.regionID != nil
                    }
                    for observation in used {
                        guard let region = value.regions.first(where: { $0.id == observation.regionID }), region.intendedRegionRetained, region.subjectID == nil || region.support?.qualifiesWholeSubject == true else { throw ReviewValidationIssue(.geometry, "comparison.retainedForeground", field: "claims.evidence") }
                        regions.append(region)
                    }
                }
                guard let first = regions.first, regions.allSatisfy({ region in
                    abs(region.scaleX / first.scaleX - 1) <= 0.1 && abs(region.scaleY / first.scaleY - 1) <= 0.1
                }) else { throw ReviewValidationIssue(.geometry, "comparison.matchedScale", field: "claims.evidence") }
            }
        }
        if decision == .preferred {
            guard claims.allSatisfy({ $0.claim.contradictions.isEmpty }) else { throw ReviewValidationIssue(.grounding, "comparison.preferenceWithoutConflict", field: "claims.contradictions") }
        }
        if decision != .abstain {
            guard !claims.isEmpty, results.allSatisfy({ $0.report?.incomplete == false }),
                  Set(claims.flatMap(\.imageIDs)).isSuperset(of: ids) else { throw ReviewValidationIssue(.grounding, "comparison.completeReportCoverage", field: "claims") }
        }
    }
}
