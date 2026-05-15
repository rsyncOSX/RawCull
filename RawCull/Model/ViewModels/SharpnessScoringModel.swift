//
//  SharpnessScoringModel.swift
//  RawCull
//

import Foundation
import Observation
import OSLog

enum ApertureFilter: String, CaseIterable, Identifiable {
    case all = "All"
    case wide = "Wide (≤ f/5.6)"
    case landscape = "Landscape (≥ f/8)"

    var id: String {
        rawValue
    }

    func matches(_ file: FileItem) -> Bool {
        switch self {
        case .all:
            true

        case .wide:
            file.exifData?.apertureValue.map { $0 <= 5.6 } ?? false

        case .landscape:
            file.exifData?.apertureValue.map { $0 >= 8.0 } ?? false
        }
    }
}

@Observable @MainActor
final class SharpnessScoringModel {
    typealias SharpnessScoreComputer = @Sendable (
        URL,
        FocusDetectorConfig,
        Int,
        CGPoint?,
    ) async -> (score: Float?, saliency: SaliencyInfo?)

    /// Sharpness scores keyed by FileItem.id. Wholesale-replaced at the end
    /// of a scoring run; incremental inserts happen only when loading
    /// persisted scores. `didSet` refreshes `maxScore` so read sites in view
    /// bodies are O(1) instead of re-sorting the full score set per cell.
    var scores: [UUID: Float] = [:] {
        didSet { recomputeMaxScore() }
    }

    var saliencyInfo: [UUID: SaliencyInfo] = [:]
    var isScoring: Bool = false
    var sortBySharpness: Bool = false
    var apertureFilter: ApertureFilter = .all
    var saliencyCategoryFilter: String?

    var availableSaliencyCategories: [String] {
        Array(Set(saliencyInfo.values.compactMap(\.subjectLabel))).sorted()
    }

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

    func reset() {
        cancelScoring()
        apertureFilter = .all
        saliencyCategoryFilter = nil
    }

    func cancelScoring() {
        _scoringTask?.cancel()
        _scoringTask = nil
        isScoring = false
        scores = [:]
        saliencyInfo = [:]
        scoringProgress = 0
        scoringTotal = 0
        scoringEstimatedSeconds = 0
        sortBySharpness = false
        saliencyCategoryFilter = nil
    }

    func calibrateFromBurst(_ files: [FileItem]) async {
        isCalibratingSharpnessScoring = true
        let fileEntries = files.map { (url: $0.url, iso: $0.exifData?.isoValue) }

        guard let result = await focusMaskModel.calibrateAndApplyFromBurstParallel(
            files: fileEntries,
            thumbnailMaxPixelSize: thumbnailMaxPixelSize,
            minSamples: 5,
            maxConcurrentTasks: 8,
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

        let engine = FocusMaskEngine()
        let config = focusMaskModel.config
        let thumbSize = thumbnailMaxPixelSize
        let scoreComputerOverride = scoreComputerOverride
        var iterator = files.makeIterator()
        var active = 0
        let maxConcurrent = 6

        let workTask = Task {
            defer {
                self._scoringTask = nil
                self.isScoring = false
            }

            await withTaskGroup(of: (UUID, Float?, SaliencyInfo?).self) { group in
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
                            )
                        }
                        return (id, result.score, result.saliency)
                    }
                    active += 1
                }

                var localScores: [UUID: Float] = [:]
                var localSaliency: [UUID: SaliencyInfo] = [:]
                var completedCount = 0
                var completionTimes: [TimeInterval] = []
                var lastCompletionTime: Date?

                for await (id, score, saliency) in group {
                    active -= 1
                    guard !Task.isCancelled else { break }

                    if let score { localScores[id] = score }
                    if let saliency { localSaliency[id] = saliency }
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
                                )
                            }
                            return (id, result.score, result.saliency)
                        }
                        active += 1
                    }
                }

                guard !Task.isCancelled else { return }
                self.scores = localScores
                self.saliencyInfo = localSaliency
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

        sortBySharpness = !scores.isEmpty
        scoringProgress = 0
        scoringTotal = 0
        scoringEstimatedSeconds = 0
    }
}
