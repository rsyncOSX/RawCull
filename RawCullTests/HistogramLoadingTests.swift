import AppKit
import CoreGraphics
@testable import RawCull
import Testing

@MainActor
@Suite("Histogram loading")
struct HistogramLoadingTests {
    @Test(.tags(.smoke))
    func `nil image clears published bins`() async throws {
        let model = HistogramPresentationModel()
        let image = try #require(makeImage())

        await model.load(image: image) { _ in [0.25, 0.75] }
        #expect(model.normalizedBins == [0.25, 0.75])

        await model.load(image: nil)
        #expect(model.normalizedBins.isEmpty)
    }

    @Test(.tags(.smoke))
    func `image conversion failure clears published bins`() async throws {
        let model = HistogramPresentationModel()
        let image = try #require(makeImage())

        await model.load(image: image) { _ in [1] }
        #expect(model.normalizedBins == [1])

        await model.load(image: NSImage(size: NSSize(width: 1, height: 1)))
        #expect(model.normalizedBins.isEmpty)
    }

    @Test(.tags(.smoke))
    func `successful calculation publishes normalized bins`() async throws {
        let model = HistogramPresentationModel()
        let image = try #require(makeImage())

        await model.load(image: image) { _ in [0, 0.5, 1] }

        #expect(model.normalizedBins == [0, 0.5, 1])
    }

    @Test(.tags(.smoke))
    func `bounds histogram sample while preserving aspect ratio`() throws {
        let image = try makeSplitCGImage(width: 1024, height: 512)

        let sampledImage = HistogramLoader.sampledImage(from: image)

        #expect(sampledImage.width == HistogramLoader.maximumSampleDimension)
        #expect(sampledImage.height == HistogramLoader.maximumSampleDimension / 2)
    }

    @Test(.tags(.smoke))
    func `sampled histogram preserves dominant luminance values`() async throws {
        let image = try makeSplitCGImage(width: 1024, height: 512)

        let histogram = try await HistogramLoader.calculate(from: image)

        #expect(histogram.count == 256)
        #expect(histogram[0] == 1)
        #expect(histogram[255] == 1)
        #expect(histogram[1 ..< 255].allSatisfy { $0 == 0 })
    }

    @Test(.tags(.smoke))
    func `slow cancelled image cannot overwrite fast replacement`() async throws {
        let model = HistogramPresentationModel()
        let slowImage = try #require(makeImage(red: 0))
        let fastImage = try #require(makeImage(red: 255))
        let gate = HistogramCalculationGate()

        let slowTask = Task {
            await model.load(image: slowImage) { _ in
                await gate.wait()
                return [0.1]
            }
        }
        await gate.waitUntilStarted()

        slowTask.cancel()
        await model.load(image: fastImage) { _ in [0.9] }
        await gate.release()
        await slowTask.value

        #expect(model.normalizedBins == [0.9])
    }

    private func makeImage(red: UInt8 = 127) -> NSImage? {
        let colorSpace = CGColorSpace(name: CGColorSpace.sRGB)
        let context = CGContext(
            data: nil,
            width: 2,
            height: 2,
            bitsPerComponent: 8,
            bytesPerRow: 8,
            space: colorSpace ?? CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue,
        )
        context?.setFillColor(
            red: CGFloat(red) / 255,
            green: 0,
            blue: 0,
            alpha: 1,
        )
        context?.fill(CGRect(x: 0, y: 0, width: 2, height: 2))
        guard let cgImage = context?.makeImage() else { return nil }
        return NSImage(cgImage: cgImage, size: NSSize(width: 2, height: 2))
    }

    private func makeSplitCGImage(width: Int, height: Int) throws -> CGImage {
        let context = try #require(CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGBitmapInfo.byteOrder32Big.rawValue
                | CGImageAlphaInfo.premultipliedLast.rawValue,
        ))
        context.setFillColor(CGColor(gray: 0, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width / 2, height: height))
        context.setFillColor(CGColor(gray: 1, alpha: 1))
        context.fill(CGRect(x: width / 2, y: 0, width: width / 2, height: height))
        return try #require(context.makeImage())
    }
}

private actor HistogramCalculationGate {
    private var isStarted = false
    private var startWaiters: [CheckedContinuation<Void, Never>] = []
    private var releaseContinuation: CheckedContinuation<Void, Never>?

    func wait() async {
        isStarted = true
        let waiters = startWaiters
        startWaiters.removeAll()
        for waiter in waiters {
            waiter.resume()
        }

        await withCheckedContinuation { continuation in
            releaseContinuation = continuation
        }
    }

    func waitUntilStarted() async {
        guard !isStarted else { return }
        await withCheckedContinuation { continuation in
            startWaiters.append(continuation)
        }
    }

    func release() {
        releaseContinuation?.resume()
        releaseContinuation = nil
    }
}
