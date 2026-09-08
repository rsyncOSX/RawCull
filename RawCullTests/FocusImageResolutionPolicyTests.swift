import CoreGraphics
@testable import RawCull
import Testing

@MainActor
@Suite("Focus image resolution policy")
struct FocusImageResolutionPolicyTests {
    @Test(arguments: [(width: 2048, height: 1024), (width: 1024, height: 2048), (width: 128, height: 64)])
    func `analysis preserves decoded pixels for every orientation`(dimensions: (width: Int, height: Int)) throws {
        let image = try makeImage(width: dimensions.width, height: dimensions.height)

        let result = FocusMaskAnalysisResolutionPolicy.prepare(image)

        #expect(result === image)
        #expect(result.width == dimensions.width)
        #expect(result.height == dimensions.height)
    }

    private func makeImage(width: Int, height: Int) throws -> CGImage {
        let context = try #require(CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue,
        ))
        context.setFillColor(CGColor(red: 0.8, green: 0.2, blue: 0.1, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        return try #require(context.makeImage())
    }
}
