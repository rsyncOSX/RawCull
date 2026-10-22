import SwiftUI

/// Shared chrome for image inspection controls; each control owns its behavior.
struct OverlayControlCapsule<Content: View>: View {
    let density: ImageOverlayControlDensity
    var shortcutLabel: String?
    @ViewBuilder let content: () -> Content

    var body: some View {
        HStack(spacing: density == .compact ? 5 : 12) {
            content()
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
    }
}
