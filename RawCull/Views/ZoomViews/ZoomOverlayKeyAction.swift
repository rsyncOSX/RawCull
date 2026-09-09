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
        switch characters {
        case "+":
            .zoomIn

        case "-":
            .zoomOut

        case "j", "J":
            .toggleEmbeddedJPG

        case "r", "R":
            .toggleDevelopedRAW

        case "f", "F":
            .toggleFocusMask

        case "s", "S":
            .toggleSubjectOutline

        case "a", "A":
            .toggleFocusPoints

        case "x", "X":
            .rating(-1)

        case "p", "P", "0":
            .rating(0)

        case "1", "2":
            .rating(2)

        case "3", "t", "T":
            .rating(3)

        case "4":
            .rating(4)

        case "5":
            .rating(5)

        default:
            nil
        }
    }
}
