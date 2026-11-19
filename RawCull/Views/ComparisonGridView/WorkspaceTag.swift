import OSLog
import RawCullCore
import SwiftUI

struct WorkspaceTag: View {
    let title: String
    let color: Color

    var body: some View {
        Text(title)
            .font(.caption.weight(.semibold))
            .padding(.horizontal, 9)
            .padding(.vertical, 5)
            .foregroundStyle(color)
            .background(color.opacity(0.13), in: .rect(cornerRadius: 7))
            .overlay { RoundedRectangle(cornerRadius: 7).stroke(color.opacity(0.5), lineWidth: 1) }
    }
}

/// Consistent image status badges for the burst workspace and assessment comparison.
struct WorkspaceImageBadges: View {
    let image: CGImage?
    let rating: RatingDisplay?
    let isSuggested: Bool
    let subjectLabel: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let image {
                ImagePixelDimensionsBadgeView(width: image.width, height: image.height)
            }
            if let rating {
                WorkspaceTag(title: rating.label, color: rating.color)
            }
            if isSuggested {
                WorkspaceTag(title: "Suggested", color: .orange)
            }
            if let subjectLabel {
                WorkspaceTag(title: subjectLabel, color: .cyan)
            }
        }
        .allowsHitTesting(false)
    }
}
