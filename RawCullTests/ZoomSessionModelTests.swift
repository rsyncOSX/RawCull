import CoreGraphics
import Foundation
@testable import RawCull
import Testing

@MainActor
@Suite("ZoomSessionModel")
struct ZoomSessionModelTests {
    @Test
    func `preview clipping warning distinguishes white black and ordinary colors`() async throws {
        let samples: [UInt8] = [
            255, 255, 255, 255,
            0, 0, 0, 255,
            128, 128, 128, 255,
            255, 0, 0, 255
        ]
        let provider = try #require(CGDataProvider(data: Data(samples) as CFData))
        let source = try #require(try CGImage(
            width: 4, height: 1, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: 16,
            space: #require(CGColorSpace(name: CGColorSpace.sRGB)),
            bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue)
                .union(.byteOrder32Big),
            provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent,
        ))
        let overlay = try #require(await RAWPreviewClippingOverlay.make(from: source))
        let data = try #require(overlay.dataProvider?.data)
        let bytes = try #require(CFDataGetBytePtr(data))
        #expect(Array(UnsafeBufferPointer(start: bytes, count: 16)) == [
            180, 0, 0, 180,
            0, 0, 180, 180,
            0, 0, 0, 0,
            0, 0, 0, 0
        ])
    }

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
