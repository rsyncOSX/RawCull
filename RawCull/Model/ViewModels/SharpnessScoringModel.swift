//
//  SharpnessScoringModel.swift
//  RawCull
//

import Foundation
import Observation
import OSLog

// MARK: - ApertureFilter

/// Restricts the catalog view to images shot within a specific aperture range.
/// Photographers typically use wide apertures for wildlife/portraits and
/// stopped-down apertures for landscapes — filtering by style lets them
/// score and cull each session type without mixing them.
enum ApertureFilter: String, CaseIterable, Identifiable {
    case all = "All"
    case wide = "Wide (≤ f/5.6)" // birds, wildlife, portraits
    case landscape = "Landscape (≥ f/8)" // tripod, landscape, architecture

    var id: String {
        rawValue
    }

    func matches(_ file: FileItem) -> Bool {
        switch self {
        case .all:
            true

        case .wide:
            // Exclude files with missing EXIF rather than accidentally including them.
            file.exifData?.apertureValue.map { $0 <= 5.6 } ?? false

        case .landscape:
            file.exifData?.apertureValue.map { $0 >= 8.0 } ?? false
        }
    }
}

// MARK: - SharpnessScoringModel

/// Owns all sharpness-scoring state and the shared FocusMaskModel whose config
/// sliders feed into both the zoom overlay and the scoring pipeline.
@Observable @MainActor
final class SharpnessScoringModel {
    /// Scored sharpness for each FileItem by UUID.
    var scores: [UUID: Float] = [:]

    /// Saliency result for each FileItem by UUID. Populated alongside scoring.
    var saliencyInfo: [UUID: SaliencyInfo] = [:]

    /// True while batch scoring is running.
    var isScoring: Bool = false

    /// When true the caller should sort filteredFiles sharpest-first.
    var sortBySharpness: Bool = false

    /// Active aperture filter — changing this triggers a re-sort in the ViewModel.
    var apertureFilter: ApertureFilter = .all

    /// Shared config for both the Focus Mask overlay and the scoring pipeline.
    var focusMaskModel = FocusMaskModel()

    /// Thumbnail pixel size used when decoding images for sharpness scoring.
    /// Larger values are more accurate but slower (~3–4× per step).
    var thumbnailMaxPixelSize: Int = 512

    /// Number of images scored so far in the current batch.
    var scoringProgress: Int = 0

    /// Total number of images in the current batch.
    var scoringTotal: Int = 0

    /// Rough ETA in seconds to completion, updated after each image.
    var scoringEstimatedSeconds: Int = 0

    /// p90 of all scores — used as the "100%" anchor for badge normalisation.
    /// Using p90 rather than max prevents a single noise spike from making
    /// every other image render as near-zero stars.
    var maxScore: Float {
        guard scores.count >= 2 else { return scores.values.first ?? 1.0 }
        var sorted = Array(scores.values)
        sorted.sort()
        let k = Int(Float(sorted.count - 1) * 0.90)
        return max(sorted[k], 1e-6)
    }

    /// The running batch task — retained so it can be cancelled externally.
    private var _scoringTask: Task<Void, Never>?

    /// Calibrate
    var calibratingsharpnessscoring: Bool = false

    // MARK: - Lifecycle

    /// Called when a new catalog is opened to discard stale data.
    func reset() {
        scores = [:]
        saliencyInfo = [:]
        sortBySharpness = false
        apertureFilter = .all
        scoringProgress = 0
        scoringTotal = 0
        scoringEstimatedSeconds = 0
    }

    // MARK: - Cancellation

    /// Aborts any in-progress batch score and clears all results.
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
    }

    // MARK: - Calibration

    /// Auto-calibrates `focusMaskModel.config` from a burst and logs the result.
    /// Applies threshold + gain directly; call before `scoreFiles(_:)` for best results.
    func calibrateFromBurst(_ files: [FileItem]) async {
        // Starte calibrate
        calibratingsharpnessscoring = true
        let fileEntries = files.map { (url: $0.url, iso: $0.exifData?.isoValue) }
        guard let result = await focusMaskModel.calibrateAndApplyFromBurstParallel(
            files: fileEntries,
            thumbnailMaxPixelSize: thumbnailMaxPixelSize,
            minSamples: 5,
            maxConcurrentTasks: 8,
        ) else {
            Logger.process.warning("SharpnessScoringModel: calibration failed (too few scoreable images)")
            calibratingsharpnessscoring = false
            return
        }
        Logger.process.debugMessageOnly("SharpnessScoringModel: calibration applied — threshold: \(result.threshold), gain: \(result.energyMultiplier), n=\(result.sampleCount)")
        Logger.process.debugMessageOnly("  p50: \(result.p50)  p90: \(result.p90)  p95: \(result.p95)  p99: \(result.p99)")

        calibratingsharpnessscoring = false
    }

    // MARK: - Batch Scoring

    /// Batch-scores all files with bounded concurrency (max 6 simultaneous
    /// thumbnail decodes). Updates `scoringProgress` and `scoringEstimatedSeconds`
    /// after each result. Supports cooperative cancellation via `cancelScoring()`.
    func scoreFiles(_ files: [FileItem]) async {
        guard !isScoring, !files.isEmpty else { return }
        isScoring = true
        scoringProgress = 0
        scoringTotal = files.count
        scoringEstimatedSeconds = 0
        scores = [:]
        saliencyInfo = [:]

        let model = focusMaskModel
        let config = focusMaskModel.config
        let thumbSize = thumbnailMaxPixelSize
        let startTime = Date()
        var iterator = files.makeIterator()
        var active = 0
        let maxConcurrent = 6

        // Wrap withTaskGroup in an unstructured Task so we can cancel it via
        // _scoringTask while scoreFiles is suspended at `await workTask.value`.
        let workTask = Task {
            await withTaskGroup(of: (UUID, Float?, SaliencyInfo?).self) { group in
                // Seed the first batch
                while active < maxConcurrent, let file = iterator.next() {
                    let url = file.url
                    let id = file.id
                    let iso = file.exifData?.isoValue ?? 400
                    group.addTask(priority: .userInitiated) {
                        var fileConfig = config
                        fileConfig.iso = iso
                        let result = await model.computeSharpnessScore(fromRawURL: url, config: fileConfig, thumbnailMaxPixelSize: thumbSize)
                        return (id, result.score, result.saliency)
                    }
                    active += 1
                }
                // Accumulate locally; assign to @Observable state once at the end
                // so the UI only pays one observer notification for the entire run.
                var localScores: [UUID: Float] = [:]
                var localSaliency: [UUID: SaliencyInfo] = [:]
                var completedCount = 0

                // Drain results, replenish slots, update progress
                for await (id, score, saliency) in group {
                    active -= 1
                    // Cancellation check before mutating state
                    guard !Task.isCancelled else { break }
                    if let score { localScores[id] = score }
                    if let saliency { localSaliency[id] = saliency }
                    completedCount += 1

                    // Progress and ETA are cheap scalars — update every image.
                    self.scoringProgress = completedCount
                    let elapsed = Date().timeIntervalSince(startTime)
                    if completedCount > 0, elapsed > 0 {
                        let rate = Double(completedCount) / elapsed
                        self.scoringEstimatedSeconds = max(0, Int(Double(files.count - completedCount) / rate))
                    }
                    if let file = iterator.next() {
                        let url = file.url
                        let id = file.id
                        let iso = file.exifData?.isoValue ?? 400
                        group.addTask(priority: .userInitiated) {
                            var fileConfig = config
                            fileConfig.iso = iso
                            let result = await model.computeSharpnessScore(fromRawURL: url, config: fileConfig, thumbnailMaxPixelSize: thumbSize)
                            return (id, result.score, result.saliency)
                        }
                        active += 1
                    }
                }

                // Single assignment — one observer notification for the whole run.
                self.scores = localScores
                self.saliencyInfo = localSaliency
            }
        }

        _scoringTask = workTask
        await workTask.value

        // cancelScoring() sets isScoring = false before we get here — bail out
        // without overwriting the cleared state.
        _scoringTask = nil
        guard isScoring else { return }

        isScoring = false
        sortBySharpness = true
        scoringProgress = 0
        scoringTotal = 0
        scoringEstimatedSeconds = 0
    }
}
