import SwiftUI

struct CombinedReviewTechnicalDetails: View {
    let feature: CombinedReviewFeature
    let result: CombinedReviewResult
    let inspect: (String?) -> Void
    private var presentation: CombinedReviewPresentation {
        CombinedReviewPresentation(result: result)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let report = result.report {
                Text(report.incomplete ? "Review with missing evidence" : "Review").font(.headline)
                if report.claims.isEmpty {
                    Text("Insufficient validated evidence for a synthesized claim. Inspect the completed stages below.")
                }
                ForEach(presentation.findings) { claim in
                    VStack(alignment: .leading, spacing: 3) {
                        Text(claim.text).textSelection(.enabled)
                        if let subject = claim.subjectID {
                            Text("Subject: " + subject.rawValue).font(.caption2).textSelection(.enabled)
                        }
                        if let region = claim.regionID {
                            Text("Region: " + region.rawValue).font(.caption2).textSelection(.enabled)
                        }
                        Text(claim.uncertainty).font(.caption).foregroundStyle(.secondary)
                        Text("Evidence: " + claim.evidence.map(\.id).joined(separator: ", ")).font(.caption).textSelection(.enabled)
                        if !claim.contradictions.isEmpty {
                            Text("Conflicting evidence: \(claim.contradictions.map(\.id).formatted())").font(.caption).textSelection(.enabled)
                        }
                    }
                }
            }
            if let summary = result.evidenceOnlySummary {
                DisclosureGroup(summary.label) {
                    Text("Completed independent evidence only; model synthesis failed. This summary does not resolve conflicts or infer new findings.").font(.caption)
                    ForEach(summary.rows, id: \.reference) { row in
                        VStack(alignment: .leading, spacing: 3) {
                            Text(row.text).textSelection(.enabled)
                            Text(row.reference.id + " · " + row.availability.rawValue).font(.caption2).textSelection(.enabled)
                        }
                    }
                    ForEach(summary.limitations, id: \.self) { Text($0).font(.caption) }
                }
            }
            ForEach(result.observations, id: \.id) { observation in
                DisclosureGroup(observation.provenance.workID.rawValue.contains(":reconcile") ? "Evidence reconciliation" : observation.regionID == nil ? "Independent overview" : "Crop observation") {
                    Text(observation.text).textSelection(.enabled)
                    Text(observation.uncertainty).foregroundStyle(.secondary)
                    Text(observation.id.rawValue).font(.caption2).textSelection(.enabled)
                    Button("Inspect exact input") { inspect(observation.provenance.inputReference) }
                }
            }
            ForEach(result.regions, id: \.id) { region in
                DisclosureGroup("\(CombinedReviewPresentation.regionName(region, subjects: result.subjects)) · \(Int(region.sourceRect.width)) × \(Int(region.sourceRect.height))") {
                    Text(region.purpose).font(.caption).textSelection(.enabled)
                    Text("Source crop \(Int(region.sourceRect.width)) × \(Int(region.sourceRect.height)); encoder \(Int(region.encoderSize.width)) × \(Int(region.encoderSize.height)); clipped: \(region.edgeClipped ? "yes" : "no").")
                    Button("Inspect exact crop") { inspect(region.inputReference) }
                    if let clip = result.clip[region.id.rawValue] {
                        Text("CLIP goal relevance: \(String(clip.relevance)) — uncalibrated similarity.")
                    }
                }
            }
            ForEach(result.measurements, id: \.id) { measurement in
                DisclosureGroup("Measured subject detail") {
                    if !measurement.hasCurrentMaskSemantics {
                        Text("Measurement is unqualified for current synthesis; retained for historical inspection.")
                    }
                    CombinedReviewMeasurementValues(values: measurement.values)
                    Text("Scorer: " + (measurement.scorerVersion ?? "unknown; historical measurement is unqualified")).font(.caption)
                    Text("Subject: " + measurement.subjectID.rawValue).font(.caption2).textSelection(.enabled)
                    Text(measurement.reason ?? "").font(.caption)
                    Text(measurement.id.rawValue).font(.caption2).textSelection(.enabled)
                }
            }
            DisclosureGroup("Limitations and coverage") {
                ForEach(presentation.limitations, id: \.id) { Text($0.reason).font(.caption).textSelection(.enabled) }
                ForEach(result.omissions, id: \.regionID) { omission in
                    Text(omission.regionID.rawValue + " · " + omission.reason.rawValue + ": " + omission.detail).font(.caption).textSelection(.enabled)
                }
                if let report = result.report {
                    Text("\(report.inspectedRegions.count) inspected regions; \(report.uninspectedRegions.count) uninspected.")
                }
            }
        }
    }
}

private struct CombinedReviewMeasurementValues: View {
    let values: [String: Double]
    var body: some View {
        Grid(alignment: .leading, horizontalSpacing: 20, verticalSpacing: 6) {
            ForEach(values.keys.sorted(), id: \.self) { key in
                GridRow {
                    Text(key).foregroundStyle(.secondary)
                    Text(String(values[key, default: 0])).monospacedDigit().textSelection(.enabled)
                }
            }
        }.font(.caption)
    }
}
