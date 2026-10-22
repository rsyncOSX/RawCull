import SwiftUI

struct FocusPointControllerView: View {
    @Binding var showFocusPoints: Bool
    var shortcutLabel: String?
    var density: ImageOverlayControlDensity = .regular

    var body: some View {
        OverlayControlCapsule(density: density, shortcutLabel: shortcutLabel) {
            Button {
                withAnimation(.easeInOut(duration: 0.2)) { showFocusPoints.toggle() }
            } label: {
                Image(systemName: showFocusPoints ? "dot.circle.viewfinder" : "dot.viewfinder")
                    .font(density == .compact ? .body : .title3)
                    .foregroundStyle(showFocusPoints ? .yellow : .primary)
                    .symbolEffect(.bounce, value: showFocusPoints)
            }
            .buttonStyle(.plain)
            .help(showFocusPoints ? "Hide focus points" : "Show focus points")
            .accessibilityLabel("Camera focus points")
            .accessibilityValue(showFocusPoints ? "Shown" : "Hidden")
            .accessibilityHint("Shows or hides camera autofocus points.")

        }
        .animation(.spring(duration: 0.3), value: showFocusPoints)
    }
}
