enum ComparisonGridNavigationDirection: Sendable {
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

    nonisolated private static func singleColumnDestination(
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
