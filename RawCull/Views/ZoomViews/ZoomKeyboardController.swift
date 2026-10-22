import SwiftUI

@MainActor
struct ZoomKeyboardController {
    let session: ZoomSessionModel
    let hasSubjectOutline: Bool
    let navigate: (Int) -> Void
    let dismiss: () -> Void
    let increaseZoom: () -> Void
    let decreaseZoom: () -> Void
    let applyRating: (Int) -> KeyPress.Result

    func handle(_ action: ZoomOverlayKeyAction?) -> KeyPress.Result {
        guard let action else { return .ignored }
        if session.evaluateRAWExposure {
            switch action {
            case .escape, .zoomIn, .zoomOut: break
            default: return .handled
            }
        }

        switch action {
        case .navigatePrevious:
            navigate(-1)
            return .handled

        case .navigateNext:
            navigate(1)
            return .handled

        case .escape:
            dismiss()
            return .handled

        case .zoomIn:
            increaseZoom()
            return .handled

        case .zoomOut:
            decreaseZoom()
            return .handled

        case .toggleEmbeddedJPG:
            session.sourceSelection.toggleExtractionSource(.embeddedJPG)
            return .handled

        case .toggleDevelopedRAW:
            session.sourceSelection.toggleExtractionSource(.developedRAW)
            return .handled

        case .toggleFocusMask:
            session.viewport.showFocusMask.toggle()
            return .handled

        case .toggleSubjectOutline:
            guard hasSubjectOutline else { return .ignored }
            session.showSubjectOutline.toggle()
            return .handled

        case .toggleFocusPoints:
            session.viewport.showFocusPoints.toggle()
            return .handled

        case let .rating(rating):
            return applyRating(rating)
        }
    }
}
