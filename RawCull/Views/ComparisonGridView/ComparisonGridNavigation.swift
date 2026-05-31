enum ComparisonGridNavigationDirection {
    case left
    case right
    case up
    case down
}

enum ComparisonGridNavigation {
    nonisolated static func destinationIndex(
        from currentIndex: Int,
        itemCount: Int,
        columnCount: Int,
        direction: ComparisonGridNavigationDirection,
    ) -> Int? {
        guard itemCount > 0,
              currentIndex >= 0,
              currentIndex < itemCount else { return nil }

        let columns = max(1, columnCount)

        if columns == 1 {
            return singleColumnDestination(
                from: currentIndex,
                itemCount: itemCount,
                direction: direction,
            )
        }

        let destination = switch direction {
        case .left:
            currentIndex % columns == 0 ? nil : currentIndex - 1

        case .right:
            currentIndex % columns == columns - 1 ? nil : currentIndex + 1

        case .up:
            currentIndex - columns

        case .down:
            currentIndex + columns
        }

        guard let destination,
              destination >= 0,
              destination < itemCount else { return nil }
        return destination
    }

    private nonisolated static func singleColumnDestination(
        from currentIndex: Int,
        itemCount: Int,
        direction: ComparisonGridNavigationDirection,
    ) -> Int? {
        let destination = switch direction {
        case .left, .up:
            currentIndex - 1

        case .right, .down:
            currentIndex + 1
        }

        guard destination >= 0,
              destination < itemCount else { return nil }
        return destination
    }
}

enum ComparisonGridKeyAction: Equatable {
    case navigate(ComparisonGridNavigationDirection)
    case escape
    case zoomIn
    case zoomOut
    case toggleImageSource
    case toggleFocusMask
    case toggleFocusPoints
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

        case 125:
            .navigate(.down)

        case 126:
            .navigate(.up)

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

        case "J":
            .toggleImageSource

        case "f", "F":
            .toggleFocusMask

        case "a", "A":
            .toggleFocusPoints

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
