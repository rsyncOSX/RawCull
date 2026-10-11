import CoreGraphics
import Foundation
import ImageIO
@testable import RawCull
import Testing
import UniformTypeIdentifiers

@Suite("Subject mask representation regressions", .tags(.smoke))
struct SubjectMaskFocusRegressionTests {
    @Test func `disjoint grayscale masks select different textures through PNG retention`() async throws {
        let image = try Self.image()
        let left = try Self.mask(right: false)
        let right = try Self.mask(right: true)
        let store = ReviewArtifactStore(root: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString))
        defer { try? FileManager.default.removeItem(at: store.root) }
        let data = NSMutableData()
        let destination = try #require(CGImageDestinationCreateWithData(data, UTType.png.identifier as CFString, 1, nil))
        CGImageDestinationAddImage(destination, right, nil)
        #expect(CGImageDestinationFinalize(destination))
        let key = try await store.retainInput(data as Data)
        let saved = try await store.input(key)
        let source = try #require(CGImageSourceCreateWithData(saved as CFData, nil))
        let reloaded = try #require(CGImageSourceCreateImageAtIndex(source, 0, nil))
        #expect(reloaded.colorSpace?.model == .monochrome)
        #expect(reloaded.alphaInfo == .none)
        let scorer = SubjectMaskFocusScorer()
        let smooth = try #require(try await scorer.score(image: image, subjectMask: left, normalizedAFPoint: CGPoint(x: 0.25, y: 0.5)))
        let textured = try #require(try await scorer.score(image: image, subjectMask: reloaded, normalizedAFPoint: CGPoint(x: 0.25, y: 0.5)))
        withKnownIssue("F1: opaque grayscale is incorrectly consumed as alpha") {
            #expect(smooth.maskCoverage < 0.5)
            #expect(textured.finalScore > smooth.finalScore)
            #expect(textured.autofocusInsideMask == false)
        }
        #expect(try await scorer.score(image: image, subjectMask: reloaded, normalizedAFPoint: CGPoint(x: 0.25, y: 0.5)) == textured)
    }

    private nonisolated static func image() throws -> CGImage {
        let side = 128
        let pixels = (0 ..< side * side).map { index -> UInt8 in
            let x = index % side
            return x < side / 2 ? 128 : (x % 4 < 2 ? 32 : 224)
        }
        return try gray(pixels, width: side, height: side)
    }

    private nonisolated static func mask(right: Bool) throws -> CGImage {
        let side = 128
        return try gray((0 ..< side * side).map { index in
            ((index % side >= side / 2) == right) ? UInt8(255) : 0
        }, width: side, height: side)
    }

    private nonisolated static func gray(_ pixels: [UInt8], width: Int, height: Int) throws -> CGImage {
        let provider = try #require(CGDataProvider(data: Data(pixels) as CFData))
        return try #require(CGImage(width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 8,
                                   bytesPerRow: width, space: CGColorSpaceCreateDeviceGray(),
                                   bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.none.rawValue), provider: provider,
                                   decode: nil, shouldInterpolate: false, intent: .defaultIntent))
    }
}
