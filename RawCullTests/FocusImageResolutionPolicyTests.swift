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

    @Test(arguments: [(width: 1200, height: 800), (width: 2048, height: 1365), (width: 1365, height: 2048)])
    func `analysis previews measure masks at the calibration size`(dimensions: (width: Int, height: Int)) throws {
        let image = try makeImage(width: dimensions.width, height: dimensions.height)

        let result = FocusMaskAnalysisResolutionPolicy.calibrationScaled(image)

        #expect(max(result.width, result.height) == FocusMaskAnalysisResolutionPolicy.calibrationMaximumPixelSize)
        // Aspect ratio and orientation are kept.
        #expect((result.width > result.height) == (dimensions.width > dimensions.height))
    }

    @Test func `images already at the calibration size are not resampled`() throws {
        let image = try makeImage(width: 1616, height: 1080)
        #expect(FocusMaskAnalysisResolutionPolicy.calibrationScaled(image) === image)
    }

    @Test func `the visual threshold is calibrated on the source masks render`() {
        #expect(FocusMaskAnalysisResolutionPolicy.calibrationSource == .embeddedPreview)
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
