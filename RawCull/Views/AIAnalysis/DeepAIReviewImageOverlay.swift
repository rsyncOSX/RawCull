import SwiftUI

struct DeepAIReviewImageOverlay: View {
    let image: CGImage
    let focusMap: CGImage?
    let maskOverlay: CGImage?
    let autofocusPoint: CGPoint?

    var body: some View {
        AnalysisImageCanvas(image: image, focusMap: focusMap, autofocusPoint: autofocusPoint) { rect in
            if let maskOverlay {
                ImageReviewRasterOverlay(
                    image: Image(decorative: maskOverlay, scale: 1, orientation: .up),
                    size: rect.size,
                    kind: .subjectOutline,
                )
                .position(x: rect.midX, y: rect.midY)
            }
        }
        .accessibilityLabel("Photograph with subject mask, focus map, and camera autofocus point when available")
    }
}
