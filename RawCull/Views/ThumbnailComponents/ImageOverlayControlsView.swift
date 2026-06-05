import SwiftUI

enum ImageOverlayControlDensity {
    case regular
    case compact
}

/// Bottom control bar shared by all image viewer surfaces.
/// Hosts the focus-mask toggle, focus-points toggle, and zoom pill.
/// Slider controls for focus mask and focus points have moved to Settings → Focus.
struct ImageOverlayControlsView: View {
    // MARK: - Focus mask

    @Binding var showFocusMask: Bool
    var focusMaskAvailable: Bool

    // MARK: - Focus points

    var hasFocusPoints: Bool
    @Binding var showFocusPoints: Bool
    var showShortcutHints: Bool = false
    var density: ImageOverlayControlDensity = .regular

    // MARK: - Image source toggle (zoom overlay only)

    var showImageSourceToggle: Bool = false
    @Binding var useThumbnailSource: Bool
    var imageSourceSelection: Binding<ImageSourceSelectionState>? = nil

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
        HStack(alignment: .center, spacing: density == .compact ? 4 : nil) {
            FocusMaskControlsView(
                showFocusMask: $showFocusMask,
                focusMaskAvailable: focusMaskAvailable,
                shortcutLabel: showShortcutHints ? "F" : nil,
                density: density,
            )

            if hasFocusPoints {
                FocusPointControllerView(
                    showFocusPoints: $showFocusPoints,
                    shortcutLabel: showShortcutHints ? "A" : nil,
                    density: density,
                )
                .transition(.opacity)
            }

            if showImageSourceToggle {
                Group {
                    if let imageSourceSelection {
                        ImageSourceSelectorView(
                            selection: imageSourceSelection,
                            density: density,
                        )
                    } else {
                        ImageSourceToggleView(
                            useThumbnailSource: $useThumbnailSource,
                            density: density,
                        )
                    }
                }
                .transition(.opacity)
            }

            if let onToggleInspector {
                Button {
                    onToggleInspector()
                } label: {
                    Image(systemName: "sidebar.right")
                        .font(.system(size: 12))
                        .frame(width: buttonSize, height: buttonSize)
                        .contentShape(Circle())
                }
                .buttonStyle(.plain)
                .foregroundStyle(inspectorIsPresented ? Color.accentColor : Color.primary)
                .padding(.horizontal, capsuleHorizontalPadding)
                .padding(.vertical, capsuleVerticalPadding)
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
                        .frame(width: buttonSize, height: buttonSize)
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
                        .frame(width: buttonSize, height: buttonSize)
                        .contentShape(Circle())
                }
                .disabled(!canZoomIn)
                .help("Zoom in")
            }
            .buttonStyle(.plain)
            .padding(.horizontal, zoomHorizontalPadding)
            .padding(.vertical, capsuleVerticalPadding)
            .background(.regularMaterial)
            .clipShape(.rect(cornerRadius: 20))
        }
    }

    private var buttonSize: CGFloat {
        density == .compact ? 20 : 28
    }

    private var capsuleHorizontalPadding: CGFloat {
        density == .compact ? 5 : 8
    }

    private var capsuleVerticalPadding: CGFloat {
        density == .compact ? 3 : 6
    }

    private var zoomHorizontalPadding: CGFloat {
        density == .compact ? 7 : 12
    }
}
