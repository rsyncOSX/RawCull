import SwiftUI

struct ImageSourceToggleView: View {
    @Binding var useThumbnailSource: Bool
    var density: ImageOverlayControlDensity = .regular

    var body: some View {
        Button {
            withAnimation(.easeInOut(duration: 0.2)) { useThumbnailSource.toggle() }
        } label: {
            Image(systemName: useThumbnailSource ? "photo.fill" : "photo")
                .font(density == .compact ? .body : .title3)
                .foregroundStyle(useThumbnailSource ? .blue : .primary)
                .symbolEffect(.bounce, value: useThumbnailSource)
        }
        .buttonStyle(.plain)
        .help(useThumbnailSource ? "Using thumbnail — switch to extracted JPG" : "Using extracted JPG — switch to thumbnail")
        .padding(.horizontal, density == .compact ? 6 : 10)
        .padding(.vertical, density == .compact ? 5 : 9)
        .background(.regularMaterial, in: Capsule())
        .overlay { Capsule().strokeBorder(.primary.opacity(0.1), lineWidth: 0.5) }
        .padding(density == .compact ? 2 : 10)
        .animation(.spring(duration: 0.3), value: useThumbnailSource)
    }
}
