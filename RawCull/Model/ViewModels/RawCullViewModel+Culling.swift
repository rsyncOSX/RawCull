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
                if rating == 0 {
                    // Remove the record entirely — file is untagged
                    cullingModel.savedFiles[index].filerecords?.removeAll { $0.fileName == file.name }
                } else if let recordIndex = cullingModel.savedFiles[index].filerecords?.firstIndex(where: { $0.fileName == file.name }) {
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
            } else if rating != 0 {
                // No catalog entry yet — create one (only for non-zero ratings)
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

    func toggleTag(for file: FileItem) async {
        await cullingModel.toggleSelectionSavedFiles(
            in: file.url,
            toggledfilename: file.name,
        )
    }
}
