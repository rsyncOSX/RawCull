@testable import RawCull
import Testing

@MainActor
@Suite("ZoomSessionModel")
struct ZoomSessionModelTests {
    @Test
    func `launch context initializes source zoom and focus presentation`() {
        let model = ZoomSessionModel()
        model.applyLaunchContext(
            ZoomOverlayLaunchContext(
                initialSource: .embeddedJPG,
                initialZoomMode: .actualPixels,
                showFocusPointsOnOpen: true,
            ),
            hasFocusTarget: true,
        )

        #expect(model.sourceSelection.selected == .embeddedJPG)
        #expect(model.pendingInitialZoomMode == .actualPixels)
        #expect(model.viewport.showFocusPoints)
    }

    @Test
    func `keyboard actions use shared zoom policy adapter`() {
        let model = ZoomSessionModel()
        #expect(model.keyAction(characters: "+", navigationAxis: .horizontal) == .zoomIn)
        #expect(model.keyAction(characters: "X", navigationAxis: .horizontal) == .rating(-1))
    }
}
