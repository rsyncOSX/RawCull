import Foundation
@testable import RawCull
import Testing

@Suite("LoupeImageKeyAction")
struct LoupeImageKeyActionTests {
    @Test(.tags(.smoke))
    func `zoom shortcuts resolve from characters`() {
        #expect(LoupeImageKeyAction.resolve(characters: "+") == .zoomIn)
        #expect(LoupeImageKeyAction.resolve(characters: "-") == .zoomOut)
    }

    @Test(.tags(.smoke))
    func `jpg source shortcuts resolve from lowercase and uppercase j`() {
        #expect(LoupeImageKeyAction.resolve(characters: "j") == .toggleExtractedJPG)
        #expect(LoupeImageKeyAction.resolve(characters: "J") == .toggleExtractedJPG)
    }

    @Test(.tags(.smoke))
    func `unmapped keys are ignored`() {
        #expect(LoupeImageKeyAction.resolve(characters: "f") == nil)
        #expect(LoupeImageKeyAction.resolve(characters: "q") == nil)
        #expect(LoupeImageKeyAction.resolve(characters: nil) == nil)
    }
}
