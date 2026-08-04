import CoreGraphics
import PhotoAnalysisKit
@testable import RawCull
import Testing

@Suite("PhotoAnalysisKit integration")
struct PhotoAnalysisKitIntegrationTests {
    @Test(.tags(.smoke))
    @MainActor
    func `RawCull focus model analyzes through package Metal pipeline`() async throws {
        let image = try #require(makeIntegrationCheckerboard())
        let model = FocusMaskModel()

        let result = await model.generateFocusMaskWithBreakdown(
            from: image,
            scale: 1,
            iso: 800,
            aperture: 4,
        )

        #expect(result.mask != nil)
        let breakdown = try #require(result.breakdown)
        #expect(breakdown.finalScore.isFinite)
        #expect((0 ... 1).contains(breakdown.finalScore))
    }

    @Test(.tags(.smoke))
    func `RawCull breakdown preserves app scoring source`() {
        let packageBreakdown = PhotoAnalysisKit.SharpnessBreakdown(
            finalScore: 0.72,
            globalScore: 0.61,
            subjectScore: 0.72,
            afPointScore: 0.75,
            blurGateSigma: 0.03,
            subjectLabel: "bird",
            subjectConfidence: 0.9,
            focusFailureKind: .none,
        )

        let breakdown = RawCull.SharpnessBreakdown(
            package: packageBreakdown,
            scoringSource: .rawDemosaic,
        )

        #expect(breakdown.finalScore == packageBreakdown.finalScore)
        #expect(breakdown.focusFailureKind == packageBreakdown.focusFailureKind)
        #expect(breakdown.scoringSource == .rawDemosaic)
    }
}

private func makeIntegrationCheckerboard(size: Int = 128) -> CGImage? {
    guard let colorSpace = CGColorSpace(name: CGColorSpace.sRGB),
          let context = CGContext(
              data: nil,
              width: size,
              height: size,
              bitsPerComponent: 8,
              bytesPerRow: size * 4,
              space: colorSpace,
              bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue,
          )
    else { return nil }

    context.setFillColor(gray: 0.08, alpha: 1)
    context.fill(CGRect(x: 0, y: 0, width: size, height: size))
    context.setFillColor(gray: 0.92, alpha: 1)
    let tile = 8
    for y in stride(from: 0, to: size, by: tile) {
        for x in stride(from: 0, to: size, by: tile)
            where (x / tile + y / tile).isMultiple(of: 2) {
            context.fill(CGRect(x: x, y: y, width: tile, height: tile))
        }
    }
    return context.makeImage()
}
