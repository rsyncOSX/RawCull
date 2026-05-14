@testable import RawCull
import Testing

@Suite("Comparison grid navigation")
struct ComparisonGridNavigationTests {
    @Test(
        arguments: [
            (ComparisonGridNavigationDirection.left, 1),
            (ComparisonGridNavigationDirection.up, 1),
            (ComparisonGridNavigationDirection.right, 3),
            (ComparisonGridNavigationDirection.down, 3)
        ],
    )
    func `one column arrows move previous or next`(
        direction: ComparisonGridNavigationDirection,
        expectedIndex: Int,
    ) {
        let destination = ComparisonGridNavigation.destinationIndex(
            from: 2,
            itemCount: 4,
            columnCount: 1,
            direction: direction,
        )

        #expect(destination == expectedIndex)
    }

    @Test(
        arguments: [
            (1, ComparisonGridNavigationDirection.left, 0),
            (0, ComparisonGridNavigationDirection.right, 1),
            (2, ComparisonGridNavigationDirection.up, 0),
            (1, ComparisonGridNavigationDirection.down, 3)
        ],
    )
    func `two column arrows select directional neighbors`(
        currentIndex: Int,
        direction: ComparisonGridNavigationDirection,
        expectedIndex: Int,
    ) {
        let destination = ComparisonGridNavigation.destinationIndex(
            from: currentIndex,
            itemCount: 4,
            columnCount: 2,
            direction: direction,
        )

        #expect(destination == expectedIndex)
    }

    @Test(
        arguments: [
            (0, 4, ComparisonGridNavigationDirection.left),
            (1, 4, ComparisonGridNavigationDirection.right),
            (0, 4, ComparisonGridNavigationDirection.up),
            (2, 4, ComparisonGridNavigationDirection.down),
            (2, 3, ComparisonGridNavigationDirection.right),
            (1, 3, ComparisonGridNavigationDirection.down)
        ],
    )
    func `two column arrows stop without a valid neighbor`(
        currentIndex: Int,
        itemCount: Int,
        direction: ComparisonGridNavigationDirection,
    ) {
        let destination = ComparisonGridNavigation.destinationIndex(
            from: currentIndex,
            itemCount: itemCount,
            columnCount: 2,
            direction: direction,
        )

        #expect(destination == nil)
    }

    @Test(arguments: [-1, 4])
    func `invalid current index returns nil`(currentIndex: Int) {
        let destination = ComparisonGridNavigation.destinationIndex(
            from: currentIndex,
            itemCount: 4,
            columnCount: 2,
            direction: .right,
        )

        #expect(destination == nil)
    }
}
