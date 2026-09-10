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

    @Test
    func `embedded JPG displays extracted pixels but analyzes thumbnail pixels`() throws {
        let extractedJPG = try makeImage(gray: 0.25)
        let thumbnail = try makeImage(gray: 0.75)

        let decoded = ComparisonImageLoader.embeddedJPGImages(
            display: extractedJPG,
            analysis: thumbnail,
        )

        #expect(decoded.displayCGImage === extractedJPG)
        #expect(decoded.analysisCGImage === thumbnail)
    }

    @Test
    func `embedded JPG falls back to extracted pixels when thumbnail is unavailable`() throws {
        let extractedJPG = try makeImage(gray: 0.25)

        let decoded = ComparisonImageLoader.embeddedJPGImages(
            display: extractedJPG,
            analysis: nil,
        )

        #expect(decoded.displayCGImage === extractedJPG)
        #expect(decoded.analysisCGImage === extractedJPG)
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
