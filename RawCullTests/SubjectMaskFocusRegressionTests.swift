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
        #expect(smooth.maskCoverage < 0.5)
        #expect(textured.finalScore > smooth.finalScore)
        #expect(textured.autofocusInsideMask == false)
        #expect(try await scorer.score(image: image, subjectMask: reloaded, normalizedAFPoint: CGPoint(x: 0.25, y: 0.5)) == textured)
    }

    @Test func `grayscale and alpha have equivalent support bounds and scores`() async throws {
        let image = try Self.image()
        let gray = try Self.mask(right: true)
        let context = try #require(CGContext(data: nil, width: 128, height: 128, bitsPerComponent: 8,
                                             bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(),
                                             bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue))
        context.clear(CGRect(x: 0, y: 0, width: 128, height: 128))
        context.setFillColor(CGColor(gray: 1, alpha: 1))
        context.fill(CGRect(x: 64, y: 0, width: 64, height: 128))
        let alpha = try #require(context.makeImage())
        let foreground = try SubjectMaskForeground.decode(gray, width: 128, height: 128)
        #expect(try foreground.pixels == (SubjectMaskForeground.decode(alpha, width: 128, height: 128)).pixels)
        #expect(foreground.foregroundCount == 8192)
        #expect(foreground.bounds == CGRect(x: 64, y: 0, width: 64, height: 128))
        let scorer = SubjectMaskFocusScorer()
        let a = try #require(try await scorer.score(image: image, subjectMask: gray, normalizedAFPoint: nil))
        let b = try #require(try await scorer.score(image: image, subjectMask: alpha, normalizedAFPoint: nil))
        #expect(a == b)
        #expect(a.scorerVersion == SubjectMaskFocusScorer.semanticsVersion)
        #expect(a.foregroundCount == 8192)
        #expect(a.usableForegroundCount == 7688)
        #expect(a.interiorPixelCount == 15376)
        #expect(a.borderPixels == 2)
    }

    @Test func `empty sparse and mismatched masks abstain explicitly while full masks are suspect`() async throws {
        let image = try Self.image()
        let empty = try Self.gray(Array(repeating: 0, count: 16384), width: 128, height: 128)
        await #expect(throws: SubjectMaskDecodingError.emptyForeground) {
            try await SubjectMaskFocusScorer().score(image: image, subjectMask: empty, normalizedAFPoint: nil)
        }
        var pixels = Array(repeating: UInt8(0), count: 16384)
        pixels[64 * 128 + 64] = 255
        let sparse = try Self.gray(pixels, width: 128, height: 128)
        await #expect(throws: SubjectMaskDecodingError.insufficientUsablePixels) {
            try await SubjectMaskFocusScorer().score(image: image, subjectMask: sparse, normalizedAFPoint: nil)
        }
        #expect(throws: SubjectMaskDecodingError.unsafeRegistration) {
            try SubjectMaskForeground.decode(empty, width: 64, height: 128)
        }
        let full = try Self.gray(Array(repeating: 255, count: 16384), width: 128, height: 128)
        let evidence = try #require(try await SubjectMaskFocusScorer().score(image: image, subjectMask: full, normalizedAFPoint: nil))
        #expect(evidence.suspectNearFullOccupancy == true)
        #expect(evidence.foregroundCount == 16384)
        #expect(evidence.maskCoverage == 0.9384765625)
    }

    @Test func `padded grayscale rows preserve raw threshold and contract registration`() throws {
        let provider = try #require(CGDataProvider(data: Data([0, 16, 17, 255, 99, 99, 255, 17, 16, 0, 99, 99]) as CFData))
        let mask = try #require(CGImage(width: 4, height: 2, bitsPerComponent: 8, bitsPerPixel: 8,
                                        bytesPerRow: 6, space: CGColorSpaceCreateDeviceGray(),
                                        bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.none.rawValue),
                                        provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent))
        let decoded = try SubjectMaskForeground.decode(mask, width: 4, height: 2)
        #expect(decoded.pixels == [0, 16, 17, 255, 255, 17, 16, 0])
        #expect(decoded.foregroundCount == 4)
        let contract = try SubjectMaskContract.make(mask: mask, sourceIdentity: "source")
        #expect(try JSONDecoder().decode(SubjectMaskContract.self, from: JSONEncoder().encode(contract)) == contract)
        #expect(throws: SubjectMaskDecodingError.unsafeRegistration) { try contract.validate(mask: mask, sourceIdentity: "other") }
        let rgb = try #require(CGContext(data: nil, width: 4, height: 2, bitsPerComponent: 8, bytesPerRow: 0,
                                         space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)?.makeImage())
        #expect(throws: SubjectMaskDecodingError.unsupportedEncoding) { try SubjectMaskForeground.decode(rgb, width: 4, height: 2) }
    }

    @Test func `high ISO noise does not let a noisier copy outrank the clean frame`() async throws {
        let (width, height) = (2048, 1365)
        let clean = Self.blockTexture(width: width, height: height, noise: 0)
        let noisy = Self.blockTexture(width: width, height: height, noise: 40)
        let mask = try Self.gray(Self.centerMask(width: width, height: height), width: width, height: height)
        let scorer = SubjectMaskFocusScorer()
        let cleanScore = try #require(try await scorer.score(
            image: Self.gray(clean, width: width, height: height), subjectMask: mask, normalizedAFPoint: nil, iso: 6400,
        ))
        let noisyScore = try #require(try await scorer.score(
            image: Self.gray(noisy, width: width, height: height), subjectMask: mask, normalizedAFPoint: nil, iso: 6400,
        ))
        // Noise always adds some edge energy; it must not decide the ranking.
        #expect(noisyScore.finalScore <= cleanScore.finalScore * 1.05)
    }

    @Test func `subject detail is comparable across embedded and RAW decode sizes`() async throws {
        let scorer = SubjectMaskFocusScorer()
        var scores: [Float] = []
        for (width, height) in [(1616, 1080), (2048, 1365)] {
            let image = try Self.gray(Self.blockTexture(width: width, height: height, noise: 0, longSideBlocks: 128),
                                      width: width, height: height)
            let mask = try Self.gray(Self.centerMask(width: width, height: height), width: width, height: height)
            let evidence = try #require(try await scorer.score(image: image, subjectMask: mask, normalizedAFPoint: nil))
            scores.append(evidence.finalScore)
        }
        #expect(abs(scores[0] - scores[1]) <= max(scores[0], scores[1]) * 0.10)
    }

    @Test func `working size never upsamples and shrinks with ISO`() {
        #expect(SubjectMaskFocusScorer.workingSize(width: 128, height: 96, iso: 6400) == (128, 96))
        #expect(SubjectMaskFocusScorer.workingSize(width: 2048, height: 1365, iso: nil).width == 1024)
        #expect(SubjectMaskFocusScorer.workingSize(width: 1616, height: 1080, iso: 200).width == 1024)
        #expect(SubjectMaskFocusScorer.workingSize(width: 2048, height: 1365, iso: 6400).width < 1024)
    }

    /// Blocks scaled with the frame (`longSideBlocks` across the long side) so detail is
    /// the same scene at any decode size; optional seeded uniform noise of ±`noise` levels.
    private nonisolated static func blockTexture(width: Int, height: Int, noise: Int, longSideBlocks: Int = 128) -> [UInt8] {
        var state: UInt64 = 0x9E37_79B9_7F4A_7C15
        let block = Double(max(width, height)) / Double(longSideBlocks)
        return (0 ..< width * height).map { index in
            let x = index % width, y = index / width
            let base = (Int(Double(x) / block) + Int(Double(y) / block)) % 2 == 0 ? 80 : 176
            guard noise > 0 else { return UInt8(base) }
            state = state &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
            let offset = Int(state >> 33) % (2 * noise + 1) - noise
            return UInt8(clamping: base + offset)
        }
    }

    private nonisolated static func centerMask(width: Int, height: Int) -> [UInt8] {
        (0 ..< width * height).map { index in
            let x = index % width, y = index / width
            return (width / 4 ..< width * 3 / 4).contains(x) && (height / 4 ..< height * 3 / 4).contains(y) ? 255 : 0
        }
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
            (right ? index % side >= side / 2 : index % side < side / 2 - 4) ? UInt8(255) : 0
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
