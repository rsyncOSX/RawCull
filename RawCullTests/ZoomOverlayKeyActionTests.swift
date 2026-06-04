import Foundation
@testable import RawCull
import Testing

@Suite("ZoomOverlayKeyAction")
struct ZoomOverlayKeyActionTests {
    @Test(.tags(.smoke))
    func `horizontal arrows resolve to previous and next`() {
        #expect(ZoomOverlayKeyAction.resolve(
            characters: nil,
            keyCode: 123,
            navigationAxis: .horizontal,
        ) == .navigatePrevious)
        #expect(ZoomOverlayKeyAction.resolve(
            characters: nil,
            keyCode: 124,
            navigationAxis: .horizontal,
        ) == .navigateNext)
    }

    @Test(.tags(.smoke))
    func `vertical arrows resolve to previous and next`() {
        #expect(ZoomOverlayKeyAction.resolve(
            characters: nil,
            keyCode: 126,
            navigationAxis: .vertical,
        ) == .navigatePrevious)
        #expect(ZoomOverlayKeyAction.resolve(
            characters: nil,
            keyCode: 125,
            navigationAxis: .vertical,
        ) == .navigateNext)
    }

    @Test(.tags(.smoke))
    func `unrelated arrows are ignored for the active axis`() {
        #expect(ZoomOverlayKeyAction.resolve(
            characters: nil,
            keyCode: 126,
            navigationAxis: .horizontal,
        ) == nil)
        #expect(ZoomOverlayKeyAction.resolve(
            characters: nil,
            keyCode: 123,
            navigationAxis: .vertical,
        ) == nil)
    }

    @Test(.tags(.smoke))
    func `escape zoom and source shortcuts resolve`() {
        #expect(ZoomOverlayKeyAction.resolve(
            characters: nil,
            keyCode: 53,
            navigationAxis: .horizontal,
        ) == .escape)
        #expect(ZoomOverlayKeyAction.resolve(
            characters: "+",
            keyCode: 0,
            navigationAxis: .horizontal,
        ) == .zoomIn)
        #expect(ZoomOverlayKeyAction.resolve(
            characters: "-",
            keyCode: 0,
            navigationAxis: .horizontal,
        ) == .zoomOut)
        #expect(ZoomOverlayKeyAction.resolve(
            characters: "j",
            keyCode: 0,
            navigationAxis: .horizontal,
        ) == .toggleThumbnailSource)
        #expect(ZoomOverlayKeyAction.resolve(
            characters: "J",
            keyCode: 0,
            navigationAxis: .horizontal,
        ) == .toggleThumbnailSource)
        #expect(ZoomOverlayKeyAction.resolve(
            characters: "F",
            keyCode: 0,
            navigationAxis: .horizontal,
        ) == .toggleFocusMask)
        #expect(ZoomOverlayKeyAction.resolve(
            characters: "a",
            keyCode: 0,
            navigationAxis: .horizontal,
        ) == .toggleFocusPoints)
    }

    @Test(.tags(.smoke))
    func `rating shortcuts resolve from characters`() {
        #expect(ZoomOverlayKeyAction.resolve(
            characters: "x",
            keyCode: 0,
            navigationAxis: .horizontal,
        ) == .rating(-1))
        #expect(ZoomOverlayKeyAction.resolve(
            characters: "p",
            keyCode: 0,
            navigationAxis: .horizontal,
        ) == .rating(0))
        #expect(ZoomOverlayKeyAction.resolve(
            characters: "0",
            keyCode: 0,
            navigationAxis: .horizontal,
        ) == .rating(0))
        #expect(ZoomOverlayKeyAction.resolve(
            characters: "1",
            keyCode: 0,
            navigationAxis: .horizontal,
        ) == .rating(2))
        #expect(ZoomOverlayKeyAction.resolve(
            characters: "2",
            keyCode: 0,
            navigationAxis: .horizontal,
        ) == .rating(2))
        #expect(ZoomOverlayKeyAction.resolve(
            characters: "t",
            keyCode: 0,
            navigationAxis: .horizontal,
        ) == .rating(3))
        #expect(ZoomOverlayKeyAction.resolve(
            characters: "3",
            keyCode: 0,
            navigationAxis: .horizontal,
        ) == .rating(3))
        #expect(ZoomOverlayKeyAction.resolve(
            characters: "4",
            keyCode: 0,
            navigationAxis: .horizontal,
        ) == .rating(4))
        #expect(ZoomOverlayKeyAction.resolve(
            characters: "5",
            keyCode: 0,
            navigationAxis: .horizontal,
        ) == .rating(5))
    }

    @Test(.tags(.smoke))
    func `unmapped keys are ignored`() {
        #expect(ZoomOverlayKeyAction.resolve(
            characters: "q",
            keyCode: 12,
            navigationAxis: .horizontal,
        ) == nil)
        #expect(ZoomOverlayKeyAction.resolve(
            characters: nil,
            keyCode: 36,
            navigationAxis: .vertical,
        ) == nil)
    }
}

@Suite("ZoomOverlayNavigationContext")
struct ZoomOverlayNavigationContextTests {
    @Test(.tags(.smoke))
    func `destination returns previous and next inside supplied sequence`() {
        let ids = [UUID(), UUID(), UUID()]
        let context = ZoomOverlayNavigationContext(orderedFileIDs: ids)

        #expect(context.destinationID(from: ids[1], delta: -1) == ids[0])
        #expect(context.destinationID(from: ids[1], delta: 1) == ids[2])
    }

    @Test(.tags(.smoke))
    func `navigation is disabled at sequence boundaries`() {
        let ids = [UUID(), UUID(), UUID()]
        let context = ZoomOverlayNavigationContext(orderedFileIDs: ids)

        #expect(context.canNavigatePrevious(from: ids[0]) == false)
        #expect(context.canNavigateNext(from: ids[0]) == true)
        #expect(context.canNavigatePrevious(from: ids[2]) == true)
        #expect(context.canNavigateNext(from: ids[2]) == false)
    }

    @Test(.tags(.smoke))
    func `context does not navigate outside supplied sequence`() {
        let sequence = [UUID(), UUID()]
        let secondGroupFirstID = UUID()
        let context = ZoomOverlayNavigationContext(orderedFileIDs: sequence)

        #expect(context.destinationID(from: sequence[1], delta: 1) == nil)
        #expect(context.destinationID(from: secondGroupFirstID, delta: -1) == nil)
        #expect(context.destinationID(from: secondGroupFirstID, delta: 1) == nil)
    }

    @Test(.tags(.smoke))
    func `context keeps first occurrence when duplicate IDs are supplied`() {
        let ids = [UUID(), UUID()]
        let context = ZoomOverlayNavigationContext(orderedFileIDs: [ids[0], ids[1], ids[0]])

        #expect(context.orderedFileIDs == ids)
    }
}
