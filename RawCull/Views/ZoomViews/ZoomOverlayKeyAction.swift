nonisolated enum ZoomOverlayKeyAction: Equatable {
    case navigatePrevious
    case navigateNext
    case escape
    case zoomIn
    case zoomOut
    case toggleEmbeddedJPG
    case toggleDevelopedRAW
    case toggleFocusMask
    case toggleSubjectOutline
    case toggleFocusPoints
    case rating(Int)

    nonisolated static func resolve(
        characters: String?,
        keyCode: UInt16,
        navigationAxis: ZoomOverlayNavigationAxis,
    ) -> ZoomOverlayKeyAction? {
        if let action = action(for: characters) {
            return action
        }

        return switch (navigationAxis, keyCode) {
        case (.horizontal, 123), (.vertical, 126):
            .navigatePrevious

        case (.horizontal, 124), (.vertical, 125):
            .navigateNext

        case (_, 53):
            .escape

        default:
            nil
        }
    }

    private nonisolated static func action(for characters: String?) -> ZoomOverlayKeyAction? {
        guard let sharedAction = ImageReviewKeyboardPolicy.action(for: characters) else {
            return nil
        }
        return switch sharedAction {
        case .zoomIn: .zoomIn
        case .zoomOut: .zoomOut
        case .toggleEmbeddedJPG: .toggleEmbeddedJPG
        case .toggleDevelopedRAW: .toggleDevelopedRAW
        case .toggleFocusMask: .toggleFocusMask
        case .toggleSubjectOutline: .toggleSubjectOutline
        case .toggleFocusPoints: .toggleFocusPoints
        case let .rating(action): .rating(action.value)
        }
    }
}
