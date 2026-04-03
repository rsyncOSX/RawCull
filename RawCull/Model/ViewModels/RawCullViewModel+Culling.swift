//
//  RawCullViewModel+Culling.swift
//  RawCull
//

import Foundation

extension RawCullViewModel {
    func extractRatedfilenames(_ rating: Int) -> [String] {
        filteredFiles
            .filter { getRating(for: $0) >= rating }
            .map(\.name)
    }

    func extractTaggedfilenames() -> [String] {
        guard let index = cullingModel.savedFiles.firstIndex(where: { $0.catalog == selectedSource?.url }),
              let taggedfilerecords = cullingModel.savedFiles[index].filerecords
        else { return [] }
        return taggedfilerecords
            .filter { ($0.rating ?? 0) >= 2 }
            .compactMap(\.fileName)
    }

    func passesRatingFilter(_ file: FileItem) -> Bool {
        switch ratingFilter {
        case .all:           return true
        case .rejected:      return getRating(for: file) == -1
        case .keepers:       return getRating(for: file) == 0
        case .minimum(let n): return getRating(for: file) >= n
        }
    }

    func getRating(for file: FileItem) -> Int {
        guard let index = cullingModel.savedFiles.firstIndex(where: { $0.catalog == selectedSource?.url }),
              let filerecords = cullingModel.savedFiles[index].filerecords,
              let record = filerecords.first(where: { $0.fileName == file.name })
        else { return 0 }
        return record.rating ?? 0
    }

    func updateRating(for file: FileItem, rating: Int) {
        Task {
            guard let selectedSource else { return }
            let catalog = selectedSource.url

            if let index = cullingModel.savedFiles.firstIndex(where: { $0.catalog == catalog }) {
                if let recordIndex = cullingModel.savedFiles[index].filerecords?.firstIndex(where: { $0.fileName == file.name }) {
                    // Update existing record
                    cullingModel.savedFiles[index].filerecords?[recordIndex].rating = rating
                } else {
                    // Create a new record — file has not been tagged yet
                    let newRecord = FileRecord(
                        fileName: file.name,
                        dateTagged: Date().en_string_from_date(),
                        dateCopied: nil,
                        rating: rating,
                    )
                    if cullingModel.savedFiles[index].filerecords == nil {
                        cullingModel.savedFiles[index].filerecords = [newRecord]
                    } else {
                        cullingModel.savedFiles[index].filerecords?.append(newRecord)
                    }
                }
            } else {
                // No catalog entry yet — create one
                let newRecord = FileRecord(
                    fileName: file.name,
                    dateTagged: Date().en_string_from_date(),
                    dateCopied: nil,
                    rating: rating,
                )
                cullingModel.savedFiles.append(SavedFiles(
                    catalog: catalog,
                    dateStart: Date().en_string_from_date(),
                    filerecord: newRecord,
                ))
            }
            await WriteSavedFilesJSON(cullingModel.savedFiles)
        }
    }

    func applySharpnessThreshold(_ thresholdPercent: Int) {
        let maxScore = sharpnessModel.maxScore
        guard maxScore > 0 else { return }
        for file in filteredFiles {
            guard let score = sharpnessModel.scores[file.id] else { continue }
            let normalised = Int((score / maxScore) * 100)
            updateRating(for: file, rating: normalised >= thresholdPercent ? 0 : -1)
        }
    }

    func toggleTag(for file: FileItem) async {
        await cullingModel.toggleSelectionSavedFiles(
            in: file.url,
            toggledfilename: file.name,
        )
    }
}
