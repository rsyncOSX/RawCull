import AppKit
import SwiftUI

struct ObjectPhotoResultsTable: View {
    let results: [ObjectPhotoAnalysisResult]
    @Binding var selection: UUID?

    var body: some View {
        Table(results, selection: $selection) {
            TableColumn("File") { result in Text(result.fileName).lineLimit(1) }
            TableColumn("Objects") { result in Text(result.instances.count.formatted()) }
                .width(65)
            TableColumn("Concepts") { result in
                Text(result.concepts.joined(separator: ", ")).lineLimit(1)
            }
            TableColumn("Qwen confidence") { result in
                Text(result.assessment?.confidence.formatted(.percent.precision(.fractionLength(0))) ?? "—")
            }
            .width(90)
            TableColumn("Status") { result in
                if result.needsAssessmentRetry {
                    AIAnalysisStatusBadge(title: "Needs retry", color: .orange)
                } else {
                    AIAnalysisStatusBadge(
                        title: result.failure == nil ? "Complete" : "Failed",
                        color: result.failure == nil ? .green : .orange)
                }
            }
        }
        .aiAnalysisTableNavigation(ids: results.map(\.fileID), selection: $selection)
        .accessibilityLabel("Object analysis results")
    }
}
