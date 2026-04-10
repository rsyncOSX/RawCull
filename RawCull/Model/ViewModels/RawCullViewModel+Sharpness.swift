//
//  RawCullViewModel+Sharpness.swift
//  RawCull
//

import Foundation

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
            await WriteSavedFilesJSON.write(cullingModel.savedFiles)
        }
        await handleSortOrderChange()
    }

    /// Merges current sharpness scores and saliency labels into cullingModel.savedFiles
    /// without writing to disk. Caller is responsible for the WriteSavedFilesJSON call.
    func persistScoringResultsInMemory() {
        guard let catalog = selectedSource?.url else { return }
        let scores = sharpnessModel.scores
        let saliency = sharpnessModel.saliencyInfo
        let date = Date().en_string_from_date()

        // Ensure a catalog entry exists
        if cullingModel.savedFiles.firstIndex(where: { $0.catalog == catalog }) == nil {
            guard let firstFile = files.first(where: { scores[$0.id] != nil }) else { return }
            cullingModel.savedFiles.append(SavedFiles(
                catalog: catalog,
                dateStart: date,
                filerecord: FileRecord(
                    fileName: firstFile.name,
                    dateTagged: nil,
                    dateCopied: nil,
                    rating: nil,
                    sharpnessScore: scores[firstFile.id],
                    saliencySubject: saliency[firstFile.id]?.subjectLabel,
                ),
            ))
        }

        guard let catalogIndex = cullingModel.savedFiles.firstIndex(where: { $0.catalog == catalog }) else { return }

        for file in files {
            guard let score = scores[file.id] else { continue }
            let subjectLabel = saliency[file.id]?.subjectLabel
            if let recordIndex = cullingModel.savedFiles[catalogIndex].filerecords?.firstIndex(where: { $0.fileName == file.name }) {
                cullingModel.savedFiles[catalogIndex].filerecords?[recordIndex].sharpnessScore = score
                cullingModel.savedFiles[catalogIndex].filerecords?[recordIndex].saliencySubject = subjectLabel
            } else {
                var newRecord = FileRecord(fileName: file.name, dateTagged: nil, dateCopied: nil, rating: nil)
                newRecord.sharpnessScore = score
                newRecord.saliencySubject = subjectLabel
                if cullingModel.savedFiles[catalogIndex].filerecords == nil {
                    cullingModel.savedFiles[catalogIndex].filerecords = [newRecord]
                } else {
                    cullingModel.savedFiles[catalogIndex].filerecords?.append(newRecord)
                }
            }
        }
    }

    func loadPersistedScoringandSaliency() {
        guard let catalog = selectedSource?.url else { return }
        guard let catalogIndex = cullingModel.savedFiles.firstIndex(where: { $0.catalog == catalog }) else { return }
        guard let filerecords = cullingModel.savedFiles[catalogIndex].filerecords else { return }

        for file in files {
            // Find the matching file record for this file
            guard let fileRecord = filerecords.first(where: { $0.fileName == file.name }) else { continue }

            // Load the persisted score and saliency info back into the sharpness model
            if let score = fileRecord.sharpnessScore { sharpnessModel.scores[file.id] = score }

            if let subjectLabel = fileRecord.saliencySubject {
                // Create saliency info with the subject label
                sharpnessModel.saliencyInfo[file.id] = SaliencyInfo(subjectLabel: subjectLabel)
            }
        }
    }
}
