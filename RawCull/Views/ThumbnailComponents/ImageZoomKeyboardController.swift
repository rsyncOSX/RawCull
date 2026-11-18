import SwiftUI

/// Dispatches zoom shortcuts without depending on a particular viewer's session.
@MainActor
struct ImageZoomKeyboardController {
    let increaseZoom: () -> Void
    let decreaseZoom: () -> Void

    func handle(_ action: ImageReviewSemanticAction?) -> KeyPress.Result {
        switch action {
        case .zoomIn:
            increaseZoom()
        case .zoomOut:
            decreaseZoom()
        default:
            return .ignored
        }
        return .handled
    }
}
