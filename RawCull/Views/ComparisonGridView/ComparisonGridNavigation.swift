nonisolated enum ComparisonGridNavigationDirection {
    case left
    case right
}

nonisolated enum ComparisonGridNavigation {
    nonisolated static func destinationIndex(
        from currentIndex: Int,
        itemCount: Int,
        direction: ComparisonGridNavigationDirection,
    ) -> Int? {
        guard itemCount > 0,
              currentIndex >= 0,
              currentIndex < itemCount else { return nil }

        let destination = switch direction {
        case .left:
            currentIndex - 1

        case .right:
            currentIndex + 1
        }

        guard destination >= 0,
              destination < itemCount else { return nil }
        return destination
    }
}

nonisolated enum ComparisonGridKeyAction: Equatable {
    case navigate(ComparisonGridNavigationDirection)
    case escape
    case zoomIn
    case zoomOut
    case toggleImageSource
    case toggleInspector
    case toggleFocusMask
    case toggleFocusPoints
    case inspectActualPixels
    case keepBest
    case rating(Int)

    nonisolated static func resolve(characters: String?, keyCode: UInt16) -> ComparisonGridKeyAction? {
        if let action = action(for: characters) {
            return action
        }

        return switch keyCode {
        case 123:
            .navigate(.left)

        case 124:
            .navigate(.right)

        case 53:
            .escape

        default:
            nil
        }
    }

    private nonisolated static func action(for characters: String?) -> ComparisonGridKeyAction? {
        switch characters {
        case "+":
            .zoomIn

        case "-":
            .zoomOut

        case "j", "J":
            .toggleImageSource

        case "i", "I":
            .toggleInspector

        case "f", "F":
            .toggleFocusMask

        case "a", "A":
            .toggleFocusPoints

        case "z", "Z":
            .inspectActualPixels

        case "b", "B":
            .keepBest

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
