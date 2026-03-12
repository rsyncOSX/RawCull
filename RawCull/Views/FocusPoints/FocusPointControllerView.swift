import SwiftUI

struct FocusPointControllerView: View {
    @Binding var showFocusPoints: Bool
    @Binding var markerSize: CGFloat

    var body: some View {
        HStack(spacing: 12) {
            if showFocusPoints {
                HStack(spacing: 6) {
                    Image(systemName: "viewfinder")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Slider(value: $markerSize, in: 32 ... 100, step: 4)
                        .frame(width: 100)
                        .controlSize(.small)
                    Image(systemName: "viewfinder")
                        .font(.body)
                        .foregroundStyle(.secondary)
                }
                .transition(.move(edge: .trailing).combined(with: .opacity))
            }

            Button {
                withAnimation(.easeInOut(duration: 0.2)) { showFocusPoints.toggle() }
            } label: {
                Image(systemName: showFocusPoints ? "viewfinder.circle.fill" : "viewfinder.circle")
                    .font(.title3)
                    .foregroundStyle(showFocusPoints ? .yellow : .primary)
                    .symbolEffect(.bounce, value: showFocusPoints)
            }
            .buttonStyle(.plain)
            .help(showFocusPoints ? "Hide focus points" : "Show focus points")
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 9)
        .background(.ultraThinMaterial, in: Capsule())
        .overlay { Capsule().strokeBorder(.primary.opacity(0.1), lineWidth: 0.5) }
        .padding(10)
        .animation(.spring(duration: 0.3), value: showFocusPoints)
    }
}
