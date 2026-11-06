import SwiftUI

struct ZoomOverlayChrome: View {
    let dimensions: CGSize?
    let rating: RatingDisplay?
    var isReducedRAWPreview: Bool?
    var rawRenderSeconds: Double?
    var isPreparingRAW = false
    var isPreparingRAWPreview = true
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
                    if isReducedRAWPreview != nil || isPreparingRAW {
                        RAWDecodeBadgeView(
                            isReduced: isReducedRAWPreview ?? true,
                            renderSeconds: rawRenderSeconds,
                            isPreparing: isPreparingRAW,
                            isPreparingPreview: isPreparingRAWPreview,
                        )
                    }
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

private struct RAWDecodeBadgeView: View {
    let isReduced: Bool

    let renderSeconds: Double?
    let isPreparing: Bool
    let isPreparingPreview: Bool

    private var title: Text {
        if isPreparing {
            isPreparingPreview ? Text("Preparing RAW preview…") : Text("Preparing full-detail RAW…")
        } else if let renderSeconds {
            isReduced
                ? Text("RAW Preview · \(renderSeconds, format: .number.precision(.fractionLength(1))) s")
                : Text("RAW Full detail · \(renderSeconds, format: .number.precision(.fractionLength(1))) s")
        } else {
            isReduced ? Text("RAW Preview") : Text("RAW Full detail")
        }
    }

    var body: some View {
        Label {
            title
        } icon: {
            if isPreparing {
                ProgressView().controlSize(.mini)
            } else {
                Image(systemName: isReduced ? "photo" : "viewfinder")
            }
        }
        .font(.system(size: 12, weight: .semibold, design: .monospaced))
        .foregroundStyle(.white)
        .padding(.horizontal, 9)
        .padding(.vertical, 5)
        .background(Color.secondary.opacity(0.85), in: Capsule())
        .fixedSize()
        .help(isReduced
            ? Text("Processed at a resolution suited to this view to reduce processing time. Zoom in to load full detail. Time measures the latest render request, including cache retrieval.")
            : Text("Processed at native resolution for full detail. Time measures the latest render request, including cache retrieval."))
    }
}
