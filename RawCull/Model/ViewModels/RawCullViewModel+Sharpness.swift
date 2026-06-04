//
//  RawCullViewModel+Sharpness.swift
//  RawCull
//

import Foundation
import RawCullCore

extension RawCullViewModel {
    /// Auto-calibrates focus config from the current catalog, then scores and re-sorts.
    /// After a successful (non-cancelled) run, scores and saliency are persisted to SavedFiles.
    func calibrateAndScoreCurrentCatalog() async {
        await sharpnessModel.calibrateFromBurst(files)
        await sharpnessModel.scoreFiles(files)
        // scores is cleared at the start of scoreFiles and only written on clean completion —
        // an empty dict means the run was cancelled, so skip the write.
        if !sharpnessModel.scores.isEmpty {
            persistScoringResultsInMemory()
        }
        await handleSortOrderChange()
    }

    /// Merges current sharpness scores and saliency labels into cullingModel.savedFiles
    /// and lets the culling store coalesce persistence with other culling changes.
    func persistScoringResultsInMemory() {
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

            if let score = fileRecord.sharpnessScore { sharpnessModel.scores[file.id] = score }

            if let subjectLabel = fileRecord.saliencySubject {
                // Create saliency info with the subject label
                sharpnessModel.saliencyInfo[file.id] = SaliencyInfo(subjectLabel: subjectLabel)
            }
        }
    }
}
