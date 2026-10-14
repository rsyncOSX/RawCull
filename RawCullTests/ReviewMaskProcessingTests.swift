import CoreGraphics
import Foundation
@testable import RawCull
import Testing

@Suite("Combined Review background mask processing")
struct ReviewMaskProcessingTests {
    @Test func `background registration preserves producer diagnostics and deduplicated geometry`() async throws {
        let mask = try mask(bounds: CGRect(x: 12, y: 16, width: 36, height: 24))
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".png")
        defer { try? FileManager.default.removeItem(at: url) }
        try ReviewImageSource.pngData(for: mask).write(to: url)
        let source = try await ReviewImageSourceService().load(.init(url: url, preference: .highQualityPreview, policy: .appearance))
        let producer = CGRect(x: 0.1, y: 0.2, width: 0.5, height: 0.5)
        let candidate = try ObjectInstanceDeduplicator.candidate(concept: "bird", mask: mask, score: 0.9, bounds: producer, id: "bird")
        let expected = try ReviewMaskRegistration.make(mask: mask, source: source, producerBounds: producer)
        let worker = ReviewMaskProcessing()
        let registered = try await worker.register([candidate], source: source)
        let value = try #require(registered.first)
        #expect(value.registration == expected)
        #expect(value.retained.descriptor.normalizedBoundingBox == expected.normalizedBounds(width: mask.width, height: mask.height))
        #expect(value.retained.mask === mask)
        #expect(value.registration.warning != nil)
    }

    @Test func `crop support matches original scans and invalidates cache when mask changes`() async throws {
        let worker = ReviewMaskProcessing()
        let subject = ReviewSubjectID(rawValue: "subject")
        let first = try mask(bounds: CGRect(x: 0, y: 0, width: 30, height: 20))
        let second = try mask(bounds: CGRect(x: 80, y: 50, width: 30, height: 20))
        let crop = CGRect(x: 0, y: 0, width: 60, height: 40)
        let encoder = CGRect(x: 10, y: 0, width: 30, height: 40)
        for mask in [first, first, second] {
            let expected = try SubjectMaskForeground.decode(mask, width: 120, height: 80)
            let support = try await worker.cropSupport(subjectID: subject, mask: mask, width: 120, height: 80,
                                                       cropRect: crop, encoderRect: encoder, sourceEdgeContact: true)
            #expect(support.subjectForegroundRetained == ReviewMaskRegistration.retainedFraction(expected, in: crop))
            #expect(support.encoderForegroundRetained == ReviewMaskRegistration.retainedFraction(expected, in: encoder))
            #expect(support.sourceEdgeContact)
        }
    }

    @Test @MainActor func `retained inputs preserve grayscale foreground when eagerly decoded`() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = ReviewArtifactStore(root: root)
        let feature = CombinedReviewFeature(store: store, lease: CombinedReviewLease(), backendFactory: { throw ReviewRunError.modelUnavailable })
        let original = try mask(bounds: CGRect(x: 20, y: 10, width: 30, height: 25))
        let key = try await store.retainInput(ReviewImageSource.pngData(for: original))
        let loaded = try #require(await feature.exactInput(key))
        let before = try SubjectMaskForeground.decode(original, width: 120, height: 80)
        let after = try SubjectMaskForeground.decode(loaded, width: 120, height: 80)
        #expect(after.pixels == before.pixels)
        #expect(after.bounds == before.bounds)
        #expect(after.foregroundCount == before.foregroundCount)
    }

    @Test @MainActor func `cancelled worker operation refuses a raster scan`() async throws {
        let worker = ReviewMaskProcessing()
        let mask = try mask(bounds: CGRect(x: 0, y: 0, width: 30, height: 20))
        let task = Task {
            try await worker.cropSupport(subjectID: .init(rawValue: "subject"), mask: mask, width: 120, height: 80,
                                         cropRect: .zero, encoderRect: .zero, sourceEdgeContact: false)
        }
        task.cancel()
        await #expect(throws: CancellationError.self) { try await task.value }
    }

    private func mask(bounds: CGRect) throws -> CGImage {
        let pixels = (0 ..< 120 * 80).map { index in
            bounds.contains(CGPoint(x: Double(index % 120) + 0.5, y: Double(index / 120) + 0.5)) ? UInt8(255) : 0
        }
        let provider = try #require(CGDataProvider(data: Data(pixels) as CFData))
        return try #require(CGImage(width: 120, height: 80, bitsPerComponent: 8, bitsPerPixel: 8, bytesPerRow: 120,
                                    space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.none.rawValue),
                                    provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent))
    }
}
