import CoreGraphics
import Foundation
@testable import RawCull
import Testing

@MainActor
@Suite("ZoomOverlayLaunchContext")
struct ZoomOverlayLaunchContextTests {
    @Test
    func `default zoom overlay launch context preserves existing behavior`() {
        let viewModel = makeRawCullViewModel()

        viewModel.openZoomOverlay()

        #expect(viewModel.zoomOverlayLaunchContext == .default)
        #expect(viewModel.zoomOverlayLaunchContext.initialSource == .thumbnail)
        #expect(viewModel.zoomOverlayLaunchContext.initialZoomMode == .fit)
        #expect(viewModel.zoomOverlayLaunchContext.showFocusPointsOnOpen == false)
    }

    @Test
    func `actual-pixels launch context requests embedded JPG and focus points`() {
        let viewModel = makeRawCullViewModel()

        viewModel.openZoomOverlay(
            initialSource: .embeddedJPG,
            initialZoomMode: .actualPixels,
            showFocusPointsOnOpen: true,
        )

        #expect(viewModel.zoomOverlayLaunchContext.initialSource == .embeddedJPG)
        #expect(viewModel.zoomOverlayLaunchContext.initialZoomMode == .actualPixels)
        #expect(viewModel.zoomOverlayLaunchContext.showFocusPointsOnOpen)
    }
}
