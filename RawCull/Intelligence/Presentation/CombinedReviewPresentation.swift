import Foundation

/// Presentation only: never turns model observations or uncalibrated metrics into a quality score.
nonisolated struct CombinedReviewFinding: Identifiable, Sendable {
    let id: String
    let type: String
    let text: String
    let uncertainty: String
    let evidence: [ReviewEvidenceReference]
    let contradictions: [ReviewEvidenceReference]
    let subjectID: ReviewSubjectID?
    let regionID: ReviewRegionID?
    let isObservationOnly: Bool

    var title: LocalizedStringResource {
        switch type {
        case "composition": "Framing"
        case "exposure": "Lighting"
        case "visibility": "Subject visibility"
        case "detail": "Visible detail"
        case "suggestion": "Suggestion"
        default: "Model observation"
        }
    }
}

nonisolated struct CombinedReviewPresentation: Sendable {
    let findings: [CombinedReviewFinding]
    let limitations: [ReviewLimitation]
    let importantLimits: [String]
    let inspectedCount: Int?
    let uninspectedCount: Int?
    let incomplete: Bool

    init(result: CombinedReviewResult) {
        if let report = result.report, !report.claims.isEmpty {
            findings = report.claims.map { claim in
                CombinedReviewFinding(
                    id: report.id.rawValue + ":" + ReviewCompatibility.digest(
                        claim.type + "|" + claim.text + "|" + claim.evidence.map(\.id).joined(separator: "|"),
                    ),
                    type: claim.type, text: claim.text, uncertainty: claim.uncertainty,
                    evidence: claim.evidence, contradictions: claim.contradictions,
                    subjectID: claim.subjectID, regionID: claim.regionID,
                    isObservationOnly: false,
                )
            }
        } else {
            // Failed synthesis can still expose available observations, explicitly as observations.
            findings = result.observations.filter { $0.availability == .available }.map { observation in
                CombinedReviewFinding(
                    id: observation.id.rawValue, type: "observation", text: observation.text,
                    uncertainty: observation.uncertainty,
                    evidence: [.init(kind: .observation, id: observation.id.rawValue)],
                    contradictions: [], subjectID: nil, regionID: observation.regionID,
                    isObservationOnly: true,
                )
            }
        }
        var seen: Set<String> = []
        limitations = (result.limitations + (result.report?.limitations ?? [])).filter {
            seen.insert($0.reason).inserted
        }
        let reasons = limitations.map(\.reason) + (result.source?.limitations ?? [])
        // Surface only known, decision-relevant limits; original wording remains in the full record.
        var notices: [String] = []
        if reasons.contains(where: { $0.hasPrefix("Preview reduced") }) {
            notices.append(String(localized: "Reduced preview limits fine-detail evidence."))
        }
        if reasons.contains(where: { $0.hasPrefix("Eye localization unavailable") }) {
            notices.append(String(localized: "Eye detail could not be assessed."))
        }
        if reasons.contains(where: { $0.hasPrefix("AF mapping is unavailable") }) {
            notices.append(String(localized: "AF point mapping is unavailable."))
        }
        if reasons.contains(where: { $0.hasPrefix("Main-subject priority is ambiguous") }) {
            notices.append(String(localized: "Main-subject priority is unassigned."))
        }
        if findings.contains(where: { !$0.contradictions.isEmpty }) {
            notices.append(String(localized: "Some findings have conflicting evidence."))
        }
        importantLimits = notices
        inspectedCount = result.report?.inspectedRegions.count
        uninspectedCount = result.report?.uninspectedRegions.count
        incomplete = result.report?.incomplete != false || !result.failures.isEmpty ||
            !(result.report?.uninspectedRegions.isEmpty ?? true)
    }

    static func selectedResult(in results: [CombinedReviewResult], fileID: UUID?) -> CombinedReviewResult? {
        guard let fileID else { return results.first }
        // Never show another photo's findings when the selected photo hasn't been reviewed.
        return results.first { $0.file.fileID == fileID }
    }

    static func supportingRegion(for finding: CombinedReviewFinding, in result: CombinedReviewResult) -> ReviewRegionID? {
        if let id = finding.regionID, result.regions.contains(where: { $0.id == id }) {
            return id
        }
        for reference in finding.evidence {
            if reference.kind == .region, let region = result.regions.first(where: { $0.id.rawValue == reference.id }) {
                return region.id
            }
            if reference.kind == .observation,
               let observation = result.observations.first(where: { $0.id.rawValue == reference.id }),
               let id = observation.regionID, result.regions.contains(where: { $0.id == id })
            {
                return id
            }
        }
        return nil
    }

    static func regionName(_ region: ReviewRegionRecord, subjects: [ReviewSubjectRecord]) -> String {
        // Purpose may contain pipeline diagnostics. Keep it intact in the technical record.
        let concept = subjects.first { $0.id == region.subjectID }?.concept
        return concept ?? String(localized: "Reviewed region")
    }
}

/// A complete copyable record preserves precision and provenance outside the compact presentation.
nonisolated struct CombinedReviewTechnicalRecord: Encodable {
    let file: ReviewFileSnapshot
    let source: ReviewSourceRecord?
    let overview: CombinedReviewOverview?
    let subjects: [ReviewSubjectRecord]
    let regions: [ReviewRegionRecord]
    let omissions: [ReviewRegionOmission]
    let observations: [ReviewObservation]
    let measurements: [ReviewMeasurement]
    let clip: [String: CombinedReviewCLIPResult]
    let report: ReviewImageReport?
    let limitations: [ReviewLimitation]
    let failures: [String: String]
    let evidenceOnlySummary: ReviewEvidenceOnlySummary?
    let overviewInputReference: String?

    init(_ result: CombinedReviewResult) {
        file = result.file; source = result.source; overview = result.overview
        subjects = result.subjects; regions = result.regions; omissions = result.omissions
        observations = result.observations; measurements = result.measurements; clip = result.clip
        report = result.report; limitations = result.limitations; failures = result.failures
        evidenceOnlySummary = result.evidenceOnlySummary; overviewInputReference = result.overviewInputReference
    }

    func json() throws -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try String(decoding: encoder.encode(self), as: UTF8.self)
    }
}
