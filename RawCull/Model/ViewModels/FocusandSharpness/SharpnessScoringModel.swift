//
//  SharpnessScoringModel.swift
//  RawCull
//

import Foundation
import Observation
import OSLog
import RawCullCore

@Observable @MainActor
final class SharpnessScoringModel {
    /// Sharpness scores keyed by FileItem.id. Wholesale-replaced at the end
    /// of a scoring run; incremental inserts happen only when loading
    /// persisted scores. `didSet` refreshes `maxScore` so read sites in view
    /// bodies are O(1) instead of re-sorting the full score set per cell.
    var scores: [UUID: Float] = [:] {
        didSet {
            recomputeMaxScore()
            scoreRevision &+= 1
        }
    }

    private(set) var scoreRevision: Int = 0
    var saliencyInfo: [UUID: SaliencyInfo] = [:]
    var breakdowns: [UUID: SharpnessBreakdown] = [:]
    var isScoring: Bool = false
    var sortBySharpness: Bool = false
    var photoType: SharpnessPhotoType = .auto
    var scoringQuality: SharpnessScoringQuality = .fast
    var scoringSource: SharpnessScoringSource = .embeddedPreview

    var focusMaskModel = FocusMaskModel()
    var thumbnailMaxPixelSize: Int = 512
    var scoringProgress: Int = 0
    var scoringTotal: Int = 0
    var scoringEstimatedSeconds: Int = 0

    /// Normalization denominator for sharpness badges / percentiles. Stored
    /// (not computed) so each ImageItemView read is O(1); recomputed only on
    /// `scores` mutation via `didSet`.
    private(set) var maxScore: Float = 1.0

    /// Normalization denominator used by UI badges:
    ///   n <  2 → the lone score itself (or 1.0 as a safe default)
    ///   n < 10 → the raw max (too few samples for a stable percentile)
    ///   n ≥ 10 → the 90-th percentile, so a single outlier cannot compress
    ///            every other badge toward zero.
    /// 1e-6 floor prevents division-by-zero in the consumers.
    private func recomputeMaxScore() {
        guard scores.count >= 2 else {
            maxScore = max(scores.values.first ?? 1.0, 1e-6)
            return
        }
        var sorted = Array(scores.values)
        sorted.sort()
        guard sorted.count >= 10 else {
            maxScore = max(sorted.last ?? 1e-6, 1e-6)
            return
        }
        let k = Int(Float(sorted.count - 1) * 0.90)
        maxScore = max(sorted[k], 1e-6)
    }

    private var _scoringTask: Task<Void, Never>?
    @ObservationIgnored private nonisolated let analysisAdapter: RawCullPhotoAnalysisAdapter
    private var scoringCompletionTimes = [TimeInterval]()
    private var lastScoringCompletionTime: Date?
    var isCalibratingSharpnessScoring: Bool = false

    private static let minimumSamplesBeforeEstimation = 10
    private static let estimationWindowSize = 10

    init(analysisAdapterOverride: RawCullPhotoAnalysisAdapter? = nil) {
        analysisAdapter = analysisAdapterOverride ?? RawCullPhotoAnalysisAdapter()
        // Default mode for wildlife
        focusMaskModel.config = .birdsInFlight
    }

    var effectiveFocusConfig: FocusDetectorConfig {
        scoringQuality.packageQuality.applying(
            to: photoType.packagePreset.applying(to: focusMaskModel.config),
        )
    }

    var effectiveThumbnailMaxPixelSize: Int {
        SharpnessScoringSizeOption.normalizedPixelSize(thumbnailMaxPixelSize, for: scoringQuality)
    }

    var scoringSignature: SharpnessScoringSignature {
        SharpnessScoringSignature(
            scoringSource: scoringSource,
            thumbnailMaxPixelSize: effectiveThumbnailMaxPixelSize,
            config: effectiveFocusConfig,
        )
    }

    var effectiveMaxConcurrentScoringTasks: Int {
        switch scoringSource {
        case .embeddedPreview:
            scoringQuality.maxConcurrentScoringTasks

        case .rawDemosaic:
            min(2, scoringQuality.maxConcurrentScoringTasks)
        }
    }

    func reset() {
        cancelScoring()
    }

    func cancelScoring() {
        _scoringTask?.cancel()
        _scoringTask = nil
        isScoring = false
        scores = [:]
        saliencyInfo = [:]
        breakdowns = [:]
        scoringProgress = 0
        scoringTotal = 0
        scoringEstimatedSeconds = 0
        scoringCompletionTimes = []
        lastScoringCompletionTime = nil
        sortBySharpness = false
    }

    func calibrateFromBurst(_ files: [FileItem]) async {
        isCalibratingSharpnessScoring = true
        let fileEntries = files.map {
            (
                url: $0.url,
                iso: $0.exifData?.isoValue,
                aperture: $0.exifData?.apertureValue,
            )
        }
        let calibrationConfig = effectiveFocusConfig

        guard let result = await focusMaskModel.calibrateAndApplyFromBurstParallel(
            files: fileEntries,
            baseConfigOverride: calibrationConfig,
            thumbnailMaxPixelSize: effectiveThumbnailMaxPixelSize,
            scoringSource: scoringSource,
            minSamples: 5,
            maxConcurrentTasks: effectiveMaxConcurrentScoringTasks,
        ) else {
            Logger.process.warning("SharpnessScoringModel: calibration failed (too few scoreable images)")
            isCalibratingSharpnessScoring = false
            return
        }

        Logger.process.debugMessageOnly("SharpnessScoringModel: visual calibration applied — threshold: \(result.threshold), pixels=\(result.sampleCount)")
        Logger.process.debugMessageOnly("  p50: \(result.p50)  p90: \(result.p90)  p95: \(result.p95)  p99: \(result.p99)")
        isCalibratingSharpnessScoring = false
    }

    func scoreFiles(_ files: [FileItem]) async {
        guard !files.isEmpty else { return }

        if let existingTask = _scoringTask {
            await existingTask.value
            return
        }

        isScoring = true

        scoringProgress = 0
        scoringTotal = files.count
        scoringEstimatedSeconds = 0
        scores = [:]
        saliencyInfo = [:]
        breakdowns = [:]
        scoringCompletionTimes = []
        lastScoringCompletionTime = nil

        let config = effectiveFocusConfig
        let thumbSize = effectiveThumbnailMaxPixelSize
        let scoringSource = scoringSource
        let maxConcurrent = effectiveMaxConcurrentScoringTasks
        let requests = files.map { file in
            RawCullPhotoAnalysisRequest(
                id: file.id,
                file: RawCullPhotoAnalysisFile(
                    url: file.url,
                    iso: file.exifData?.isoValue ?? 400,
                    aperture: file.exifData?.apertureValue,
                    normalizedAFPoint: file.afFocusNormalized,
                ),
            )
        }

        let workTask = Task {
            defer {
                self._scoringTask = nil
                self.isScoring = false
            }

            guard let results = await analysisAdapter.analyzeBatch(
                requests: requests,
                configuration: config,
                maximumPixelSize: thumbSize,
                source: scoringSource,
                maximumConcurrentTasks: maxConcurrent,
                progress: { completedCount, totalCount in
                    await MainActor.run {
                        self.recordScoringProgress(
                            completedCount: completedCount,
                            totalCount: totalCount,
                        )
                    }
                },
            ), !Task.isCancelled else { return }

            self.scores = Dictionary(
                uniqueKeysWithValues: results.compactMap { result in
                    result.score.map { (result.id, $0) }
                },
            )
            self.saliencyInfo = Dictionary(
                uniqueKeysWithValues: results.compactMap { result in
                    result.saliency.map { (result.id, $0) }
                },
            )
            self.breakdowns = Dictionary(
                uniqueKeysWithValues: results.compactMap { result in
                    result.breakdown.map { (result.id, $0) }
                },
            )

            self.sortBySharpness = true
            self.scoringProgress = 0
            self.scoringTotal = 0
            self.scoringEstimatedSeconds = 0
            self.scoringCompletionTimes = []
            self.lastScoringCompletionTime = nil
        }

        _scoringTask = workTask
        await workTask.value
    }

    private func recordScoringProgress(completedCount: Int, totalCount: Int) {
        scoringProgress = completedCount
        let now = Date()
        if let lastScoringCompletionTime {
            scoringCompletionTimes.append(
                now.timeIntervalSince(lastScoringCompletionTime),
            )
        }
        lastScoringCompletionTime = now

        guard completedCount >= Self.minimumSamplesBeforeEstimation,
              !scoringCompletionTimes.isEmpty
        else { return }

        let recentTimes = scoringCompletionTimes.suffix(
            min(Self.estimationWindowSize, scoringCompletionTimes.count),
        )
        let averageSeconds = recentTimes.reduce(0, +) / Double(recentTimes.count)
        let remainingItems = totalCount - completedCount
        scoringEstimatedSeconds = max(
            0,
            Int(averageSeconds * Double(remainingItems)),
        )
    }

    func applyPreloadedScores(
        _ files: [FileItem],
        preloadedScores: [UUID: Float],
        preloadedSaliency: [UUID: SaliencyInfo],
    ) {
        guard !files.isEmpty else {
            sortBySharpness = false
            scoringProgress = 0
            scoringTotal = 0
            scoringEstimatedSeconds = 0
            return
        }

        cancelScoring()

        isScoring = true
        defer { isScoring = false }

        let validIDs = Set(files.map(\.id))
        scores = preloadedScores.filter { validIDs.contains($0.key) }
        saliencyInfo = preloadedSaliency.filter { validIDs.contains($0.key) }
        breakdowns = [:]

        sortBySharpness = !scores.isEmpty
        scoringProgress = 0
        scoringTotal = 0
        scoringEstimatedSeconds = 0
    }
}
