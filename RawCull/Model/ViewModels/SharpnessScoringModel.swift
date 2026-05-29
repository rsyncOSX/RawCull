//
//  SharpnessScoringModel.swift
//  RawCull
//

import Foundation
import Observation
import OSLog

enum SharpnessPhotoType: String, CaseIterable, Codable, Identifiable {
    case auto
    case birdsWildlife
    case portrait
    case landscape
    case generalAction

    var id: String {
        rawValue
    }

    var title: String {
        switch self {
        case .auto: "Auto"
        case .birdsWildlife: "Birds/Wildlife"
        case .portrait: "Portrait"
        case .landscape: "Landscape"
        case .generalAction: "Action"
        }
    }

    nonisolated func applying(to config: FocusDetectorConfig) -> FocusDetectorConfig {
        var c = config
        switch self {
        case .auto:
            return c

        case .birdsWildlife:
            c.preBlurRadius = 2.2
            c.borderInsetFraction = 0.05
            c.salientWeight = 0.85
            c.explicitSalientWeightOverride = 0.85
            c.subjectSizeFactor = 0.05
            c.silhouettePenaltyStrength = 0.55
            c.afRegionRadius = 0.06
            c.enableSubjectClassification = true
            c.isolateMaskToSubject = true

        case .portrait:
            c.preBlurRadius = min(c.preBlurRadius, 1.7)
            c.salientWeight = 0.80
            c.explicitSalientWeightOverride = 0.80
            c.subjectSizeFactor = 0.08
            c.silhouettePenaltyStrength = 0.25
            c.afRegionRadius = 0.10
            c.enableSubjectClassification = true
            c.isolateMaskToSubject = true

        case .landscape:
            c.preBlurRadius = min(c.preBlurRadius, 1.55)
            c.salientWeight = 0.35
            c.explicitSalientWeightOverride = 0.35
            c.subjectSizeFactor = 0.0
            c.silhouettePenaltyStrength = 0.15
            c.afRegionRadius = 0.0
            c.isolateMaskToSubject = false

        case .generalAction:
            c.preBlurRadius = 2.0
            c.salientWeight = 0.65
            c.explicitSalientWeightOverride = 0.65
            c.subjectSizeFactor = 0.05
            c.silhouettePenaltyStrength = 0.40
            c.afRegionRadius = 0.09
            c.enableSubjectClassification = true
            c.isolateMaskToSubject = true
        }
        return c
    }
}

enum SharpnessScoringQuality: String, CaseIterable, Codable, Identifiable {
    case fast
    case balanced
    case highPrecision

    var id: String {
        rawValue
    }

    var title: String {
        switch self {
        case .fast: "Fast"
        case .balanced: "Balanced"
        case .highPrecision: "High Precision"
        }
    }

    var minimumThumbnailMaxPixelSize: Int {
        switch self {
        case .fast: 512
        case .balanced: 768
        case .highPrecision: 1024
        }
    }

    var maxConcurrentScoringTasks: Int {
        switch self {
        case .fast: 6
        case .balanced: 4
        case .highPrecision: 3
        }
    }

    nonisolated func applying(to config: FocusDetectorConfig) -> FocusDetectorConfig {
        var c = config
        switch self {
        case .fast:
            c.fineDetailBlendWeight = 0.0

        case .balanced:
            c.fineDetailBlendWeight = max(c.fineDetailBlendWeight, 0.25)

        case .highPrecision:
            c.fineDetailBlendWeight = max(c.fineDetailBlendWeight, 0.45)
            c.enableSubjectClassification = true
        }
        return c
    }
}

enum SharpnessScoringSource: String, CaseIterable, Codable, Identifiable {
    case embeddedPreview
    case rawDemosaic

    var id: String {
        rawValue
    }

    var title: String {
        switch self {
        case .embeddedPreview: "Embedded Preview"
        case .rawDemosaic: "RAW Demosaic"
        }
    }

    var help: String {
        switch self {
        case .embeddedPreview:
            "Scores Sony's embedded camera JPEG preview. Fast and suitable for normal culling."

        case .rawDemosaic:
            "Scores a CIRAWFilter demosaiced image. Much slower, but useful for final precision checks."
        }
    }
}

enum SharpnessScoringSizeOption: Int, CaseIterable, Identifiable {
    case px1024 = 1024
    case px1536 = 1536
    case px2048 = 2048

    static let highPrecisionDefaultPixelSize = SharpnessScoringSizeOption.px2048.rawValue

    var id: Int {
        rawValue
    }

    var title: String {
        switch self {
        case .px1024: "1024 px"
        case .px1536: "1536 px"
        case .px2048: "2048 px"
        }
    }

    static func normalizedPixelSize(_ value: Int, for quality: SharpnessScoringQuality) -> Int {
        if quality == .highPrecision, value <= 0 {
            return highPrecisionDefaultPixelSize
        }
        return max(value, quality.minimumThumbnailMaxPixelSize)
    }
}

@Observable @MainActor
final class SharpnessScoringModel {
    typealias SharpnessScoreComputer = @Sendable (
        URL,
        FocusDetectorConfig,
        Int,
        CGPoint?,
    ) async -> (score: Float?, saliency: SaliencyInfo?, breakdown: SharpnessBreakdown?)

    /// Sharpness scores keyed by FileItem.id. Wholesale-replaced at the end
    /// of a scoring run; incremental inserts happen only when loading
    /// persisted scores. `didSet` refreshes `maxScore` so read sites in view
    /// bodies are O(1) instead of re-sorting the full score set per cell.
    var scores: [UUID: Float] = [:] {
        didSet { recomputeMaxScore() }
    }

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
            maxScore = scores.values.first ?? 1.0
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
    @ObservationIgnored private let scoreComputerOverride: SharpnessScoreComputer?
    var isCalibratingSharpnessScoring: Bool = false

    private static let minimumSamplesBeforeEstimation = 10
    private static let estimationWindowSize = 10

    init(scoreComputerOverride: SharpnessScoreComputer? = nil) {
        self.scoreComputerOverride = scoreComputerOverride
        // Default mode for wildlife
        focusMaskModel.config = .birdsInFlight
    }

    var effectiveFocusConfig: FocusDetectorConfig {
        scoringQuality.applying(to: photoType.applying(to: focusMaskModel.config))
    }

    var effectiveThumbnailMaxPixelSize: Int {
        SharpnessScoringSizeOption.normalizedPixelSize(thumbnailMaxPixelSize, for: scoringQuality)
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
        sortBySharpness = false
    }

    func calibrateFromBurst(_ files: [FileItem]) async {
        isCalibratingSharpnessScoring = true
        let fileEntries = files.map { (url: $0.url, iso: $0.exifData?.isoValue) }
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

        Logger.process.debugMessageOnly("SharpnessScoringModel: calibration applied — threshold: \(result.threshold), gain: \(result.energyMultiplier), n=\(result.sampleCount)")
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

        let engine = FocusMaskEngine()
        let config = effectiveFocusConfig
        let thumbSize = effectiveThumbnailMaxPixelSize
        let scoringSource = scoringSource
        let scoreComputerOverride = scoreComputerOverride
        var iterator = files.makeIterator()
        var active = 0
        let maxConcurrent = effectiveMaxConcurrentScoringTasks

        let workTask = Task {
            defer {
                self._scoringTask = nil
                self.isScoring = false
            }

            await withTaskGroup(of: (UUID, Float?, SaliencyInfo?, SharpnessBreakdown?).self) { group in
                while active < maxConcurrent, let file = iterator.next() {
                    let url = file.url
                    let id = file.id
                    let iso = file.exifData?.isoValue ?? 400
                    let afPoint = file.afFocusNormalized
                    let hint = FocusDetectorConfig.ApertureHint.from(aperture: file.exifData?.apertureValue)

                    group.addTask(priority: .userInitiated) {
                        var fileConfig = config
                        fileConfig.iso = iso
                        fileConfig.apertureHint = hint
                        let result = if let scoreComputerOverride {
                            await scoreComputerOverride(url, fileConfig, thumbSize, afPoint)
                        } else {
                            await engine.computeSharpnessScore(
                                fromRawURL: url,
                                config: fileConfig,
                                thumbnailMaxPixelSize: thumbSize,
                                afPoint: afPoint,
                                scoringSource: scoringSource,
                            )
                        }
                        return (id, result.score, result.saliency, result.breakdown)
                    }
                    active += 1
                }

                var localScores: [UUID: Float] = [:]
                var localSaliency: [UUID: SaliencyInfo] = [:]
                var localBreakdowns: [UUID: SharpnessBreakdown] = [:]
                var completedCount = 0
                var completionTimes: [TimeInterval] = []
                var lastCompletionTime: Date?

                for await (id, score, saliency, breakdown) in group {
                    active -= 1
                    guard !Task.isCancelled else { break }

                    if let score { localScores[id] = score }
                    if let saliency { localSaliency[id] = saliency }
                    if let breakdown { localBreakdowns[id] = breakdown }
                    completedCount += 1

                    self.scoringProgress = completedCount
                    let now = Date()
                    if let lastCompletionTime {
                        completionTimes.append(now.timeIntervalSince(lastCompletionTime))
                    }
                    lastCompletionTime = now

                    if completedCount >= Self.minimumSamplesBeforeEstimation, !completionTimes.isEmpty {
                        let recentTimes = completionTimes.suffix(min(Self.estimationWindowSize, completionTimes.count))
                        let avgSecondsPerCompletion = recentTimes.reduce(0, +) / Double(recentTimes.count)
                        let remainingItems = files.count - completedCount
                        self.scoringEstimatedSeconds = Swift.max(0, Int(avgSecondsPerCompletion * Double(remainingItems)))
                    }

                    if let file = iterator.next() {
                        let url = file.url
                        let id = file.id
                        let iso = file.exifData?.isoValue ?? 400
                        let afPoint = file.afFocusNormalized
                        let hint = FocusDetectorConfig.ApertureHint.from(aperture: file.exifData?.apertureValue)

                        group.addTask(priority: .userInitiated) {
                            var fileConfig = config
                            fileConfig.iso = iso
                            fileConfig.apertureHint = hint
                            let result = if let scoreComputerOverride {
                                await scoreComputerOverride(url, fileConfig, thumbSize, afPoint)
                            } else {
                                await engine.computeSharpnessScore(
                                    fromRawURL: url,
                                    config: fileConfig,
                                    thumbnailMaxPixelSize: thumbSize,
                                    afPoint: afPoint,
                                    scoringSource: scoringSource,
                                )
                            }
                            return (id, result.score, result.saliency, result.breakdown)
                        }
                        active += 1
                    }
                }

                guard !Task.isCancelled else { return }
                self.scores = localScores
                self.saliencyInfo = localSaliency
                self.breakdowns = localBreakdowns
            }

            guard !Task.isCancelled else { return }

            self.sortBySharpness = true
            self.scoringProgress = 0
            self.scoringTotal = 0
            self.scoringEstimatedSeconds = 0
        }

        _scoringTask = workTask
        await workTask.value
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
