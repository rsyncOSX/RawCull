@testable import RawCull
import Testing

@Suite("ComparisonGridNavigation")
struct ComparisonGridNavigationTests {
    @Test(.tags(.smoke))
    func `single column arrows move previous and next`() {
        #expect(ComparisonGridNavigation.destinationIndex(
            from: 1,
            itemCount: 4,
            columnCount: 1,
            direction: .left,
        ) == 0)
        #expect(ComparisonGridNavigation.destinationIndex(
            from: 1,
            itemCount: 4,
            columnCount: 1,
            direction: .up,
        ) == 0)
        #expect(ComparisonGridNavigation.destinationIndex(
            from: 1,
            itemCount: 4,
            columnCount: 1,
            direction: .right,
        ) == 2)
        #expect(ComparisonGridNavigation.destinationIndex(
            from: 1,
            itemCount: 4,
            columnCount: 1,
            direction: .down,
        ) == 2)
    }

    @Test(.tags(.smoke))
    func `two column arrows move through visible grid`() {
        #expect(ComparisonGridNavigation.destinationIndex(
            from: 0,
            itemCount: 4,
            columnCount: 2,
            direction: .right,
        ) == 1)
        #expect(ComparisonGridNavigation.destinationIndex(
            from: 1,
            itemCount: 4,
            columnCount: 2,
            direction: .left,
        ) == 0)
        #expect(ComparisonGridNavigation.destinationIndex(
            from: 0,
            itemCount: 4,
            columnCount: 2,
            direction: .down,
        ) == 2)
        #expect(ComparisonGridNavigation.destinationIndex(
            from: 2,
            itemCount: 4,
            columnCount: 2,
            direction: .up,
        ) == 0)
    }

    @Test(.tags(.smoke))
    func `boundary arrows do not leave comparison set`() {
        #expect(ComparisonGridNavigation.destinationIndex(
            from: 0,
            itemCount: 4,
            columnCount: 1,
            direction: .left,
        ) == nil)
        #expect(ComparisonGridNavigation.destinationIndex(
            from: 3,
            itemCount: 4,
            columnCount: 1,
            direction: .down,
        ) == nil)
        #expect(ComparisonGridNavigation.destinationIndex(
            from: 0,
            itemCount: 4,
            columnCount: 2,
            direction: .left,
        ) == nil)
        #expect(ComparisonGridNavigation.destinationIndex(
            from: 1,
            itemCount: 4,
            columnCount: 2,
            direction: .right,
        ) == nil)
        #expect(ComparisonGridNavigation.destinationIndex(
            from: 3,
            itemCount: 4,
            columnCount: 2,
            direction: .down,
        ) == nil)
    }
}
