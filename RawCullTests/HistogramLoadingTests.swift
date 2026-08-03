import AppKit
@testable import RawCull
import Testing

@MainActor
struct HistogramLoadingTests {
    @Test
    func `nil input clears existing bins`() async {
        let loader = HistogramLoadingModel()
        let image = createTestImage()

        _ = await loader.load(
            image: image,
            convert: { $0.cgImage(forProposedRect: nil, context: nil, hints: nil) },
            calculate: { _ in [0.25, 1.0] },
        )
        #expect(loader.normalizedBins == [0.25, 1.0])

        let converted = await loader.load(
            image: nil,
            convert: { _ in Issue.record("nil input must not be converted"); return nil },
            calculate: { _ in Issue.record("nil input must not be calculated"); return [] },
        )

        #expect(!converted)
        #expect(loader.normalizedBins.isEmpty)
    }

    @Test
    func `conversion failure is recoverable and leaves empty bins`() async {
        let loader = HistogramLoadingModel()

        let converted = await loader.load(
            image: createTestImage(),
            convert: { _ in nil },
            calculate: { _ in Issue.record("failed conversion must not be calculated"); return [] },
        )

        #expect(!converted)
        #expect(loader.normalizedBins.isEmpty)
    }

    @Test
    func `valid calculation publishes normalized bins`() async {
        let loader = HistogramLoadingModel()
        let expected: [CGFloat] = [0, 0.5, 1]

        let converted = await loader.load(
            image: createTestImage(),
            convert: { $0.cgImage(forProposedRect: nil, context: nil, hints: nil) },
            calculate: { _ in expected },
        )

        #expect(converted)
        #expect(loader.normalizedBins == expected)
    }

    @Test
    func `superseded slow calculation cannot replace fast result`() async {
        let loader = HistogramLoadingModel()
        let gate = HistogramCalculationGate()
        let slowImage = createTestImage(width: 101, height: 1)
        let fastImage = createTestImage(width: 202, height: 1)
        let converter: HistogramLoadingModel.ImageConverter = {
            $0.cgImage(forProposedRect: nil, context: nil, hints: nil)
        }
        guard let slowWidth = converter(slowImage)?.width,
              let fastWidth = converter(fastImage)?.width
        else {
            Issue.record("test images must convert to CGImage")
            return
        }

        let slowTask = Task {
            await loader.load(
                image: slowImage,
                convert: converter,
                calculate: { image in await gate.calculate(image) },
            )
        }
        await gate.waitUntilStarted(width: slowWidth)

        let fastTask = Task {
            await loader.load(
                image: fastImage,
                convert: converter,
                calculate: { image in await gate.calculate(image) },
            )
        }
        await gate.waitUntilStarted(width: fastWidth)
        await gate.finish(width: fastWidth, bins: [0.2, 1])
        _ = await fastTask.value
        #expect(loader.normalizedBins == [0.2, 1])

        await gate.finish(width: slowWidth, bins: [1, 0.1])
        _ = await slowTask.value
        #expect(loader.normalizedBins == [0.2, 1])
    }
}

private actor HistogramCalculationGate {
    private var calculations: [Int: CheckedContinuation<[CGFloat], Never>] = [:]
    private var startWaiters: [Int: CheckedContinuation<Void, Never>] = [:]

    func calculate(_ image: CGImage) async -> [CGFloat] {
        let width = image.width
        return await withCheckedContinuation { continuation in
            calculations[width] = continuation
            startWaiters.removeValue(forKey: width)?.resume()
        }
    }

    func waitUntilStarted(width: Int) async {
        guard calculations[width] == nil else { return }
        await withCheckedContinuation { continuation in
            startWaiters[width] = continuation
        }
    }

    func finish(width: Int, bins: [CGFloat]) {
        calculations.removeValue(forKey: width)?.resume(returning: bins)
    }
}
