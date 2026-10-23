import CoreGraphics
import Foundation
@testable import RawCull
import Testing

@Suite("ImageSourceSelectionState")
struct ImageSourceSelectionStateTests {
    @Test(.tags(.smoke))
    func `selection can start with an extracted JPEG`() {
        let state = ImageSourceSelectionState(initialSource: .embeddedJPG)

        #expect(state.selected == .embeddedJPG)
    }

    @Test(.tags(.smoke), arguments: [ImagePreviewSource.embeddedJPG, .developedRAW])
    func `extraction source toggles against thumbnail`(source: ImagePreviewSource) {
        var state = ImageSourceSelectionState()

        state.toggleExtractionSource(source)
        #expect(state.selected == source)

        state.toggleExtractionSource(source)
        #expect(state.selected == .thumbnail)
    }

    @Test(.tags(.smoke))
    func `disabled RAW source ignores toggle`() {
        var state = ImageSourceSelectionState()
        state.select(.developedRAW)
        state.markDevelopedRAWUnavailable()
        let restoredSource = state.selected

        state.toggleExtractionSource(.developedRAW)

        #expect(state.selected == restoredSource)
        #expect(state.rawUnavailable)
    }

    @Test(.tags(.smoke))
    func `RAW failure restores previous source and disables RAW`() {
        var state = ImageSourceSelectionState()
        state.select(.embeddedJPG)
        state.select(.developedRAW)

        state.markDevelopedRAWUnavailable()

        #expect(state.selected == .embeddedJPG)
        #expect(state.rawUnavailable)
    }

    @Test(.tags(.smoke))
    func `new image clears RAW disable while preserving selected source`() {
        var state = ImageSourceSelectionState()
        state.select(.developedRAW)
        state.markDevelopedRAWUnavailable()
        let restoredSource = state.selected

        state.resetForNewImage()

        #expect(state.selected == restoredSource)
        #expect(state.rawUnavailable == false)
    }
}
