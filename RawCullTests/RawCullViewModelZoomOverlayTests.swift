import AppKit
import CoreGraphics
@testable import RawCull
import Testing

@Suite("RawCullViewModel zoom overlay")
struct RawCullViewModelZoomOverlayTests {
    @MainActor
    @Test
    func `opening zoom overlay from loupe uses vertical navigation`() {
        let viewModel = RawCullViewModel()
        viewModel.selectMainViewMode(.loupe)

        viewModel.openZoomOverlay()

        #expect(viewModel.zoomOverlayVisible == true)
        #expect(viewModel.zoomOverlayNavigationAxis == .vertical)
    }

    @MainActor
    @Test(arguments: [
        MainViewMode.grid,
        MainViewMode.similarityGrid,
        MainViewMode.ratedGrid,
        MainViewMode.comparisonGrid
    ])
    func `opening zoom overlay from non loupe modes uses horizontal navigation`(
        mode: MainViewMode,
    ) {
        let viewModel = RawCullViewModel()
        viewModel.selectMainViewMode(mode)

        viewModel.openZoomOverlay()

        #expect(viewModel.zoomOverlayVisible == true)
        #expect(viewModel.zoomOverlayNavigationAxis == .horizontal)
    }

    @MainActor
    @Test
    func `selecting main view mode closes zoom overlay`() throws {
        for mode in MainViewMode.allCases {
            let viewModel = RawCullViewModel()
            viewModel.zoomOverlayVisible = true
            viewModel.zoomOverlayCGImage = try #require(makeOnePixelCGImage())
            viewModel.zoomOverlayNSImage = NSImage(size: NSSize(width: 1, height: 1))
            viewModel.zoomExtractionTask = Task {}

            viewModel.selectMainViewMode(mode)

            #expect(viewModel.mainViewMode == mode)
            #expect(viewModel.zoomOverlayVisible == false)
            #expect(viewModel.zoomOverlayCGImage == nil)
            #expect(viewModel.zoomOverlayNSImage == nil)
            #expect(viewModel.zoomExtractionTask == nil)
        }
    }

    @MainActor
    @Test
    func `selecting non similarity mode disables burst mode`() {
        let viewModel = RawCullViewModel()
        viewModel.similarityModel.burstModeActive = true

        viewModel.selectMainViewMode(.grid)

        #expect(viewModel.similarityModel.burstModeActive == false)
    }

    @MainActor
    @Test
    func `selecting similarity mode preserves burst mode`() {
        let viewModel = RawCullViewModel()
        viewModel.similarityModel.burstModeActive = true

        viewModel.selectMainViewMode(.similarityGrid)

        #expect(viewModel.similarityModel.burstModeActive == true)
    }

    private func makeOnePixelCGImage() -> CGImage? {
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let context = CGContext(
            data: nil,
            width: 1,
            height: 1,
            bitsPerComponent: 8,
            bytesPerRow: 4,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue,
        )
        context?.setFillColor(NSColor.white.cgColor)
        context?.fill(CGRect(x: 0, y: 0, width: 1, height: 1))
        return context?.makeImage()
    }
}
