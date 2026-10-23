import CoreGraphics
import Foundation
@testable import RawCull
import Testing

@Suite("Zoom overlay image policy")
struct ZoomOverlayImagePolicyTests {
    @Test
    func `dedicated thumbnail analysis pixels are preferred over display pixels`() throws {
        let displayImage = try makeZoomPolicyImage(gray: 0.75)
        let analysisImage = try makeZoomPolicyImage(gray: 0.25)

        let selected = ZoomOverlayImagePolicy.analysisImage(
            dedicatedAnalysisImage: analysisImage,
            displayImage: displayImage,
        )

        #expect(selected === analysisImage)
    }

    @Test
    func `CG display image remains the analysis fallback`() throws {
        let displayImage = try makeZoomPolicyImage(gray: 0.5)

        let selected = ZoomOverlayImagePolicy.analysisImage(
            dedicatedAnalysisImage: nil,
            displayImage: displayImage,
        )

        #expect(selected === displayImage)
    }
}

private func makeZoomPolicyImage(gray: CGFloat) throws -> CGImage {
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
