import SwiftUI

struct FocusMaskControlsView: View {
    @Binding var showFocusMask: Bool
    var focusMaskAvailable: Bool
    var shortcutLabel: String?
    var density: ImageOverlayControlDensity = .regular

    var body: some View {
        OverlayControlCapsule(density: density, shortcutLabel: shortcutLabel) {
            Button {
                withAnimation(.easeInOut(duration: 0.2)) { showFocusMask.toggle() }
            } label: {
                Image(systemName: showFocusMask ? "viewfinder.circle.fill" : "viewfinder.circle")
                    .font(density == .compact ? .body : .title3)
                    .foregroundStyle(showFocusMask ? .blue : .primary)
                    .symbolEffect(.bounce, value: showFocusMask)
            }
            .buttonStyle(.plain)
            .disabled(!focusMaskAvailable)
            .help(showFocusMask ? "Hide focus map" : "Show likely in-focus edges")
            .accessibilityLabel("Focus map")
            .accessibilityValue(showFocusMask ? "Shown" : "Hidden")
            .accessibilityHint(focusMaskAvailable ? "Shows or hides likely in-focus edges." : "No focus map is available for this image.")
        }
        .animation(.spring(duration: 0.3), value: showFocusMask)
    }
}
