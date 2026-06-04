import SwiftUI

enum RatingDisplay {
    case unrated
    case rejected
    case keeper
    case stars(Int)

    init(rating: Int, isExplicit: Bool = true) {
        switch rating {
        case -1:
            self = .rejected

        case 0 where isExplicit:
            self = .keeper

        case 2 ... 5:
            self = .stars(rating)

        default:
            self = .unrated
        }
    }

    var label: String {
        switch self {
        case .unrated: "Unrated"
        case .rejected: "X"
        case .keeper: "P"
        case let .stars(rating): "\(rating)"
        }
    }

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

    var help: String {
        switch self {
        case .unrated: "Unrated"
        case .rejected: "Rejected"
        case .keeper: "Keeper"
        case let .stars(rating): "\(rating)-star rating"
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
    }

    private var iconSize: CGFloat {
        density == .compact ? 8 : 10
    }

    private var labelSize: CGFloat {
        density == .compact ? 9 : 12
    }
}

struct RatingActionBarView: View {
    let currentRating: RatingDisplay
    var density: ImageOverlayControlDensity = .regular
    let onSelect: (Int) -> Void

    private let ratings: [(Int, String, Color)] = [
        (-1, "X", .red),
        (0, "P", .accentColor),
        (2, "2", .yellow),
        (3, "3", .green),
        (4, "4", .blue),
        (5, "5", .purple)
    ]

    var body: some View {
        HStack(spacing: density == .compact ? 4 : 6) {
            ForEach(ratings, id: \.0) { rating, label, color in
                Button {
                    onSelect(rating)
                } label: {
                    Text(label)
                        .font(.system(size: density == .compact ? 11 : 12, weight: .semibold, design: .monospaced))
                        .foregroundStyle(isActive(rating) ? .white : color)
                        .frame(width: density == .compact ? 20 : 24, height: density == .compact ? 20 : 24)
                        .background(
                            Circle()
                                .fill(isActive(rating) ? color.opacity(0.95) : color.opacity(0.18)),
                        )
                }
                .buttonStyle(.plain)
                .help(help(for: rating))
            }
        }
        .padding(.horizontal, density == .compact ? 7 : 10)
        .padding(.vertical, density == .compact ? 4 : 7)
        .background(.regularMaterial, in: Capsule())
    }

    private func isActive(_ rating: Int) -> Bool {
        switch (currentRating, rating) {
        case (.rejected, -1), (.keeper, 0):
            true

        case let (.stars(current), rating):
            current == rating

        default:
            false
        }
    }

    private func help(for rating: Int) -> String {
        switch rating {
        case -1: "Reject selected image"
        case 0: "Mark selected image as keeper"
        default: "Set selected image to \(rating) stars"
        }
    }
}
