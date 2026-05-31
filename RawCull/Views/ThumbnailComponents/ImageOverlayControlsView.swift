import SwiftUI

/// Bottom control bar shared by all image viewer surfaces.
/// Hosts the focus-mask toggle, focus-points toggle, and zoom pill.
/// Slider controls for focus mask and focus points have moved to Settings → Focus.
struct ImageOverlayControlsView: View {
    // MARK: - Focus mask

    @Binding var showFocusMask: Bool
    var focusMaskAvailable: Bool

    // MARK: - Focus peaking

    @Binding var showFocusPeaking: Bool
    var focusPeakingAvailable: Bool

    // MARK: - Focus points

    var hasFocusPoints: Bool
    @Binding var showFocusPoints: Bool
    var showShortcutHints: Bool = false

    // MARK: - Image source toggle (zoom overlay only)

    var showImageSourceToggle: Bool = false
    @Binding var useThumbnailSource: Bool

    // MARK: - Inspector

    var inspectorIsPresented: Bool = false
    var onToggleInspector: (() -> Void)?

    // MARK: - Zoom pill

    var scale: CGFloat
    var canZoomOut: Bool
    var canZoomIn: Bool
    var canReset: Bool
    var onZoomOut: () -> Void
    var onZoomReset: () -> Void
    var onZoomIn: () -> Void

    // MARK: -

    var body: some View {
        HStack(alignment: .center) {
            FocusMaskControlsView(
                showFocusMask: $showFocusMask,
                focusMaskAvailable: focusMaskAvailable,
                shortcutLabel: showShortcutHints ? "F" : nil,
            )

            FocusPeakingControlsView(
                showFocusPeaking: $showFocusPeaking,
                focusPeakingAvailable: focusPeakingAvailable,
                shortcutLabel: showShortcutHints ? "G" : nil,
            )

            if hasFocusPoints {
                FocusPointControllerView(
                    showFocusPoints: $showFocusPoints,
                    shortcutLabel: showShortcutHints ? "A" : nil,
                )
                .transition(.opacity)
            }

            if showImageSourceToggle {
                ImageSourceToggleView(useThumbnailSource: $useThumbnailSource)
                    .transition(.opacity)
            }

            if let onToggleInspector {
                Button {
                    onToggleInspector()
                } label: {
                    Image(systemName: "sidebar.right")
                        .font(.system(size: 12))
                        .frame(width: 28, height: 28)
                        .contentShape(Circle())
                }
                .buttonStyle(.plain)
                .foregroundStyle(inspectorIsPresented ? Color.accentColor : Color.primary)
                .padding(.horizontal, 8)
                .padding(.vertical, 6)
                .background(.regularMaterial)
                .clipShape(.rect(cornerRadius: 20))
                .help(inspectorIsPresented ? "Hide candidate inspector" : "Show candidate inspector")
            }

            HStack {
                Button {
                    onZoomOut()
                } label: {
                    Image(systemName: "minus")
                        .font(.system(size: 12))
                        .frame(width: 28, height: 28)
                        .contentShape(Circle())
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
                        .frame(width: 28, height: 28)
                        .contentShape(Circle())
                }
                .disabled(!canZoomIn)
                .help("Zoom in")
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(.regularMaterial)
            .clipShape(.rect(cornerRadius: 20))
        }
    }
}
