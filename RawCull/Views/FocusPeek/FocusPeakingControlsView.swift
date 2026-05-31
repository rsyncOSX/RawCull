import SwiftUI

struct FocusPeakingControlsView: View {
    @Binding var showFocusPeaking: Bool
    var focusPeakingAvailable: Bool
    var shortcutLabel: String?

    var body: some View {
        HStack(spacing: 12) {
            Button {
                withAnimation(.easeInOut(duration: 0.2)) { showFocusPeaking.toggle() }
            } label: {
                Image(systemName: showFocusPeaking ? "scope" : "scope")
                    .font(.title3)
                    .foregroundStyle(showFocusPeaking ? Color(red: 0.15, green: 0.85, blue: 0.1) : .primary)
                    .symbolEffect(.bounce, value: showFocusPeaking)
            }
            .buttonStyle(.plain)
            .disabled(!focusPeakingAvailable)
            .help(showFocusPeaking ? "Hide focus peaking" : "Show focus peaking (all in-focus edges)")

            if let shortcutLabel {
                Text(shortcutLabel)
                    .font(.system(size: 11, weight: .bold, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .accessibilityHidden(true)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 9)
        .background(.regularMaterial, in: Capsule())
        .overlay { Capsule().strokeBorder(.primary.opacity(0.1), lineWidth: 0.5) }
        .padding(10)
        .animation(.spring(duration: 0.3), value: showFocusPeaking)
    }
}
