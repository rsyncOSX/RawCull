import AppKit
import SwiftUI

struct ObjectOverviewImage: View {
    let image: CGImage
    let instances: [ObjectInstanceDescriptor]
    let outlines: [String: CGImage]
    let focusMap: CGImage?
    let autofocusPoint: CGPoint?

    var body: some View {
        AnalysisImageCanvas(image: image, focusMap: focusMap, autofocusPoint: autofocusPoint) { rect in
            let drawnWidth = rect.width
            let drawnHeight = rect.height
            let originX = rect.minX
            let originY = rect.minY
            ForEach(instances) { object in
                let box = object.normalizedBoundingBox
                if let outline = outlines[object.id] {
                    Image(decorative: outline, scale: 1)
                        .resizable()
                        .renderingMode(.template)
                        .foregroundStyle(.yellow)
                        .frame(width: drawnWidth, height: drawnHeight)
                        .position(x: rect.midX, y: rect.midY)
                }
                Rectangle()
                    .stroke(.yellow, lineWidth: 2)
                    .frame(
                        width: box.width * drawnWidth,
                        height: box.height * drawnHeight,
                    )
                    .position(
                        x: originX + box.midX * drawnWidth,
                        y: originY + (1 - box.midY) * drawnHeight,
                    )
                    .accessibilityLabel("Object \(object.id), \(object.concept)")
                Text(object.id)
                    .font(.caption.bold())
                    .padding(3)
                    .background(.black, in: RoundedRectangle(cornerRadius: 3))
                    .foregroundStyle(.white)
                    .position(
                        x: originX + box.minX * drawnWidth + 12,
                        y: originY + (1 - box.maxY) * drawnHeight + 12,
                    )
            }
        }
        .accessibilityLabel("Photograph with numbered object regions, focus map, and camera autofocus point when available")
    }
}
