import OSLog
import SwiftUI

struct BurstRecentGroupsEmptyState: View {
    let resultsAreAvailable: Bool

    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: "photo.stack")
                .font(.system(size: 42, weight: .light))
                .foregroundStyle(.secondary)
            Text(resultsAreAvailable ? "No recent groups" : "No burst groups yet")
                .font(.title3.weight(.medium))
            Text(resultsAreAvailable
                ? "Open a review queue to continue culling."
                : "Run Find Burst Groups to create your first review queue.")
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, minHeight: 165)
        .background(.quaternary.opacity(0.35), in: .rect(cornerRadius: 12))
        .overlay {
            RoundedRectangle(cornerRadius: 12)
                .stroke(.separator.opacity(0.65), lineWidth: 1)
        }
        .accessibilityElement(children: .combine)
    }
}
