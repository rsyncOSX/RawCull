import CoreGraphics
import Foundation
@testable import RawCull
import Testing

@Suite("ThumbnailKeyAction")
struct ThumbnailKeyActionTests {
    @Test(.tags(.smoke), arguments: ["z", "Z"])
    func `Z resolves to actual-pixels inspection`(characters: String) {
        #expect(ThumbnailKeyAction.resolve(characters: characters) == .inspectActualPixels)
    }

    @Test(.tags(.smoke))
    func `unmapped thumbnail key is ignored`() {
        #expect(ThumbnailKeyAction.resolve(characters: "j") == nil)
    }
}
