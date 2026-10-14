import SwiftUI

struct CombinedReviewComparison: View {
    let feature: CombinedReviewFeature
    let report: ReviewSelectionReport
    let inspect: (String?) -> Void
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(report.comparability.rawValue.capitalized + " · " + report.decision.rawValue.capitalized).font(.headline)
            Text(report.reason).textSelection(.enabled)
            if !report.preferred.isEmpty {
                let names = feature.results.filter { report.preferred.contains($0.file.id) }.map { $0.file.displayName }
                Text("Shortlist: \(names.formatted())")
            }
            Button("Inspect comparison board") { inspect(feature.comparisonInputReference) }
            if report.contextPruned {
                Text("Evidence summaries were shortened to fit the model context. Full observations remain in each image's technical record.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            comparisonClaims(report)
            ForEach(report.pairReports, id: \.id) { pair in
                DisclosureGroup("Pair tradeoff · " + pair.decision.rawValue) {
                    Text(pair.reason)
                    comparisonClaims(pair)
                    Button("Inspect matched crop board") { inspect(pair.inputReference) }
                }
            }
            Text("\(report.omittedPairs) pairs uninspected; unresolved ties remain ties.").font(.caption)
        }.padding(.top, 8)
    }

    private func comparisonClaims(_ report: ReviewSelectionReport) -> some View {
        ForEach(report.claims, id: \.id) { entry in
            VStack(alignment: .leading, spacing: 4) {
                Text(entry.claim.type.capitalized + ": " + entry.claim.text).textSelection(.enabled)
                Text(entry.claim.uncertainty).font(.caption).foregroundStyle(.secondary)
                if !entry.claim.contradictions.isEmpty {
                    Text("Conflicting evidence: " + entry.claim.contradictions.map(\.id).joined(separator: ", ")).font(.caption)
                }
                ForEach(entry.claim.evidence, id: \.self) { reference in
                    if let value = feature.results.first(where: { $0.observations.contains { $0.id.rawValue == reference.id } || $0.measurements.contains { $0.id.rawValue == reference.id } }) {
                        let input = value.observations.first { $0.id.rawValue == reference.id }?.provenance.inputReference
                        Button("Evidence · " + value.file.displayName + " · " + reference.id) { inspect(input) }.font(.caption)
                    }
                }
            }
        }
    }
}
