import SwiftUI

struct ZoomOverlayChrome: View {
    let dimensions: CGSize?
    let rating: RatingDisplay?
    let navigationAxis: ZoomOverlayNavigationAxis
    let isInspectingExposure: Bool
    let canNavigatePrevious: Bool
    let canNavigateNext: Bool
    let navigate: (Int) -> Void
    let dismiss: () -> Void

    var body: some View {
        HStack {
            if let rating {
                HStack(spacing: 6) {
                    if let dimensions {
                        ImagePixelDimensionsBadgeView(width: Int(dimensions.width), height: Int(dimensions.height))
                    }
                    CurrentRatingBadgeView(rating: rating)
                }
                .padding()
            }

            Spacer()

            if !isInspectingExposure {
                navigationButton(
                    previousNavigationIcon,
                    help: previousNavigationHelp,
                    isDisabled: !canNavigatePrevious,
                ) {
                    navigate(-1)
                }

                navigationButton(
                    nextNavigationIcon,
                    help: nextNavigationHelp,
                    isDisabled: !canNavigateNext,
                ) {
                    navigate(1)
                }
            }

            toolbarButton("xmark.circle") { dismiss() }
        }
    }

    private var usesVerticalNavigation: Bool {
        navigationAxis == .vertical
    }

    private var previousNavigationIcon: String {
        usesVerticalNavigation ? "chevron.up.circle" : "chevron.left.circle"
    }

    private var nextNavigationIcon: String {
        usesVerticalNavigation ? "chevron.down.circle" : "chevron.right.circle"
    }

    private var previousNavigationHelp: String {
        usesVerticalNavigation ? "Previous image (Up)" : "Previous image"
    }

    private var nextNavigationHelp: String {
        usesVerticalNavigation ? "Next image (Down)" : "Next image"
    }

    private func toolbarButton(_ icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 24))
                .foregroundStyle(.white)
                .frame(width: 30, height: 30)
                .background(Material.regularMaterial)
                .clipShape(Circle())
        }
        .buttonStyle(.plain)
        .shadow(color: .black.opacity(0.4), radius: 8, x: 0, y: 2)
        .padding()
    }

    private func navigationButton(
        _ icon: String,
        help: String,
        isDisabled: Bool,
        action: @escaping () -> Void,
    ) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 24))
                .foregroundStyle(isDisabled ? .white.opacity(0.35) : .white)
                .frame(width: 30, height: 30)
                .background(Material.regularMaterial)
                .clipShape(Circle())
        }
        .buttonStyle(.plain)
        .disabled(isDisabled)
        .help(help)
        .shadow(color: .black.opacity(isDisabled ? 0 : 0.4), radius: 8, x: 0, y: 2)
        .padding(.vertical)
        .padding(.trailing, 2)
    }
}
