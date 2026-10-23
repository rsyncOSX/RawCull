import CoreGraphics
import Foundation
@testable import RawCull
import Testing

@Suite("ZoomOverlayNavigationContext")
struct ZoomOverlayNavigationContextTests {
    @Test(.tags(.smoke))
    func `context keeps first occurrence when duplicate IDs are supplied`() {
        let ids = [UUID(), UUID()]
        let context = ZoomOverlayNavigationContext(orderedFileIDs: [ids[0], ids[1], ids[0]])

        #expect(context.orderedFileIDs == ids)
    }
}
