import CoreGraphics
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
        ) == .toggleEmbeddedJPG)
        #expect(ZoomOverlayKeyAction.resolve(
            characters: "J",
            keyCode: 0,
            navigationAxis: .horizontal,
        ) == .toggleEmbeddedJPG)
        #expect(ZoomOverlayKeyAction.resolve(
            characters: "r",
            keyCode: 0,
            navigationAxis: .horizontal,
        ) == .toggleDevelopedRAW)
        #expect(ZoomOverlayKeyAction.resolve(
            characters: "R",
            keyCode: 0,
            navigationAxis: .horizontal,
        ) == .toggleDevelopedRAW)
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

@Suite("ImageSourceSelectionState")
struct ImageSourceSelectionStateTests {
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

@MainActor
@Suite("ZoomOverlayLaunchContext")
struct ZoomOverlayLaunchContextTests {
    @Test
    func `default zoom overlay launch context preserves existing behavior`() {
        let viewModel = RawCullViewModel()

        viewModel.openZoomOverlay()

        #expect(viewModel.zoomOverlayLaunchContext == .default)
        #expect(viewModel.zoomOverlayLaunchContext.initialSource == .thumbnail)
        #expect(viewModel.zoomOverlayLaunchContext.initialZoomMode == .fit)
        #expect(viewModel.zoomOverlayLaunchContext.showFocusPointsOnOpen == false)
    }

    @Test
    func `actual-pixels launch context requests embedded JPG and focus points`() {
        let viewModel = RawCullViewModel()

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

@Suite("ZoomViewportMath")
struct ZoomViewportMathTests {
    @Test(.tags(.smoke))
    func `landscape inspection maps one image pixel to one display point`() {
        let scale = ZoomViewportMath.actualPixelsScale(
            imageSize: CGSize(width: 6000, height: 4000),
            viewportSize: CGSize(width: 1500, height: 1000),
        )

        #expect(scale == 4)
    }

    @Test(.tags(.smoke))
    func `portrait inspection maps one image pixel to one display point`() {
        let scale = ZoomViewportMath.actualPixelsScale(
            imageSize: CGSize(width: 4000, height: 6000),
            viewportSize: CGSize(width: 1000, height: 1500),
        )

        #expect(scale == 4)
    }

    @Test(.tags(.smoke))
    func `inspection scale reduces a fit-upscaled preview to actual pixels`() {
        let scale = ZoomViewportMath.actualPixelsScale(
            imageSize: CGSize(width: 800, height: 600),
            viewportSize: CGSize(width: 1600, height: 1200),
        )

        #expect(scale == 0.5)
    }

    @Test(.tags(.smoke))
    func `aspect mismatch still maps the fitted image to actual pixels`() {
        let fitRect = ZoomViewportMath.aspectFitRect(
            imageSize: CGSize(width: 6000, height: 4000),
            in: CGSize(width: 1200, height: 1200),
        )
        let scale = ZoomViewportMath.actualPixelsScale(
            imageSize: CGSize(width: 6000, height: 4000),
            viewportSize: CGSize(width: 1200, height: 1200),
        )

        #expect(fitRect == CGRect(x: 0, y: 200, width: 1200, height: 800))
        #expect(scale == 5)
        #expect(fitRect.width * scale == 6000)
        #expect(fitRect.height * scale == 4000)
    }

    @Test(.tags(.smoke))
    func `focus point pan centers a normalized point when there is room`() {
        let transform = ZoomViewportMath.actualPixelsTransform(
            imageSize: CGSize(width: 6000, height: 4000),
            viewportSize: CGSize(width: 1500, height: 1000),
            normalizedFocusPoint: CGPoint(x: 0.40, y: 0.50),
        )

        #expect(transform.scale == 4)
        #expect(transform.offset.width == 600)
        #expect(transform.offset.height == 0.0)
    }

    @Test(.tags(.smoke))
    func `focus point pan clamps at all four image edges`() {
        let imageSize = CGSize(width: 6000, height: 4000)
        let viewportSize = CGSize(width: 1500, height: 1000)

        let left = ZoomViewportMath.actualPixelsTransform(
            imageSize: imageSize,
            viewportSize: viewportSize,
            normalizedFocusPoint: CGPoint(x: 0, y: 0.5),
        )
        let right = ZoomViewportMath.actualPixelsTransform(
            imageSize: imageSize,
            viewportSize: viewportSize,
            normalizedFocusPoint: CGPoint(x: 1, y: 0.5),
        )
        let top = ZoomViewportMath.actualPixelsTransform(
            imageSize: imageSize,
            viewportSize: viewportSize,
            normalizedFocusPoint: CGPoint(x: 0.5, y: 0),
        )
        let bottom = ZoomViewportMath.actualPixelsTransform(
            imageSize: imageSize,
            viewportSize: viewportSize,
            normalizedFocusPoint: CGPoint(x: 0.5, y: 1),
        )

        #expect(left.offset == CGSize(width: 2250, height: 0))
        #expect(right.offset == CGSize(width: -2250, height: 0))
        #expect(top.offset == CGSize(width: 0, height: 1500))
        #expect(bottom.offset == CGSize(width: 0, height: -1500))
    }

    @Test(.tags(.smoke))
    func `out of range focus point clamps to an image edge`() {
        let transform = ZoomViewportMath.actualPixelsTransform(
            imageSize: CGSize(width: 6000, height: 4000),
            viewportSize: CGSize(width: 1500, height: 1000),
            normalizedFocusPoint: CGPoint(x: -2, y: 3),
        )

        #expect(transform.offset == CGSize(width: 2250, height: -1500))
    }

    @Test(.tags(.smoke))
    func `missing focus point keeps actual-pixels view centered`() {
        let transform = ZoomViewportMath.actualPixelsTransform(
            imageSize: CGSize(width: 6000, height: 4000),
            viewportSize: CGSize(width: 1500, height: 1000),
            normalizedFocusPoint: nil,
        )

        #expect(transform.scale == 4)
        #expect(transform.offset == .zero)
    }

    @Test(.tags(.smoke))
    func `invalid sizes use a finite centered fallback`() {
        let invalidSizes = [
            CGSize(width: 0, height: 4000),
            CGSize(width: -1, height: 4000),
            CGSize(width: CGFloat.infinity, height: 4000),
            CGSize(width: CGFloat.nan, height: 4000)
        ]

        for invalidSize in invalidSizes {
            let transform = ZoomViewportMath.actualPixelsTransform(
                imageSize: invalidSize,
                viewportSize: CGSize(width: 1500, height: 1000),
                normalizedFocusPoint: CGPoint(x: 0.5, y: 0.5),
            )

            #expect(transform.scale == 1)
            #expect(transform.scale.isFinite)
            #expect(transform.offset == .zero)
        }
    }

    @Test(.tags(.smoke))
    func `non finite focus point uses a centered fallback`() {
        let transform = ZoomViewportMath.actualPixelsTransform(
            imageSize: CGSize(width: 6000, height: 4000),
            viewportSize: CGSize(width: 1500, height: 1000),
            normalizedFocusPoint: CGPoint(x: CGFloat.nan, y: 0.5),
        )

        #expect(transform.scale == 4)
        #expect(transform.offset == .zero)
    }
}

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

    @Test(.tags(.smoke), arguments: ["a", "A"])
    func `A resolves to autofocus points`(characters: String) {
        #expect(LoupeImageKeyAction.resolve(characters: characters) == .toggleFocusPoints)
    }

    @Test(.tags(.smoke), arguments: ["z", "Z"])
    func `Z resolves to actual-pixels inspection`(characters: String) {
        #expect(LoupeImageKeyAction.resolve(characters: characters) == .inspectActualPixels)
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
