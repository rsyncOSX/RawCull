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
    func `forced vertical compare layout navigates linearly`() {
        let columnCount = 1

        #expect(ComparisonGridNavigation.destinationIndex(
            from: 0,
            itemCount: 4,
            columnCount: columnCount,
            direction: .up,
        ) == nil)
        #expect(ComparisonGridNavigation.destinationIndex(
            from: 0,
            itemCount: 4,
            columnCount: columnCount,
            direction: .left,
        ) == nil)
        #expect(ComparisonGridNavigation.destinationIndex(
            from: 1,
            itemCount: 4,
            columnCount: columnCount,
            direction: .up,
        ) == 0)
        #expect(ComparisonGridNavigation.destinationIndex(
            from: 1,
            itemCount: 4,
            columnCount: columnCount,
            direction: .left,
        ) == 0)
        #expect(ComparisonGridNavigation.destinationIndex(
            from: 1,
            itemCount: 4,
            columnCount: columnCount,
            direction: .down,
        ) == 2)
        #expect(ComparisonGridNavigation.destinationIndex(
            from: 1,
            itemCount: 4,
            columnCount: columnCount,
            direction: .right,
        ) == 2)
        #expect(ComparisonGridNavigation.destinationIndex(
            from: 3,
            itemCount: 4,
            columnCount: columnCount,
            direction: .down,
        ) == nil)
        #expect(ComparisonGridNavigation.destinationIndex(
            from: 3,
            itemCount: 4,
            columnCount: columnCount,
            direction: .right,
        ) == nil)
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

    @Test(.tags(.smoke))
    func `printable shortcuts are resolved from characters before hardware key code`() {
        #expect(ComparisonGridKeyAction.resolve(characters: "+", keyCode: 27) == .zoomIn)
        #expect(ComparisonGridKeyAction.resolve(characters: "-", keyCode: 24) == .zoomOut)
    }

    @Test(.tags(.smoke))
    func `non printable key codes still resolve navigation`() {
        #expect(ComparisonGridKeyAction.resolve(characters: nil, keyCode: 123) == .navigate(.left))
        #expect(ComparisonGridKeyAction.resolve(characters: nil, keyCode: 124) == .navigate(.right))
        #expect(ComparisonGridKeyAction.resolve(characters: nil, keyCode: 125) == .navigate(.down))
        #expect(ComparisonGridKeyAction.resolve(characters: nil, keyCode: 126) == .navigate(.up))
        #expect(ComparisonGridKeyAction.resolve(characters: nil, keyCode: 53) == .escape)
    }

    @Test(.tags(.smoke))
    func `printable rating and toggle shortcuts resolve from characters`() {
        #expect(ComparisonGridKeyAction.resolve(characters: "j", keyCode: 0) == nil)
        #expect(ComparisonGridKeyAction.resolve(characters: "F", keyCode: 0) == .toggleFocusMask)
        #expect(ComparisonGridKeyAction.resolve(characters: "a", keyCode: 0) == .toggleFocusPoints)
        #expect(ComparisonGridKeyAction.resolve(characters: "B", keyCode: 0) == .keepBest)
        #expect(ComparisonGridKeyAction.resolve(characters: "x", keyCode: 0) == .rating(-1))
        #expect(ComparisonGridKeyAction.resolve(characters: "p", keyCode: 0) == .rating(0))
        #expect(ComparisonGridKeyAction.resolve(characters: "2", keyCode: 0) == .rating(2))
        #expect(ComparisonGridKeyAction.resolve(characters: "t", keyCode: 0) == .rating(3))
        #expect(ComparisonGridKeyAction.resolve(characters: "4", keyCode: 0) == .rating(4))
        #expect(ComparisonGridKeyAction.resolve(characters: "5", keyCode: 0) == .rating(5))
    }
}
