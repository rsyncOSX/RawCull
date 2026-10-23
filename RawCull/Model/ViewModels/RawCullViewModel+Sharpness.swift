//
//  RawCullViewModel+Sharpness.swift
//  RawCull
//

import Foundation
import OSLog
import RawCullCore

extension RawCullViewModel {
    /// Applies the current catalog ordering and, when sharpness sorting has
    /// just been enabled, focuses the visible image with strongest AF-center detail. Selecting the
    /// first sorted image also lets thumbnail views reset their scroll position
    /// through their existing selection observers, matching similarity sorting.
    func handleSharpnessSortingChange(isEnabled: Bool) async {
        await handleSortOrderChange()
        guard isEnabled,
              sharpnessModel.sortBySharpness,
              let sharpestFile = filteredFiles.first
        else { return }
        selectedFileID = sharpestFile.id
    }

    var sharpnessScoringTargetFiles: [FileItem] {
        let active = activeCatalogFiles

        if !selectedFileIDs.isEmpty {
            let visibleSelected = filteredFiles.filter { selectedFileIDs.contains($0.id) }
            let visibleIDs = Set(visibleSelected.map(\.id))
            let hiddenSelected = active.filter {
                selectedFileIDs.contains($0.id) && !visibleIDs.contains($0.id)
            }.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
            return visibleSelected + hiddenSelected
        }

        if case let .stars(rating) = ratingFilter {
            if !filteredFiles.isEmpty {
                return filteredFiles.filter { self.rating(for: $0) == rating }
            }
            return active.filter { self.rating(for: $0) == rating }
                .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        }

        return active.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    /// Presentation needs membership and count, never the scoring execution order.
    var sharpnessScoringTargetCount: Int {
        let selectedIDs = selectedFileIDs
        if !selectedIDs.isEmpty {
            let visibleSelected = filteredFiles.filter { selectedIDs.contains($0.id) }
            let visibleIDs = Set(visibleSelected.map(\.id))
            return visibleSelected.count + activeCatalogFiles.count {
                selectedIDs.contains($0.id) && !visibleIDs.contains($0.id)
            }
        }
        if case let .stars(rating) = ratingFilter {
            let candidates = filteredFiles.isEmpty ? activeCatalogFiles : filteredFiles
            let ratings = ratingCache
            return candidates.count { ratings[$0.name] == rating }
        }
        return activeCatalogFiles.count
    }

    var sharpnessScoringTargetDescription: String {
        let count = sharpnessScoringTargetCount
        let fileLabel = count == 1 ? "file" : "files"

        if !selectedFileIDs.isEmpty {
            return "\(count) selected \(fileLabel)"
        }

        if case let .stars(rating) = ratingFilter {
            return "\(count) \(rating)-star \(fileLabel)"
        }

        if hasActiveSemanticSearchSelection {
            return "\(count) semantic-search \(fileLabel)"
        }

        return "\(count) catalog \(fileLabel)"
    }

    /// Auto-calibrates focus config from the current catalog, then scores and re-sorts.
    /// After a successful (non-cancelled) run, scores and saliency are persisted to SavedFiles.
    func calibrateAndScoreCurrentCatalog() async {
        Logger.process.debugMessageOnly(
            "RawCullViewModel.calibrateAndScoreCurrentCatalog(): starting catalog sharpness scoring",
        )
        await calibrateAndScoreFiles(sharpnessScoringTargetFiles)
    }

    /// Application-side effects requested after coordinator-owned burst
    /// sharpness work completes. Culling persistence and display sorting remain
    /// view-model responsibilities.
    func applyBurstSharpnessScoringSideEffects(_ files: [FileItem]) async {
        if !sharpnessModel.scores.isEmpty {
            persistScoringResultsInMemory(files: files)
        }
        await handleSortOrderChange()
    }

    private func calibrateAndScoreFiles(_ files: [FileItem]) async {
        Logger.process.debugMessageOnly(
            "RawCullViewModel.calibrateAndScoreFiles(): starting calibration and scoring for \(files.count) files",
        )
        let shouldContinue = await sharpnessModel.calibrateFromBurst(files)
        guard shouldContinue, !Task.isCancelled else { return }
        await sharpnessModel.scoreFiles(files)
        // scores is cleared at the start of scoreFiles and only written on clean completion —
        // an empty dict means the run was cancelled, so skip the write.
        if !sharpnessModel.scores.isEmpty {
            persistScoringResultsInMemory(files: files)
        }
        await handleSortOrderChange()
        Logger.process.debugMessageOnly(
            "RawCullViewModel.calibrateAndScoreFiles(): finished with \(sharpnessModel.scores.count) scores",
        )
    }

    // periphery:ignore
    /// Merges current sharpness scores and saliency labels into cullingModel.savedFiles
    /// and lets the culling store coalesce persistence with other culling changes.
    func persistScoringResultsInMemory() {
        persistScoringResultsInMemory(files: files)
    }

    private func persistScoringResultsInMemory(files: [FileItem]) {
        Logger.process.debugMessageOnly(
            "RawCullViewModel.persistScoringResultsInMemory(): persisting scores for \(files.count) files",
        )
        guard let catalog = selectedSource?.url else { return }
        let scores = sharpnessModel.scores
        let saliency = sharpnessModel.saliencyInfo
        let signature = sharpnessModel.scoringSignature

        let results = files.compactMap { file -> CullingScoringResult? in
            guard let score = scores[file.id] else { return nil }
            return CullingScoringResult(
                fileName: file.name,
                score: score,
                saliencySubject: saliency[file.id]?.subjectLabel,
                scoringSignature: signature,
                fileSize: file.size,
                modificationDate: file.dateModified,
                afPointScore: sharpnessModel.afPointScores[file.id],
            )
        }
        cullingModel.mergeScoringResults(results, in: catalog)
    }

    func loadPersistedScoringandSaliency() {
        let records = cullingModel.savedFiles.first { $0.catalog == selectedSource?.url }?.filerecords ?? []
        // Keep the first legacy duplicate, matching the previous first(where:) policy.
        let recordsByName = Dictionary(records.compactMap { record in
            record.fileName.map { ($0, record) }
        }, uniquingKeysWith: { first, _ in first })
        let signature = sharpnessModel.scoringSignature
        var scores: [UUID: Float] = [:]
        var afScores: [UUID: Float] = [:]
        var saliency: [UUID: SaliencyInfo] = [:]
        for file in files {
            guard let record = recordsByName[file.name],
                  record.sharpnessScoringSignature == signature,
                  record.sharpnessFileSize == file.size,
                  record.sharpnessModificationDate.map({ abs($0.timeIntervalSince(file.dateModified)) < 0.001 }) == true
            else { continue }
            if let score = record.sharpnessScore, score.isFinite {
                scores[file.id] = score
            }
            if let score = record.afPointSharpnessScore,
               SharpnessScoringModel.hasValidAFPoint(file.afFocusNormalized), score.isFinite, score > 1e-6 {
                afScores[file.id] = score
            }
            if let subject = record.saliencySubject {
                saliency[file.id] = SaliencyInfo(subjectLabel: subject)
            }
        }
        // One publication computes normalization once, rather than sorting after
        // every insertion. Empty results also remove stale restored evidence.
        sharpnessModel.scores = scores
        sharpnessModel.afPointScores = afScores
        sharpnessModel.saliencyInfo = saliency
    }
}
