import SwiftUI

/// The photograph and all overlays share one aspect-fit coordinate system.
struct AnalysisImageCanvas<Overlays: View>: View {
    let image: CGImage
    let focusMap: CGImage?
    let autofocusPoint: CGPoint?
    @ViewBuilder let overlays: (CGRect) -> Overlays

    var body: some View {
        GeometryReader { geometry in
            let rect = ImageReviewGeometry.aspectFitRect(
                imageSize: CGSize(width: image.width, height: image.height),
                in: geometry.size,
            )
            Image(decorative: image, scale: 1)
                .resizable()
                .frame(width: rect.width, height: rect.height)
                .position(x: rect.midX, y: rect.midY)
            if let focusMap {
                Image(decorative: focusMap, scale: 1)
                    .resizable()
                    .frame(width: rect.width, height: rect.height)
                    .position(x: rect.midX, y: rect.midY)
                    .accessibilityHidden(true)
            }
            overlays(rect)
            if let autofocusPoint {
                Circle()
                    .stroke(.cyan, lineWidth: 3)
                    .frame(width: 20, height: 20)
                    .background(Circle().fill(.black.opacity(0.35)))
                    .position(x: rect.minX + autofocusPoint.x * rect.width,
                              y: rect.minY + autofocusPoint.y * rect.height)
                    .accessibilityLabel("Camera autofocus point")
            }
        }
    }
}
