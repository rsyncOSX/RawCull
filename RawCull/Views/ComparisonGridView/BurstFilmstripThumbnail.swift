import OSLog
import RawCullCore
import SwiftUI

struct BurstFilmstripThumbnail: View {
    let file: FileItem
    let isSelected: Bool
    let isSuggested: Bool
    let isDeferred: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 0) {
                ThumbnailImageView(
                    file: file,
                    targetSize: 180,
                    style: .grid,
                    showsShimmer: true,
                )
                .frame(width: 132, height: 82)
                .clipped()
                .overlay(alignment: .topTrailing) {
                    if isSuggested || isDeferred {
                        Circle()
                            .fill(isSuggested ? Color.green : Color.orange)
                            .frame(width: 9, height: 9)
                            .padding(7)
                    }
                }
                Text(file.name)
                    .font(.caption2.monospaced())
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 5)
            }
            .frame(width: 132)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .compositingGroup()
        .clipShape(.rect(cornerRadius: 9))
        .overlay {
            RoundedRectangle(cornerRadius: 9)
                .stroke(
                    isSelected ? Color.accentColor : Color(nsColor: .separatorColor),
                    lineWidth: isSelected ? 3 : 1,
                )
        }
    }
}
