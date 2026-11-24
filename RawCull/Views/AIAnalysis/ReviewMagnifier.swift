import SwiftUI

/// A round lens centred on the pointer that shows the photo at a fixed pixel scale.
/// 100% maps one pixel of `image` (the full-size embedded preview when available) to one screen pixel.
private struct ReviewMagnifier: View {
    let image: CGImage
    let location: CGPoint
    let displaySize: CGSize
    let pointsPerPixel: CGFloat
    private let diameter: CGFloat = 240

    var body: some View {
        let full = CGSize(width: CGFloat(image.width) * pointsPerPixel, height: CGFloat(image.height) * pointsPerPixel)
        // The image point under the pointer, in the magnified image's coordinates.
        let focus = CGPoint(x: location.x / displaySize.width * full.width, y: location.y / displaySize.height * full.height)
        Image(decorative: image, scale: 1)
            .resizable()
            .interpolation(.none)
            .frame(width: full.width, height: full.height)
            .offset(x: diameter / 2 - focus.x, y: diameter / 2 - focus.y)
            .frame(width: diameter, height: diameter, alignment: .topLeading)
            .background(.black)
            .clipShape(Circle())
            .overlay { Circle().stroke(.white.opacity(0.9), lineWidth: 2) }
            .shadow(color: .black.opacity(0.5), radius: 6)
            .offset(x: location.x - diameter / 2, y: location.y - diameter / 2)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }
}

/// Off, 100% or 200% for the review photo's magnifier.
struct ReviewMagnifierPicker: View {
    @Binding var zoom: Int

    var body: some View {
        Picker("Magnifier", systemImage: "magnifyingglass", selection: $zoom) {
            Text("Off").tag(0)
            Text("100%").tag(100)
            Text("200%").tag(200)
        }
        .pickerStyle(.segmented)
        .controlSize(.small)
        .fixedSize()
        .help("Hover over the photo to magnify the full-size preview at 100% or 200% of its pixels")
    }
}

private struct ReviewMagnifierModifier: ViewModifier {
    let image: CGImage
    let zoom: Int
    let displaySize: CGSize
    @Environment(\.displayScale) private var displayScale
    @State private var location: CGPoint?

    func body(content: Content) -> some View {
        content
            .overlay(alignment: .topLeading) {
                if zoom > 0, let location {
                    ReviewMagnifier(
                        image: image,
                        location: location,
                        displaySize: displaySize,
                        pointsPerPixel: CGFloat(zoom) / 100 / displayScale,
                    )
                }
            }
            .onContinuousHover { phase in
                switch phase {
                case let .active(point): location = point
                case .ended: location = nil
                }
            }
    }
}

extension View {
    /// Shows a magnifier lens under the pointer at `zoom` percent of `image`'s pixels; 0 turns it off.
    func reviewMagnifier(image: CGImage, zoom: Int, displaySize: CGSize) -> some View {
        modifier(ReviewMagnifierModifier(image: image, zoom: zoom, displaySize: displaySize))
    }
}
