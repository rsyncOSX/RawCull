import AppKit
import CoreGraphics
import Foundation
@testable import RawCull
import Testing

private func makeCoordinatorTestCGImage(width: Int = 32, height: Int = 24) throws -> CGImage {
    let colorSpace = CGColorSpaceCreateDeviceRGB()
    let context = try #require(CGContext(
        data: nil,
        width: width,
        height: height,
        bitsPerComponent: 8,
        bytesPerRow: 0,
        space: colorSpace,
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue,
    ))
    context.setFillColor(NSColor.red.cgColor)
    context.fill(CGRect(x: 0, y: 0, width: width, height: height))
    return try #require(context.makeImage())
}

private actor ExtractionProbe {
    private var count = 0
    private let image: CGImage

    init(image: CGImage) {
        self.image = image
    }

    func extract() async throws -> CGImage {
        count += 1
        try await Task.sleep(for: .milliseconds(25))
        return image
    }

    func failingExtract() async throws -> CGImage {
        count += 1
        throw ThumbnailError.generationFailed
    }

    func extractionCount() -> Int {
        count
    }
}

struct ThumbnailExtractionCoordinatorTests {
    @Test
    func `concurrent matching requests share one extraction`() async throws {
        let coordinator = ThumbnailExtractionCoordinator()
        let image = try makeCoordinatorTestCGImage(width: 64, height: 48)
        let probe = ExtractionProbe(image: image)
        let key = ThumbnailExtractionCoordinator.Key(
            url: URL(fileURLWithPath: "/tmp/rawcull-shared.ARW"),
            targetSize: 512,
            qualityCost: 4,
        )

        let results = try await withThrowingTaskGroup(of: CGImage.self) { group in
            for _ in 0 ..< 8 {
                group.addTask {
                    try await coordinator.extract(key: key) {
                        try await probe.extract()
                    }
                }
            }

            var images: [CGImage] = []
            for try await result in group {
                images.append(result)
            }
            return images
        }

        #expect(results.count == 8)
        #expect(await probe.extractionCount() == 1)
        #expect(results.allSatisfy { $0.width == 64 && $0.height == 48 })
    }

    @Test
    func `different target sizes are extracted separately`() async throws {
        let coordinator = ThumbnailExtractionCoordinator()
        let image = try makeCoordinatorTestCGImage(width: 64, height: 48)
        let probe = ExtractionProbe(image: image)
        let url = URL(fileURLWithPath: "/tmp/rawcull-size-specific.ARW")
        let smallKey = ThumbnailExtractionCoordinator.Key(url: url, targetSize: 256, qualityCost: 4)
        let largeKey = ThumbnailExtractionCoordinator.Key(url: url, targetSize: 512, qualityCost: 4)

        async let small = coordinator.extract(key: smallKey) {
            try await probe.extract()
        }
        async let large = coordinator.extract(key: largeKey) {
            try await probe.extract()
        }

        _ = try await (small, large)

        #expect(await probe.extractionCount() == 2)
    }

    @Test
    func `failed extraction is removed so later requests retry`() async throws {
        let coordinator = ThumbnailExtractionCoordinator()
        let image = try makeCoordinatorTestCGImage(width: 64, height: 48)
        let probe = ExtractionProbe(image: image)
        let key = ThumbnailExtractionCoordinator.Key(
            url: URL(fileURLWithPath: "/tmp/rawcull-retry.ARW"),
            targetSize: 512,
            qualityCost: 4,
        )

        await #expect(throws: ThumbnailError.generationFailed) {
            try await coordinator.extract(key: key) {
                try await probe.failingExtract()
            }
        }

        let retriedImage = try await coordinator.extract(key: key) {
            try await probe.extract()
        }

        #expect(retriedImage.width == 64)
        #expect(await probe.extractionCount() == 2)
    }
}
