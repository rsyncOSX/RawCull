@testable import RawCull
import Testing

@Suite("ComparisonGridNavigation")
struct ComparisonGridNavigationTests {
    @Test(.tags(.smoke))
    func `left and right arrows move previous and next`() {
        #expect(ComparisonGridNavigation.destinationIndex(
            from: 1,
            itemCount: 4,
            direction: .left,
        ) == 0)
        #expect(ComparisonGridNavigation.destinationIndex(
            from: 1,
            itemCount: 4,
            direction: .right,
        ) == 2)

        #expect(ComparisonGridNavigation.destinationIndex(
            from: 0,
            itemCount: 4,
            direction: .left,
        ) == nil)
        #expect(ComparisonGridNavigation.destinationIndex(
            from: 3,
            itemCount: 4,
            direction: .right,
        ) == nil)
    }

    @Test(.tags(.smoke))
    func `invalid current index returns nil`() {
        #expect(ComparisonGridNavigation.destinationIndex(
            from: -1,
            itemCount: 4,
            direction: .left,
        ) == nil)
        #expect(ComparisonGridNavigation.destinationIndex(
            from: 4,
            itemCount: 4,
            direction: .right,
        ) == nil)
        #expect(ComparisonGridNavigation.destinationIndex(
            from: 0,
            itemCount: 0,
            direction: .left,
        ) == nil)
    }

    @Test(.tags(.smoke))
    func `printable shortcuts are resolved from characters before hardware key code`() {
        #expect(ComparisonGridKeyAction.resolve(characters: "+", keyCode: 27) == .zoomIn)
        #expect(ComparisonGridKeyAction.resolve(characters: "-", keyCode: 24) == .zoomOut)
    }

    @Test(.tags(.smoke))
    func `non printable key codes resolve linear navigation`() {
        #expect(ComparisonGridKeyAction.resolve(characters: nil, keyCode: 123) == .navigate(.left))
        #expect(ComparisonGridKeyAction.resolve(characters: nil, keyCode: 124) == .navigate(.right))
        #expect(ComparisonGridKeyAction.resolve(characters: nil, keyCode: 125) == nil)
        #expect(ComparisonGridKeyAction.resolve(characters: nil, keyCode: 126) == nil)
        #expect(ComparisonGridKeyAction.resolve(characters: nil, keyCode: 53) == .escape)
    }

    @Test(.tags(.smoke))
    func `printable rating and toggle shortcuts resolve from characters`() {
        #expect(ComparisonGridKeyAction.resolve(characters: "j", keyCode: 0) == .toggleImageSource)
        #expect(ComparisonGridKeyAction.resolve(characters: "J", keyCode: 0) == .toggleImageSource)
        #expect(ComparisonGridKeyAction.resolve(characters: "i", keyCode: 0) == .toggleInspector)
        #expect(ComparisonGridKeyAction.resolve(characters: "I", keyCode: 0) == .toggleInspector)
        #expect(ComparisonGridKeyAction.resolve(characters: "F", keyCode: 0) == .toggleFocusMask)
        #expect(ComparisonGridKeyAction.resolve(characters: "a", keyCode: 0) == .toggleFocusPoints)
        #expect(ComparisonGridKeyAction.resolve(characters: "B", keyCode: 0) == .keepBest)
        #expect(ComparisonGridKeyAction.resolve(characters: "x", keyCode: 0) == .rating(-1))
        #expect(ComparisonGridKeyAction.resolve(characters: "p", keyCode: 0) == .rating(0))
        #expect(ComparisonGridKeyAction.resolve(characters: "1", keyCode: 0) == .rating(2))
        #expect(ComparisonGridKeyAction.resolve(characters: "2", keyCode: 0) == .rating(2))
        #expect(ComparisonGridKeyAction.resolve(characters: "3", keyCode: 0) == .rating(3))
        #expect(ComparisonGridKeyAction.resolve(characters: "T", keyCode: 0) == .rating(3))
        #expect(ComparisonGridKeyAction.resolve(characters: "4", keyCode: 0) == .rating(4))
        #expect(ComparisonGridKeyAction.resolve(characters: "5", keyCode: 0) == .rating(5))
    }

    @Test(.tags(.smoke), arguments: ["z", "Z"])
    func `Z resolves to actual-pixels inspection`(characters: String) {
        #expect(ComparisonGridKeyAction.resolve(characters: characters, keyCode: 0) == .inspectActualPixels)
    }
}

@Suite("BurstReviewKeyAction")
struct BurstReviewKeyActionTests {
    @Test(.tags(.smoke))
    func `burst review shortcuts resolve navigation and metadata`() {
        #expect(BurstReviewKeyAction.resolve(characters: "n") == .nextImage)
        #expect(BurstReviewKeyAction.resolve(characters: "N") == .nextImage)
        #expect(BurstReviewKeyAction.resolve(characters: "p") == .previousImage)
        #expect(BurstReviewKeyAction.resolve(characters: "P") == .previousImage)
        #expect(BurstReviewKeyAction.resolve(characters: "g") == .nextGroup)
        #expect(BurstReviewKeyAction.resolve(characters: "G") == .nextGroup)
        #expect(BurstReviewKeyAction.resolve(characters: "e") == .toggleMetadata)
        #expect(BurstReviewKeyAction.resolve(characters: "E") == .toggleMetadata)
        #expect(BurstReviewKeyAction.resolve(characters: "0") == nil)
    }
}

@Suite("BurstFrameCachePolicy")
struct BurstFrameCachePolicyTests {
    @Test(.tags(.smoke))
    func `window contains previous current and next frame`() {
        #expect(BurstFrameCachePolicy.indices(around: 2, itemCount: 5) == [1, 2, 3])
    }

    @Test(.tags(.smoke))
    func `window contracts at burst boundaries`() {
        #expect(BurstFrameCachePolicy.indices(around: 0, itemCount: 5) == [0, 1])
        #expect(BurstFrameCachePolicy.indices(around: 4, itemCount: 5) == [3, 4])
    }

    @Test(.tags(.smoke))
    func `window is always bounded and contains the selection`() {
        for itemCount in 1 ... 12 {
            for selectedIndex in 0 ..< itemCount {
                let indices = BurstFrameCachePolicy.indices(
                    around: selectedIndex,
                    itemCount: itemCount,
                )
                #expect(indices.count <= BurstFrameCachePolicy.capacity)
                #expect(indices.contains(selectedIndex))
            }
        }

        #expect(BurstFrameCachePolicy.indices(around: -1, itemCount: 5).isEmpty)
        #expect(BurstFrameCachePolicy.indices(around: 5, itemCount: 5).isEmpty)
        #expect(BurstFrameCachePolicy.indices(around: 0, itemCount: 0).isEmpty)
    }
}
