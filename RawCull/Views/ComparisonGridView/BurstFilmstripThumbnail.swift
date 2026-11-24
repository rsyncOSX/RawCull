import OSLog
import RawCullCore
import SwiftUI

struct BurstFilmstripThumbnail: View {
    static let width: CGFloat = 132
    let file: FileItem
    let isSelected: Bool
    let isSuggested: Bool
    let isDeferred: Bool
    var isIncludedInCloseUps = false
    var marks = BurstFrameMarks()
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
                .frame(width: Self.width, height: 82)
                .clipped()
                .overlay(alignment: .topTrailing) {
                    if isSuggested || isDeferred {
                        Circle()
                            .fill(isSuggested ? Color.green : Color.orange)
                            .frame(width: 9, height: 9)
                            .padding(7)
                    }
                }
                .overlay(alignment: .topLeading) {
                    if marks.isSharpest {
                        Text("Sharpest")
                            .font(.caption2.weight(.semibold))
                            .padding(.horizontal, 5)
                            .padding(.vertical, 3)
                            .background(.regularMaterial, in: .rect(cornerRadius: 4))
                            .padding(5)
                            .help("Highest measured sharpness in this burst.")
                    }
                }
                .overlay(alignment: .bottomTrailing) {
                    if let score = marks.aiScore {
                        aiChip(score: score)
                    }
                }
                Text(file.name)
                    .lineLimit(1)
                    .font(.caption2.monospaced())
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 5)
            }
            .frame(width: Self.width)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .compositingGroup()
        .clipShape(.rect(cornerRadius: 9))
        .overlay {
            RoundedRectangle(cornerRadius: 9)
                .stroke(
                    isSelected || isIncludedInCloseUps ? Color.accentColor : Color(nsColor: .separatorColor),
                    lineWidth: isSelected ? 3 : (isIncludedInCloseUps ? 2 : 1),
                )
        }
    }

    private func aiChip(score: Double) -> some View {
        let value = BurstFrameMarks.formatted(score)
        return Label(marks.isAITop ? "AI top \(value)" : "AI \(value)", systemImage: "sparkles")
            .font(.caption2.weight(.semibold))
            .monospacedDigit()
            .foregroundStyle(marks.isAITop ? Color.white : Color.primary)
            .padding(.horizontal, 5)
            .padding(.vertical, 3)
            .background {
                if marks.isAITop {
                    RoundedRectangle(cornerRadius: 4).fill(Color.purple)
                } else {
                    RoundedRectangle(cornerRadius: 4).fill(.regularMaterial)
                }
            }
            .padding(5)
            .help(marks.isAITop
                ? "Highest AI assessment score in this burst (mean of rubric scores, 1–5)."
                : "AI assessment score (mean of rubric scores, 1–5).")
    }
}
