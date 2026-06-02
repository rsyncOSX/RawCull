import SwiftUI

struct FocusMaskControlsView: View {
    @Binding var showFocusMask: Bool
    var focusMaskAvailable: Bool
    var shortcutLabel: String?
    var density: ImageOverlayControlDensity = .regular

    var body: some View {
        HStack(spacing: density == .compact ? 5 : 12) {
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

            if let shortcutLabel {
                Text(shortcutLabel)
                    .font(.system(size: 11, weight: .bold, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .accessibilityHidden(true)
            }
        }
        .padding(.horizontal, density == .compact ? 6 : 10)
        .padding(.vertical, density == .compact ? 5 : 9)
        .background(.regularMaterial, in: Capsule())
        .overlay { Capsule().strokeBorder(.primary.opacity(0.1), lineWidth: 0.5) }
        .padding(density == .compact ? 2 : 10)
        .animation(.spring(duration: 0.3), value: showFocusMask)
    }
}
