import CoreGraphics
import Foundation
@testable import RawCull
import Testing

@MainActor
@Suite("ZoomOverlayLaunchContext")
struct ZoomOverlayLaunchContextTests {
    @Test
    func `default zoom overlay opens the embedded JPG fitted without focus points`() {
        let viewModel = makeRawCullViewModel()

        viewModel.openZoomOverlay()

        #expect(viewModel.zoomOverlay.launchContext == .default)
        #expect(viewModel.zoomOverlay.launchContext.initialSource == .embeddedJPG)
        #expect(viewModel.zoomOverlay.launchContext.initialZoomMode == .fit)
        #expect(viewModel.zoomOverlay.launchContext.showFocusPointsOnOpen == false)
    }

    @Test
    func `actual-pixels launch context requests embedded JPG and focus points`() {
        let viewModel = makeRawCullViewModel()

        viewModel.openZoomOverlay(
            initialSource: .embeddedJPG,
            initialZoomMode: .actualPixels,
            showFocusPointsOnOpen: true,
        )

        #expect(viewModel.zoomOverlay.launchContext.initialSource == .embeddedJPG)
        #expect(viewModel.zoomOverlay.launchContext.initialZoomMode == .actualPixels)
        #expect(viewModel.zoomOverlay.launchContext.showFocusPointsOnOpen)
    }
}
