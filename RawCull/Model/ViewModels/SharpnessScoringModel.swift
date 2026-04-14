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
    var scores: [UUID: Float] = [:]
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

    var maxScore: Float {
        guard scores.count >= 2 else { return scores.values.first ?? 1.0 }
        var sorted = Array(scores.values)
        sorted.sort()
        guard sorted.count >= 10 else { return max(sorted.last ?? 1e-6, 1e-6) }
        let k = Int(Float(sorted.count - 1) * 0.90)
        return max(sorted[k], 1e-6)
    }

    private var _scoringTask: Task<Void, Never>?
    var isCalibratingSharpnessScoring: Bool = false

    init() {
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
        guard !isScoring, !files.isEmpty else { return }
        isScoring = true
        defer { isScoring = false }

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

        let workTask = Task {
            await withTaskGroup(of: (UUID, Float?, SaliencyInfo?).self) { group in
                while active < maxConcurrent, let file = iterator.next() {
                    let url = file.url
                    let id = file.id
                    let iso = file.exifData?.isoValue ?? 400
                    let afPoint = file.afFocusNormalized

                    group.addTask(priority: .userInitiated) {
                        var fileConfig = config
                        fileConfig.iso = iso
                        let result = await model.computeSharpnessScore(
                            fromRawURL: url,
                            config: fileConfig,
                            thumbnailMaxPixelSize: thumbSize,
                            afPoint: afPoint,
                        )
                        return (id, result.score, result.saliency)
                    }
                    active += 1
                }

                var localScores: [UUID: Float] = [:]
                var localSaliency: [UUID: SaliencyInfo] = [:]
                var completedCount = 0

                for await (id, score, saliency) in group {
                    active -= 1
                    guard !Task.isCancelled else { break }

                    if let score { localScores[id] = score }
                    if let saliency { localSaliency[id] = saliency }
                    completedCount += 1

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
                        let afPoint = file.afFocusNormalized

                        group.addTask(priority: .userInitiated) {
                            var fileConfig = config
                            fileConfig.iso = iso
                            let result = await model.computeSharpnessScore(
                                fromRawURL: url,
                                config: fileConfig,
                                thumbnailMaxPixelSize: thumbSize,
                                afPoint: afPoint,
                            )
                            return (id, result.score, result.saliency)
                        }
                        active += 1
                    }
                }

                guard !Task.isCancelled else { return }
                self.scores = localScores
                self.saliencyInfo = localSaliency
            }
        }

        _scoringTask = workTask
        await workTask.value
        _scoringTask = nil
        guard !workTask.isCancelled else { return }

        sortBySharpness = true
        scoringProgress = 0
        scoringTotal = 0
        scoringEstimatedSeconds = 0
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
