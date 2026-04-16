import SwiftUI

struct FocusPointControllerView: View {
    @Binding var showFocusPoints: Bool

    var body: some View {
        HStack(spacing: 12) {
            Button {
                withAnimation(.easeInOut(duration: 0.2)) { showFocusPoints.toggle() }
            } label: {
                Image(systemName: showFocusPoints ? "dot.circle.viewfinder" : "dot.viewfinder")
                    .font(.title3)
                    .foregroundStyle(showFocusPoints ? .yellow : .primary)
                    .symbolEffect(.bounce, value: showFocusPoints)
            }
            .buttonStyle(.plain)
            .help(showFocusPoints ? "Hide focus points" : "Show focus points")
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 9)
        .background(.regularMaterial, in: Capsule())
        .overlay { Capsule().strokeBorder(.primary.opacity(0.1), lineWidth: 0.5) }
        .padding(10)
        .animation(.spring(duration: 0.3), value: showFocusPoints)
    }
}
