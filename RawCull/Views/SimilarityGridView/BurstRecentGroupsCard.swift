import OSLog
import SwiftUI

struct BurstRecentGroupsCard: View {
    let picks: [BurstSuggestedPick]
    let action: (BurstSuggestedPick) -> Void

    var body: some View {
        HStack(spacing: 14) {
            ForEach(picks) { pick in
                Button { action(pick) } label: {
                    VStack(alignment: .leading, spacing: 8) {
                        ThumbnailImageView(
                            file: pick.file,
                            targetSize: 220,
                            style: .grid,
                            showsShimmer: true,
                        )
                        .frame(maxWidth: .infinity, minHeight: 100, maxHeight: 130)
                        .clipped()

                        Text("Burst \(pick.groupID + 1, format: .number)")
                            .font(.headline.monospaced())
                        Text(pick.subject ?? pick.file.name)
                            .font(.callout)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(10)
                    .contentShape(.rect)
                }
                .buttonStyle(.plain)
                .background(.quaternary.opacity(0.35), in: .rect(cornerRadius: 12))
                .overlay {
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(.separator.opacity(0.65), lineWidth: 1)
                }
            }
        }
    }
}
