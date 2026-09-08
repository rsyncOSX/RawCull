import CoreGraphics
@testable import RawCull
import Testing

@MainActor
@Suite("Comparison image analysis source")
struct ComparisonImageAnalysisSourceTests {
    @Test
    func `thumbnail sharpening changes display but not analysis pixels`() throws {
        let unsharpened = try makeImage(gray: 0.25)
        let sharpened = try makeImage(gray: 0.75)

        let decoded = ComparisonImageLoader.thumbnailImages(
            unsharpened: unsharpened,
            sharpened: sharpened,
            sharpeningEnabled: true,
        )

        #expect(decoded.displayCGImage === sharpened)
        #expect(decoded.analysisCGImage === unsharpened)
    }

    private func makeImage(gray: CGFloat) throws -> CGImage {
        let context = try #require(CGContext(
            data: nil,
            width: 8,
            height: 8,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue,
        ))
        context.setFillColor(gray: gray, alpha: 1)
        context.fill(CGRect(x: 0, y: 0, width: 8, height: 8))
        return try #require(context.makeImage())
    }
}
