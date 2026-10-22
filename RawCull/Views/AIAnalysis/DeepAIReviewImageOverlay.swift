import SwiftUI

struct DeepAIReviewImageOverlay: View {
    let image: CGImage
    let focusMap: CGImage?
    let maskOverlay: CGImage?
    let autofocusPoint: CGPoint?

    var body: some View {
        GeometryReader { geometry in
            let scale = min(geometry.size.width / CGFloat(image.width),
                            geometry.size.height / CGFloat(image.height))
            let width = CGFloat(image.width) * scale
            let height = CGFloat(image.height) * scale
            let originX = (geometry.size.width - width) / 2
            let originY = (geometry.size.height - height) / 2

            Image(decorative: image, scale: 1)
                .resizable()
                .frame(width: width, height: height)
                .position(x: geometry.size.width / 2, y: geometry.size.height / 2)
            if let focusMap {
                Image(decorative: focusMap, scale: 1)
                    .resizable()
                    .frame(width: width, height: height)
                    .position(x: geometry.size.width / 2, y: geometry.size.height / 2)
                    .accessibilityHidden(true)
            }
            if let maskOverlay {
                Image(decorative: maskOverlay, scale: 1, orientation: .up)
                    .resizable()
                    .colorMultiply(.orange)
                    .blendMode(.screen)
                    .opacity(0.95)
                    .frame(width: width, height: height)
                    .position(x: geometry.size.width / 2, y: geometry.size.height / 2)
                    .accessibilityHidden(true)
            }
            if let autofocusPoint {
                Circle()
                    .stroke(.cyan, lineWidth: 3)
                    .frame(width: 20, height: 20)
                    .background(Circle().fill(.black.opacity(0.35)))
                    .position(x: originX + autofocusPoint.x * width,
                              y: originY + autofocusPoint.y * height)
                    .accessibilityLabel("Camera autofocus point")
            }
        }
        .accessibilityLabel("Photograph with subject mask, focus map, and camera autofocus point when available")
    }
}
