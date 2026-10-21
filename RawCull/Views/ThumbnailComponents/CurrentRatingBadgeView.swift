import SwiftUI

extension RatingDisplay {
    var color: Color {
        switch self {
        case .unrated: .secondary
        case .rejected: .red
        case .keeper: .accentColor
        case .stars(2): .yellow
        case .stars(3): .green
        case .stars(4): .blue
        case .stars: .purple
        }
    }
}

struct CurrentRatingBadgeView: View {
    let rating: RatingDisplay
    var density: ImageOverlayControlDensity = .regular

    var body: some View {
        HStack(spacing: density == .compact ? 3 : 5) {
            switch rating {
            case .stars:
                Image(systemName: "star.fill")
                    .font(.system(size: iconSize, weight: .semibold))

            case .rejected:
                Image(systemName: "xmark")
                    .font(.system(size: iconSize, weight: .semibold))

            case .keeper:
                Image(systemName: "checkmark")
                    .font(.system(size: iconSize, weight: .semibold))

            case .unrated:
                Image(systemName: "circle")
                    .font(.system(size: iconSize - 1, weight: .semibold))
            }

            Text(rating.label)
                .font(.system(size: labelSize, weight: .semibold, design: .monospaced))
        }
        .foregroundStyle(.white)
        .padding(.horizontal, density == .compact ? 5 : 9)
        .padding(.vertical, density == .compact ? 3 : 5)
        .background(rating.color.opacity(0.85), in: Capsule())
        .help(rating.help)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Current rating")
        .accessibilityValue(rating.help)
    }

    private var iconSize: CGFloat {
        density == .compact ? 8 : 10
    }

    private var labelSize: CGFloat {
        density == .compact ? 9 : 12
    }
}

struct ImagePixelDimensionsBadgeView: View {
    let width: Int
    let height: Int

    var body: some View {
        Text(verbatim: "\(width) × \(height) px")
            .font(.system(size: 12, weight: .semibold, design: .monospaced))
            .foregroundStyle(.white)
            .padding(.horizontal, 9)
            .padding(.vertical, 5)
            .background(Color.secondary.opacity(0.85), in: Capsule())
            .accessibilityLabel("Image dimensions")
            .accessibilityValue("\(width) by \(height) pixels")
    }
}
