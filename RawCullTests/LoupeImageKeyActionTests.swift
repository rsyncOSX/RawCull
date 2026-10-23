import CoreGraphics
import Foundation
@testable import RawCull
import Testing

@Suite("LoupeImageKeyAction")
struct LoupeImageKeyActionTests {
    @Test(.tags(.smoke), arguments: ["j", "J"])
    func `J resolves to embedded JPG`(characters: String) {
        #expect(LoupeImageKeyAction.resolve(characters: characters) == .toggleEmbeddedJPG)
    }

    @Test(.tags(.smoke), arguments: ["r", "R"])
    func `R resolves to developed RAW`(characters: String) {
        #expect(LoupeImageKeyAction.resolve(characters: characters) == .toggleDevelopedRAW)
    }

    @Test(.tags(.smoke), arguments: ["f", "F"])
    func `F resolves to focus mask`(characters: String) {
        #expect(LoupeImageKeyAction.resolve(characters: characters) == .toggleFocusMask)
    }

    @Test(.tags(.smoke), arguments: ["s", "S"])
    func `S resolves to Deep Review subject outline`(characters: String) {
        #expect(LoupeImageKeyAction.resolve(characters: characters) == .toggleSubjectOutline)
    }

    @Test(.tags(.smoke), arguments: ["a", "A"])
    func `A resolves to autofocus points`(characters: String) {
        #expect(LoupeImageKeyAction.resolve(characters: characters) == .toggleFocusPoints)
    }

    @Test(.tags(.smoke), arguments: ["e", "E"])
    func `E resolves to metadata panel`(characters: String) {
        #expect(LoupeImageKeyAction.resolve(characters: characters) == .toggleMetadata)
    }

    @Test(.tags(.smoke), arguments: ["z", "Z"])
    func `Z resolves to actual-pixels inspection`(characters: String) {
        #expect(LoupeImageKeyAction.resolve(characters: characters) == .inspectActualPixels)
    }
}
