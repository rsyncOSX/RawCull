import OSLog
import SwiftUI

struct BurstGroupsHomeHeader: View {
    let maintenanceActionsAreDisabled: Bool
    let showScoringParameters: () -> Void
    let reindex: () -> Void
    let indexSimilarity: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 24) {
            VStack(alignment: .leading, spacing: 8) {
                Text("Burst Groups")
                    .font(.system(size: 34, weight: .bold))
                Text("Find the strongest frame from every sequence.")
                    .font(.title3)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer()

            Menu {
                Button(action: showScoringParameters) {
                    Label("Scoring Parameters", systemImage: "slider.horizontal.3")
                }

                Divider()

                Button(action: reindex) {
                    Label("Re-index Catalog", systemImage: "arrow.clockwise")
                }
                .disabled(maintenanceActionsAreDisabled)

                Button(action: indexSimilarity) {
                    Label("Index Similarity", systemImage: "scope")
                }
                .disabled(maintenanceActionsAreDisabled)
            } label: {
                Label("More", systemImage: "ellipsis")
            }
            .menuStyle(.button)
            .controlSize(.large)
            .help("Catalog maintenance actions")
        }
    }
}
