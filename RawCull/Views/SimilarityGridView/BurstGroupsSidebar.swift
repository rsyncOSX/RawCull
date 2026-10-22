import OSLog
import SwiftUI

struct BurstGroupsSidebar: View {
    let summary: BurstReviewSummary
    let resultsAreAvailable: Bool
    let showResults: (BurstReviewQueueFilter) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            HStack(spacing: 12) {
                Text("C")
                    .font(.headline)
                    .foregroundStyle(.white)
                    .frame(width: 40, height: 40)
                    .background(Color.accentColor, in: .rect(cornerRadius: 10))
                VStack(alignment: .leading, spacing: 3) {
                    Text("Culling").font(.headline)
                    Text("Burst Groups").foregroundStyle(.secondary)
                }
            }

            sidebarSection("WORKFLOW") {
                BurstSidebarRow(title: "Overview", systemImage: "house", isSelected: true) {}
                BurstSidebarRow(title: "All bursts", count: summary.burstGroups, systemImage: "square.grid.2x2") {
                    showResults(.all)
                }
                .disabled(!resultsAreAvailable)
                BurstSidebarRow(title: "Needs review", count: summary.needsReview, countColor: .orange, systemImage: "exclamationmark.triangle") {
                    showResults(.needsReview)
                }
                BurstSidebarRow(title: "Completed", count: summary.completed, countColor: .green, systemImage: "checkmark.circle") {
                    showResults(.reviewed)
                }
                BurstSidebarRow(title: "Single images", count: summary.singleImages, countColor: .blue, systemImage: "photo") {
                    showResults(.singleImages)
                }
            }
            .disabled(!resultsAreAvailable)

            Spacer()
        }
        .padding(24)
        .background(Color(nsColor: .underPageBackgroundColor))
    }

    private func sidebarSection(
        _ title: String,
        @ViewBuilder content: () -> some View,
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.caption.monospaced())
                .foregroundStyle(.secondary)
                .padding(.horizontal, 8)
            content()
        }
    }
}
