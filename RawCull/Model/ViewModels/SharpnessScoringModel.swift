//
//  SharpnessScoringModel.swift
//  RawCull
//

import Foundation
import Observation

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
            file.exifData?.apertureValue.map { $0 <= 5.6 } ?? true

        case .landscape:
            file.exifData?.apertureValue.map { $0 >= 8.0 } ?? true
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

    /// True while batch scoring is running.
    var isScoring: Bool = false

    /// When true the caller should sort filteredFiles sharpest-first.
    var sortBySharpness: Bool = false

    /// Active aperture filter — changing this triggers a re-sort in the ViewModel.
    var apertureFilter: ApertureFilter = .all

    /// Shared config for both the Focus Mask overlay and the scoring pipeline.
    var focusMaskModel = FocusMaskModel()

    /// Highest score in the current catalog — used for badge normalisation.
    var maxScore: Float {
        scores.values.max() ?? 1.0
    }

    // MARK: - Lifecycle

    /// Called when a new catalog is opened to discard stale data.
    func reset() {
        scores = [:]
        sortBySharpness = false
        apertureFilter = .all
    }

    // MARK: - Batch Scoring

    /// Batch-scores all files off the main actor with bounded concurrency (max 6
    /// simultaneous thumbnail decodes). Writes results into `scores` and sets
    /// `sortBySharpness = true` on completion.
    func scoreFiles(_ files: [FileItem]) async {
        guard !isScoring, !files.isEmpty else { return }
        isScoring = true
        scores = [:]

        let filesToScore = files // local copy — safe to capture in detached task
        let model = focusMaskModel
        let config = focusMaskModel.config // snapshot on @MainActor before crossing boundary

        let results = await Task.detached(priority: .userInitiated) { [filesToScore, model, config] () -> [UUID: Float] in
            var scored: [UUID: Float] = [:]
            let maxConcurrent = 6
            var iterator = filesToScore.makeIterator()
            var active = 0

            await withTaskGroup(of: (UUID, Float?).self) { group in
                // Seed the first batch
                while active < maxConcurrent, let file = iterator.next() {
                    group.addTask(priority: .userInitiated) {
                        let score = model.computeSharpnessScore(fromRawURL: file.url, config: config)
                        return (file.id, score)
                    }
                    active += 1
                }
                // Drain results and top up as slots free
                for await (id, score) in group {
                    active -= 1
                    if let score { scored[id] = score }
                    if let file = iterator.next() {
                        group.addTask(priority: .userInitiated) {
                            let s = model.computeSharpnessScore(fromRawURL: file.url, config: config)
                            return (file.id, s)
                        }
                        active += 1
                    }
                }
            }
            return scored
        }.value

        scores = results
        isScoring = false
        sortBySharpness = true
    }
}
