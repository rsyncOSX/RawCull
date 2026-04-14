//
//  RawCullViewModel+Similarity.swift
//  RawCull
//

import Foundation

extension RawCullViewModel {
    // MARK: - Indexing

    /// Compute Vision feature-print embeddings for all files in the current catalog.
    /// After a successful (non-cancelled) run, embeddings are persisted to SavedFiles.
    func indexSimilarity() async {
        await similarityModel.indexFiles(files)
        if !similarityModel.embeddings.isEmpty {
            persistSimilarityEmbeddingsInMemory()
            await WriteSavedFilesJSON.write(cullingModel.savedFiles)
        }
    }

    // MARK: - Ranking

    /// Rank all indexed images by similarity to the currently selected file.
    /// Reuses saliency labels from the sharpness model for a small subject-mismatch penalty.
    /// Updates filteredFiles ordering via handleSortOrderChange() after ranking.
    func findSimilarToSelected() async {
        guard let anchor = selectedFile else { return }
        await similarityModel.rankSimilar(
            to: anchor.id,
            using: files,
            saliencyInfo: sharpnessModel.saliencyInfo
        )
        await handleSortOrderChange()
    }

    // MARK: - Persistence

    /// Merges current embeddings into cullingModel.savedFiles (in-memory only).
    /// Caller is responsible for calling WriteSavedFilesJSON.write(_:).
    func persistSimilarityEmbeddingsInMemory() {
        guard let catalog = selectedSource?.url else { return }
        let embeddings = similarityModel.embeddings
        let date = Date().en_string_from_date()

        // Resolve (or create) the catalog entry with a single lookup.
        // When creating a new entry, SavedFiles requires an initial FileRecord — we use the
        // first embedded file as a seed. Remaining files are added in the loop below.
        // This mirrors the pattern used by persistScoringResultsInMemory().
        let catalogIndex: Int
        if let existing = cullingModel.savedFiles.firstIndex(where: { $0.catalog == catalog }) {
            catalogIndex = existing
        } else {
            guard let firstFile = files.first(where: { embeddings[$0.id] != nil }) else { return }
            cullingModel.savedFiles.append(SavedFiles(
                catalog: catalog,
                dateStart: date,
                filerecord: FileRecord(
                    fileName: firstFile.name,
                    dateTagged: nil,
                    dateCopied: nil,
                    rating: nil,
                    featurePrintData: embeddings[firstFile.id]
                )
            ))
            catalogIndex = cullingModel.savedFiles.count - 1
        }

        for file in files {
            guard let fpData = embeddings[file.id] else { continue }
            if let recordIndex = cullingModel.savedFiles[catalogIndex].filerecords?.firstIndex(where: { $0.fileName == file.name }) {
                cullingModel.savedFiles[catalogIndex].filerecords?[recordIndex].featurePrintData = fpData
            } else {
                var newRecord = FileRecord(fileName: file.name, dateTagged: nil, dateCopied: nil, rating: nil)
                newRecord.featurePrintData = fpData
                if cullingModel.savedFiles[catalogIndex].filerecords == nil {
                    cullingModel.savedFiles[catalogIndex].filerecords = [newRecord]
                } else {
                    cullingModel.savedFiles[catalogIndex].filerecords?.append(newRecord)
                }
            }
        }
    }

    /// Loads persisted feature-print data from SavedFiles back into the similarity model.
    func loadPersistedSimilarityEmbeddings() {
        guard let catalog = selectedSource?.url else { return }
        guard let catalogIndex = cullingModel.savedFiles.firstIndex(where: { $0.catalog == catalog }) else { return }
        guard let filerecords = cullingModel.savedFiles[catalogIndex].filerecords else { return }

        for file in files {
            guard let record = filerecords.first(where: { $0.fileName == file.name }),
                  let fpData = record.featurePrintData
            else { continue }
            similarityModel.embeddings[file.id] = fpData
        }
    }
}
