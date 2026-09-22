import CoreGraphics
import Foundation
@testable import RawCull
import Testing

@MainActor
@Suite("LoupeSessionModel")
struct LoupeSessionModelTests {
    @Test
    func `new source request rejects stale completion`() async {
        let model = LoupeSessionModel()
        model.selectSource(.embeddedJPG)
        model.beginSourceLoad { _ in
            try? await Task.sleep(for: .milliseconds(100))
            return Self.pixel()
        }

        model.selectSource(.developedRAW)
        model.beginSourceLoad { _ in Self.pixel() }
        try? await Task.sleep(for: .milliseconds(150))

        #expect(model.developedRAWImage != nil)
        #expect(model.embeddedJPGImage == nil)
        #expect(!model.isLoadingSource)
    }

    @Test
    func `reset cancels work and clears owned previews`() async {
        let model = LoupeSessionModel()
        model.selectSource(.embeddedJPG)
        model.beginSourceLoad { _ in
            try? await Task.sleep(for: .milliseconds(100))
            return Self.pixel()
        }

        model.resetForNewImage()
        try? await Task.sleep(for: .milliseconds(150))

        #expect(model.embeddedJPGImage == nil)
        #expect(!model.isLoadingSource)
    }

    private static func pixel() -> CGImage {
        CGImage(
            width: 1,
            height: 1,
            bitsPerComponent: 8,
            bitsPerPixel: 32,
            bytesPerRow: 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
            provider: CGDataProvider(data: Data([0, 0, 0, 255]) as CFData)!,
            decode: nil,
            shouldInterpolate: false,
            intent: .defaultIntent,
        )!
    }
}
