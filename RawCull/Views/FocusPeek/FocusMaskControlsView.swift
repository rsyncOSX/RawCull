import SwiftUI

struct FocusMaskControlsView: View {
    @Binding var showFocusMask: Bool
    var focusMaskAvailable: Bool

    var body: some View {
        HStack(spacing: 12) {
            Button {
                withAnimation(.easeInOut(duration: 0.2)) { showFocusMask.toggle() }
            } label: {
                Image(systemName: showFocusMask ? "viewfinder.circle.fill" : "viewfinder.circle")
                    .font(.title3)
                    .foregroundStyle(showFocusMask ? .blue : .primary)
                    .symbolEffect(.bounce, value: showFocusMask)
            }
            .buttonStyle(.plain)
            .disabled(!focusMaskAvailable)
            .help(showFocusMask ? "Hide focus mask" : "Show focus mask")
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 9)
        .background(.regularMaterial, in: Capsule())
        .overlay { Capsule().strokeBorder(.primary.opacity(0.1), lineWidth: 0.5) }
        .padding(10)
        .animation(.spring(duration: 0.3), value: showFocusMask)
    }
}
