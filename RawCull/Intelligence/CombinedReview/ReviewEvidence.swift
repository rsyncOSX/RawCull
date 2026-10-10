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
