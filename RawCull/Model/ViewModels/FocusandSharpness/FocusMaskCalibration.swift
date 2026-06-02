import CoreImage
import Foundation

struct FocusCalibrationResult {
    let threshold: Float
    let sampleCount: Int
    let p50: Float
    let p90: Float
    let p95: Float
    let p99: Float
}

extension FocusMaskEngine {
    /// Calibrates only the visual edge threshold from sampled Laplacian pixel energies.
    /// Core sharpness scores keep a fixed gain and therefore do not depend on catalog contents.
    nonisolated func calibrateFromBurstParallel(
        files: [(url: URL, iso: Int?)],
        baseConfig: FocusDetectorConfig,
        thumbnailMaxPixelSize: Int = 512,
        scoringSource: SharpnessScoringSource = .embeddedPreview,
        thresholdPercentile: Float = 0.90,
        minSamples: Int = 5,
        maxConcurrentTasks: Int = 8,
    ) async -> FocusCalibrationResult? {
        guard !files.isEmpty else { return nil }
        let calibrationPixelSize = thumbnailMaxPixelSize > 0 ? min(thumbnailMaxPixelSize, 512) : 512
        let concurrency = max(1, min(maxConcurrentTasks, files.count))
        let context = self.context
        var nextIndex = 0
        var successfulImages = 0
        var energies = [Float]()

        await withTaskGroup(of: [Float]?.self) { group in
            func enqueue(_ entry: (url: URL, iso: Int?)) {
                group.addTask { [baseConfig, calibrationPixelSize, scoringSource, context] in
                    guard !Task.isCancelled else { return nil }
                    var fileConfig = baseConfig
                    fileConfig.iso = entry.iso ?? 400
                    fileConfig.enableSubjectClassification = false
                    guard let image = Self.decodeScoringImage(
                        at: entry.url,
                        maxPixelSize: calibrationPixelSize,
                        scoringSource: scoringSource,
                        context: context,
                    ), let laplacian = Self.buildAmplifiedLaplacian(
                        from: CIImage(cgImage: image),
                        config: fileConfig,
                    ) else { return nil }
                    guard !Task.isCancelled else { return nil }
                    let samples = Self.redSamples(in: laplacian.extent, from: laplacian, context: context)
                        .filter { $0.isFinite && $0 > 0 }
                    guard !Task.isCancelled else { return nil }
                    let strideBy = max(samples.count / 4096, 1)
                    return Swift.stride(from: 0, to: samples.count, by: strideBy).map { samples[$0] }
                }
            }
            for _ in 0 ..< concurrency where nextIndex < files.count && !Task.isCancelled {
                enqueue(files[nextIndex])
                nextIndex += 1
            }
            while let values = await group.next() {
                guard !Task.isCancelled else {
                    group.cancelAll()
                    break
                }
                if let values, !values.isEmpty {
                    successfulImages += 1
                    energies.append(contentsOf: values)
                }
                if nextIndex < files.count, !Task.isCancelled {
                    enqueue(files[nextIndex])
                    nextIndex += 1
                }
            }
        }

        guard !Task.isCancelled, successfulImages >= minSamples, !energies.isEmpty else { return nil }
        energies.sort()
        func percentile(_ p: Float) -> Float {
            let index = Int((Float(energies.count - 1) * min(max(p, 0), 1)).rounded(.toNearestOrEven))
            return energies[index]
        }
        return FocusCalibrationResult(
            threshold: min(max(percentile(thresholdPercentile), 0.01), 0.95),
            sampleCount: energies.count,
            p50: percentile(0.50),
            p90: percentile(0.90),
            p95: percentile(0.95),
            p99: percentile(0.99),
        )
    }
}
