import CoreGraphics
@testable import RawCull
import Testing

struct DeepAIReviewMaskOutlineRendererTests {
    @Test
    func `filled mask becomes a transparent contour`() async throws {
        let mask = try #require(makeMask())
        let outline = try #require(
            await DeepAIReviewMaskOutlineRenderer.outline(from: mask),
        )
        let alpha = try #require(alphaPixels(from: outline))

        #expect(outline.width == mask.width)
        #expect(outline.height == mask.height)
        #expect(sample(alpha, x: 16, y: 16, width: outline.width) == 0)
        #expect(sample(alpha, x: 8, y: 16, width: outline.width) > 0)
        #expect(sample(alpha, x: 1, y: 1, width: outline.width) == 0)
    }

    @Test
    func `disconnected subjects each receive a contour`() async throws {
        let mask = try #require(makeMask(rectangles: [
            CGRect(x: 4, y: 8, width: 8, height: 16),
            CGRect(x: 20, y: 8, width: 8, height: 16),
        ]))
        let outline = try #require(
            await DeepAIReviewMaskOutlineRenderer.outline(from: mask),
        )
        let alpha = try #require(alphaPixels(from: outline))

        #expect(sample(alpha, x: 4, y: 16, width: outline.width) > 0)
        #expect(sample(alpha, x: 27, y: 16, width: outline.width) > 0)
        #expect(sample(alpha, x: 16, y: 16, width: outline.width) == 0)
    }

    private func makeMask() -> CGImage? {
        makeMask(rectangles: [CGRect(x: 8, y: 8, width: 16, height: 16)])
    }

    private func makeMask(rectangles: [CGRect]) -> CGImage? {
        let width = 32
        let height = 32
        guard let context = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue,
        ) else { return nil }

        context.clear(CGRect(x: 0, y: 0, width: width, height: height))
        context.setFillColor(CGColor(gray: 1, alpha: 1))
        for rectangle in rectangles {
            context.fill(rectangle)
        }
        return context.makeImage()
    }

    private func alphaPixels(from image: CGImage) -> [UInt8]? {
        var pixels = [UInt8](repeating: 0, count: image.width * image.height * 4)
        guard let context = CGContext(
            data: &pixels,
            width: image.width,
            height: image.height,
            bitsPerComponent: 8,
            bytesPerRow: image.width * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue,
        ) else { return nil }

        context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        return stride(from: 3, to: pixels.count, by: 4).map { pixels[$0] }
    }

    private func sample(_ pixels: [UInt8], x column: Int, y row: Int, width: Int) -> UInt8 {
        pixels[row * width + column]
    }
}
