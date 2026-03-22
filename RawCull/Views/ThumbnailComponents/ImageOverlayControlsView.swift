import SwiftUI

/// Bottom control bar shared by all image viewer surfaces.
/// Hosts the focus-mask controls, focus-points toggle, and zoom pill.
/// Automatically hides focus-points and zoom when the focus-mask slider
/// panel is expanded, so the sliders can be used without visual clutter.
struct ImageOverlayControlsView: View {
    // MARK: - Focus mask
    @Binding var showFocusMask: Bool
    @Binding var config: FocusDetectorConfig
    @Binding var overlayOpacity: Double
    @Binding var controlsCollapsed: Bool
    var focusMaskAvailable: Bool

    // MARK: - Focus points
    var hasFocusPoints: Bool
    @Binding var showFocusPoints: Bool
    @Binding var markerSize: CGFloat

    // MARK: - Zoom pill
    var scale: CGFloat
    var canZoomOut: Bool
    var canZoomIn: Bool
    var canReset: Bool
    var onZoomOut: () -> Void
    var onZoomReset: () -> Void
    var onZoomIn: () -> Void

    // MARK: -

    var slidersVisible: Bool {
        showFocusMask && !controlsCollapsed
    }

    var body: some View {
        HStack(alignment: .center) {
            FocusMaskControlsView(
                showFocusMask: $showFocusMask,
                config: $config,
                overlayOpacity: $overlayOpacity,
                controlsCollapsed: $controlsCollapsed,
                focusMaskAvailable: focusMaskAvailable,
            )

            if hasFocusPoints, !slidersVisible {
                FocusPointControllerView(
                    showFocusPoints: $showFocusPoints,
                    markerSize: $markerSize,
                )
                .transition(.opacity)
            }

            if !slidersVisible {
                HStack {
                    Button {
                        onZoomOut()
                    } label: {
                        Image(systemName: "minus")
                            .font(.system(size: 12))
                    }
                    .disabled(!canZoomOut)
                    .help("Zoom out")

                    Button {
                        onZoomReset()
                    } label: {
                        Text("Reset \(scale * 100, format: .number.precision(.fractionLength(0)))%")
                            .font(.caption)
                    }
                    .disabled(!canReset)
                    .help("Reset zoom")

                    Button {
                        onZoomIn()
                    } label: {
                        Image(systemName: "plus")
                            .font(.system(size: 12))
                    }
                    .disabled(!canZoomIn)
                    .help("Zoom in")
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(.regularMaterial)
                .clipShape(.rect(cornerRadius: 20))
                .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.2), value: slidersVisible)
    }
}
