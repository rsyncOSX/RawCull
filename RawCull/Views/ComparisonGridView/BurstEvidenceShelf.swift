import OSLog
import RawCullCore
import SwiftUI

struct BurstEvidenceShelf: View {
    let file: FileItem
    let image: NSImage?
    let rating: RatingDisplay
    let rank: Int
    let frameCount: Int
    let sharpness: Float?
    let overallScore: Float?
    let exif: ExifSummary

    var body: some View {
        VStack(spacing: 6) {
            HStack(spacing: 16) {
                HStack(spacing: 9) {
                    Text(file.name)
                        .font(.callout.weight(.semibold).monospaced())
                        .lineLimit(1)

                    evidenceBadge("#\(rank) / \(frameCount)", color: .secondary)
                }

                Divider().frame(height: 34)

                VStack(alignment: .trailing, spacing: 3) {
                    scoreRow("Sharpness", value: sharpness)
                    scoreRow("Overall", value: overallScore)
                }
                .frame(minWidth: 108)

                HistogramView(nsImage: image, height: 42)
                    .frame(width: 110)
                    .accessibilityLabel("Luminance histogram")

                VStack(alignment: .trailing, spacing: 3) {
                    Text(exif.exposureParts.joined(separator: "   "))
                    Text(exif.gearParts.joined(separator: "   "))
                        .foregroundStyle(.secondary)
                }
                .font(.caption.monospaced())
                .lineLimit(1)
                .frame(maxWidth: 560, alignment: .trailing)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 9)
        .background(.regularMaterial, in: .rect(cornerRadius: 9))
        .overlay {
            RoundedRectangle(cornerRadius: 9)
                .stroke(.white.opacity(0.15), lineWidth: 1)
        }
        .shadow(color: .black.opacity(0.28), radius: 12, y: 4)
        .accessibilityElement(children: .contain)
    }

    private func scoreRow(_ title: String, value: Float?) -> some View {
        HStack(spacing: 6) {
            Text(title).foregroundStyle(.secondary)
            Text(value.map(percent) ?? "—")
                .fontWeight(.semibold)
                .monospacedDigit()
        }
        .font(.caption)
    }

    private func percent(_ value: Float) -> String {
        value.formatted(.percent.precision(.fractionLength(0)))
    }

    private func evidenceBadge(_ title: String, color: Color) -> some View {
        Text(title)
            .font(.caption2.weight(.semibold).monospaced())
            .foregroundStyle(color)
            .padding(.horizontal, 7)
            .padding(.vertical, 4)
            .background(color.opacity(0.13), in: .rect(cornerRadius: 5))
            .overlay {
                RoundedRectangle(cornerRadius: 5)
                    .stroke(color.opacity(0.45), lineWidth: 1)
            }
    }
}
