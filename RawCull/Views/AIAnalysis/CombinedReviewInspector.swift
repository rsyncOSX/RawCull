import SwiftUI

/// The overview with an optional subject-mask tint and the crop geometry of one region:
/// requested yellow, padded orange (dashed), clipped green, model-retained pink.
struct CombinedReviewInspectionCanvas: View {
    let image: CGImage
    let tint: CGImage?
    let sourceSize: CGSize
    let region: ReviewRegionRecord?

    var body: some View {
        GeometryReader { geometry in
            let scale = min(geometry.size.width / sourceSize.width, geometry.size.height / sourceSize.height)
            let size = CGSize(width: sourceSize.width * scale, height: sourceSize.height * scale)
            ZStack(alignment: .topLeading) {
                Image(decorative: image, scale: 1).resizable().frame(width: size.width, height: size.height)
                if let tint {
                    Image(decorative: tint, scale: 1).resizable().frame(width: size.width, height: size.height)
                }
                if let region {
                    outline(region.requestedRect, color: .yellow, size: size)
                    outline(region.paddedRect, color: .orange, size: size)
                    outline(region.sourceRect, color: .green, size: size)
                    outline(region.retainedSourceRect, color: .pink, size: size)
                }
            }.frame(width: size.width, height: size.height).clipped()
        }
    }

    private func outline(_ rect: CGRect, color: Color, size: CGSize) -> some View {
        let display = ReviewInspectionOverlay.displayRect(rect, sourceSize: sourceSize, displaySize: size)
        return Rectangle().stroke(color, style: StrokeStyle(lineWidth: 2, dash: color == .orange ? [5, 3] : []))
            .frame(width: display.width, height: display.height).offset(x: display.minX, y: display.minY)
    }
}
