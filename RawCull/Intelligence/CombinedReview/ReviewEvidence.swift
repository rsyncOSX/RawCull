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
    let id: ReviewObservationID
    let regionID: ReviewRegionID?
    let text: String
    let uncertainty: String
    let availability: ReviewEvidenceAvailability
    let provenance: ReviewEvidenceProvenance
}

nonisolated struct ReviewMeasurement: Codable, Sendable {
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
    let text: String
    let type: String
    let evidence: [ReviewEvidenceReference]
    let uncertainty: String
    let contradictions: [ReviewEvidenceReference]

    func validate(allowed: Set<ReviewEvidenceReference>) throws {
        guard !text.isEmpty, !evidence.isEmpty,
              Set(evidence + contradictions).isSubset(of: allowed) else { throw ReviewRunError.invalidEvidence }
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
        guard !reason.isEmpty, reason.count <= 500, Set(preferred).isSubset(of: ids), Set(preferred).count == preferred.count,
              decision != .preferred || (comparability == .comparable && preferred.count == 1),
              decision != .tie || (comparability == .comparable && preferred.count >= 2),
              decision != .abstain || preferred.isEmpty,
              comparability == .comparable || (decision == .abstain && preferred.isEmpty), claims.count <= 6 else { throw ReviewRunError.invalidEvidence }
        guard results.allSatisfy({ value in
            value.observations.allSatisfy { $0.provenance.imageID == value.file.id } &&
                value.measurements.allSatisfy { measurement in
                    measurement.provenance.imageID == value.file.id && value.subjects.contains { $0.id == measurement.subjectID }
                }
        }) else { throw ReviewRunError.invalidEvidence }
        let evidence = Dictionary(uniqueKeysWithValues: results.map { value in
            (value.file.id, Set(value.observations.filter { $0.availability == .available && !$0.provenance.workID.rawValue.contains(":reconcile") }.map { ReviewEvidenceReference(kind: .observation, id: $0.id.rawValue) }
                    + value.measurements.filter { $0.availability == .available }.map { ReviewEvidenceReference(kind: .measurement, id: $0.id.rawValue) }))
        })
        for entry in claims {
            let referenced = Set(entry.imageIDs)
            guard !referenced.isEmpty, referenced.count == entry.imageIDs.count, referenced.isSubset(of: ids),
                  ["composition", "exposure", "visibility", "detail", "suggestion"].contains(entry.claim.type) else { throw ReviewRunError.invalidEvidence }
            try entry.claim.validate(allowed: referenced.reduce(into: Set<ReviewEvidenceReference>()) { $0.formUnion(evidence[$1] ?? []) })
            // Each named image must contribute evidence; a finding from A cannot support a comparison about B.
            for id in referenced {
                guard entry.claim.evidence.contains(where: { evidence[id]?.contains($0) == true }) else { throw ReviewRunError.invalidEvidence }
            }
            guard entry.claim.text.count <= 500, entry.claim.uncertainty.count <= 200 else { throw ReviewRunError.invalidEvidence }
            let lower = entry.claim.text.lowercased()
            guard !["eye", "iris", "gaze", "recover", "same individual", "same animal", "same person"].contains(where: lower.contains) else { throw ReviewRunError.invalidEvidence }
            if entry.claim.type == "detail" || ["sharp", "blur", "soft", "focus"].contains(where: lower.contains) {
                let sources = results.filter { referenced.contains($0.file.id) }.compactMap(\.source)
                guard sources.count == referenced.count, Set(sources.map(\.fidelity)).count == 1, Set(sources.map(\.policy)).count == 1,
                      Set(sources.map { "\($0.width)x\($0.height)" }).count == 1 else { throw ReviewRunError.invalidEvidence }
                var regions: [ReviewRegionRecord] = []
                for id in referenced {
                    guard let value = results.first(where: { $0.file.id == id }) else { throw ReviewRunError.invalidEvidence }
                    let detail = Set(value.observations.filter { $0.regionID != nil }.map { ReviewEvidenceReference(kind: .observation, id: $0.id.rawValue) })
                    guard entry.claim.evidence.contains(where: detail.contains) else { throw ReviewRunError.invalidEvidence }
                    let used = value.observations.filter { observation in
                        entry.claim.evidence.contains(.init(kind: .observation, id: observation.id.rawValue)) && observation.regionID != nil
                    }
                    for observation in used {
                        guard let region = value.regions.first(where: { $0.id == observation.regionID }), region.intendedRegionRetained else { throw ReviewRunError.invalidEvidence }
                        regions.append(region)
                    }
                }
                guard let first = regions.first, regions.allSatisfy({ region in
                    abs(region.scaleX / first.scaleX - 1) <= 0.1 && abs(region.scaleY / first.scaleY - 1) <= 0.1
                }) else { throw ReviewRunError.invalidEvidence }
            }
        }
        if decision == .preferred {
            guard claims.allSatisfy({ $0.claim.contradictions.isEmpty }) else { throw ReviewRunError.invalidEvidence }
        }
        if decision != .abstain {
            guard !claims.isEmpty, results.allSatisfy({ $0.report?.incomplete == false }),
                  Set(claims.flatMap(\.imageIDs)).isSuperset(of: ids) else { throw ReviewRunError.invalidEvidence }
        }
    }
}
