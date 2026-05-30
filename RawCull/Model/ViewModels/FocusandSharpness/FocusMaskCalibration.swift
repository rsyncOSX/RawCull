import Foundation

struct FocusCalibrationResult {
    let threshold: Float
    let energyMultiplier: Float
    let sampleCount: Int
    let p50: Float
    let p90: Float
    let p95: Float
    let p99: Float
}

extension FocusMaskEngine {
    /// Burst-based auto-calibration of `threshold` and `energyMultiplier`.
    ///
    /// Scores every file with `energyMultiplier = 1.0` (unit gain), collects the
    /// resulting raw scores, sorts them, then derives:
    ///
    ///     gain      = clamp(targetP95AfterGain / p95, 0.5, 32.0)
    ///     threshold = min(percentile(scores, thresholdPercentile) · gain, 1.0)
    ///
    /// The idea: after applying `gain`, the 95-th percentile of the catalog lands
    /// at `targetP95AfterGain` (default 0.50), giving consistent mask contrast
    /// across bright/dim or noisy/clean burst sets.  The threshold is placed at
    /// the chosen percentile (default 90-th) of the *post-gain* distribution so
    /// roughly the top 10 % of edges survive the threshold into the focus mask.
    ///
    /// Returns `nil` when fewer than `minSamples` files produced a usable score.
    nonisolated func calibrateFromBurstParallel(
        files: [(url: URL, iso: Int?)],
        baseConfig: FocusDetectorConfig,
        thumbnailMaxPixelSize: Int = 512,
        scoringSource: SharpnessScoringSource = .embeddedPreview,
        thresholdPercentile: Float = 0.90,
        targetP95AfterGain: Float = 0.50,
        minSamples: Int = 5,
        maxConcurrentTasks: Int = 8,
    ) async -> FocusCalibrationResult? {
        guard !files.isEmpty else { return nil }

        let tSize = thumbnailMaxPixelSize
        let concurrency = max(1, min(maxConcurrentTasks, files.count))

        var nextIndex = 0
        var scores = [Float]()
        scores.reserveCapacity(files.count)

        await withTaskGroup(of: Float?.self) { group in
            for _ in 0 ..< concurrency {
                guard nextIndex < files.count else { break }
                let entry = files[nextIndex]
                nextIndex += 1

                group.addTask { [baseConfig, tSize] in
                    var fileConfig = baseConfig
                    fileConfig.energyMultiplier = 1.0
                    fileConfig.iso = entry.iso ?? 400
                    fileConfig.enableSubjectClassification = false
                    let result = await computeSharpnessScore(
                        fromRawURL: entry.url,
                        config: fileConfig,
                        thumbnailMaxPixelSize: tSize,
                        scoringSource: scoringSource,
                    )
                    return result.score
                }
            }

            while let value = await group.next() {
                if let s = value, s.isFinite, s > 0 { scores.append(s) }

                if nextIndex < files.count {
                    let entry = files[nextIndex]
                    nextIndex += 1

                    group.addTask { [baseConfig, tSize] in
                        var fileConfig = baseConfig
                        fileConfig.energyMultiplier = 1.0
                        fileConfig.iso = entry.iso ?? 400
                        fileConfig.enableSubjectClassification = false
                        let result = await computeSharpnessScore(
                            fromRawURL: entry.url,
                            config: fileConfig,
                            thumbnailMaxPixelSize: tSize,
                            scoringSource: scoringSource,
                        )
                        return result.score
                    }
                }
            }
        }

        guard scores.count >= minSamples else { return nil }
        scores.sort()

        @inline(__always)
        func percentile(_ sorted: [Float], _ p: Float) -> Float {
            let clamped = min(max(p, 0), 1)
            let idx = Int((Float(sorted.count - 1) * clamped).rounded(.toNearestOrEven))
            return sorted[idx]
        }

        let p50 = percentile(scores, 0.50)
        let p90 = percentile(scores, 0.90)
        let p95 = percentile(scores, 0.95)
        let p99 = percentile(scores, 0.99)

        let eps: Float = 1e-6
        let rawGain = targetP95AfterGain / max(p95, eps)
        let tunedGain = min(max(rawGain, 0.5), 32.0)
        let tunedThreshold = min(percentile(scores, thresholdPercentile) * tunedGain, 1.0)

        return FocusCalibrationResult(
            threshold: tunedThreshold,
            energyMultiplier: tunedGain,
            sampleCount: scores.count,
            p50: p50,
            p90: p90,
            p95: p95,
            p99: p99,
        )
    }
}
