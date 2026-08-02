//
//  RawCullViewModel+Sharpness.swift
//  RawCull
//

import Foundation
import OSLog
import RawCullCore

extension RawCullViewModel {
    var sharpnessScoringTargetFiles: [FileItem] {
        let ordered = activeCatalogFiles.sorted {
            $0.name.localizedStandardCompare($1.name) == .orderedAscending
        }

        if !selectedFileIDs.isEmpty {
            let visibleSelected = filteredFiles.filter { selectedFileIDs.contains($0.id) }
            let visibleIDs = Set(visibleSelected.map(\.id))
            let hiddenSelected = ordered.filter {
                selectedFileIDs.contains($0.id) && !visibleIDs.contains($0.id)
            }
            return visibleSelected + hiddenSelected
        }

        if case let .stars(rating) = ratingFilter {
            let visible = filteredFiles.isEmpty ? ordered : filteredFiles
            return visible.filter { getRating(for: $0) == rating }
        }

        return ordered
    }

    var sharpnessScoringTargetDescription: String {
        let count = sharpnessScoringTargetFiles.count
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

    /// Auto-calibrates and scores only the files participating in burst analysis.
    /// Used by rating- or selection-scoped burst reanalysis to avoid scoring the full catalog.
    func calibrateAndScoreBurstFiles(_ files: [FileItem]) async {
        Logger.process.debugMessageOnly(
            "RawCullViewModel.calibrateAndScoreBurstFiles(): starting sharpness scoring for \(files.count) burst files",
        )
        await calibrateAndScoreFiles(files)
    }

    private func calibrateAndScoreFiles(_ files: [FileItem]) async {
        Logger.process.debugMessageOnly(
            "RawCullViewModel.calibrateAndScoreFiles(): starting calibration and scoring for \(files.count) files",
        )
        await sharpnessModel.calibrateFromBurst(files)
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

    /// Merges current sharpness scores and saliency labels into cullingModel.savedFiles
    /// and lets the culling store coalesce persistence with other culling changes.
    // periphery:ignore
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
            )
        }
        cullingModel.mergeScoringResults(results, in: catalog)
    }

    func loadPersistedScoringandSaliency() {
        guard let catalog = selectedSource?.url else { return }
        guard let catalogIndex = cullingModel.savedFiles.firstIndex(where: { $0.catalog == catalog }) else { return }
        guard let filerecords = cullingModel.savedFiles[catalogIndex].filerecords else { return }

        for file in files {
            // Find the matching file record for this file
            guard let fileRecord = filerecords.first(where: { $0.fileName == file.name }) else { continue }

            // Legacy unsigned scores remain in JSON for compatibility but are stale.
            let metadataMatches = fileRecord.sharpnessFileSize == file.size
                && fileRecord.sharpnessModificationDate.map { abs($0.timeIntervalSince(file.dateModified)) < 0.001 } == true
            guard fileRecord.sharpnessScoringSignature == sharpnessModel.scoringSignature, metadataMatches else { continue }

            if let score = fileRecord.sharpnessScore {
                sharpnessModel.scores[file.id] = score
            }

            if let subjectLabel = fileRecord.saliencySubject {
                // Create saliency info with the subject label
                sharpnessModel.saliencyInfo[file.id] = SaliencyInfo(subjectLabel: subjectLabel)
            }
        }
    }
}
