//
//  RawCullViewModel+Culling.swift
//  RawCull
//

import Foundation

extension RawCullViewModel {
    /// Rebuilds the O(1) rating and tagged-names caches from the current catalog entry.
    /// Must be called after any mutation of cullingModel.savedFiles.
    func rebuildRatingCache() {
        guard let catalog = selectedSource?.url,
              let index = cullingModel.savedFiles.firstIndex(where: { $0.catalog == catalog }),
              let records = cullingModel.savedFiles[index].filerecords
        else {
            ratingCache = [:]
            taggedNamesCache = []
            return
        }
        var cache: [String: Int] = [:]
        var tagged: Set<String> = []
        for record in records {
            guard let name = record.fileName else { continue }
            cache[name] = record.rating ?? 0
            tagged.insert(name)
        }
        ratingCache = cache
        taggedNamesCache = tagged
    }

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
        case .all: true
        case .rejected: getRating(for: file) == -1
        case .keepers: getRating(for: file) == 0
        case let .stars(n): getRating(for: file) == n
        }
    }

    func getRating(for file: FileItem) -> Int {
        ratingCache[file.name] ?? 0
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
            rebuildRatingCache()
        }
    }

    func applySharpnessThreshold(_ thresholdPercent: Int) {
        let maxScore = sharpnessModel.maxScore
        guard maxScore > 0, let selectedSource else { return }
        let catalog = selectedSource.url
        let date = Date().en_string_from_date()

        // Ensure a catalog entry exists — created from the first scored file if needed
        if cullingModel.savedFiles.firstIndex(where: { $0.catalog == catalog }) == nil {
            guard let firstFile = filteredFiles.first(where: { sharpnessModel.scores[$0.id] != nil }),
                  let firstScore = sharpnessModel.scores[firstFile.id]
            else { return }
            let normalised = Int((firstScore / maxScore) * 100)
            cullingModel.savedFiles.append(SavedFiles(
                catalog: catalog,
                dateStart: date,
                filerecord: FileRecord(fileName: firstFile.name, dateTagged: date, dateCopied: nil, rating: normalised >= thresholdPercent ? 0 : -1),
            ))
        }

        guard let catalogIndex = cullingModel.savedFiles.firstIndex(where: { $0.catalog == catalog }) else { return }

        // Mutate all records in-memory, then write once
        for file in filteredFiles {
            guard let score = sharpnessModel.scores[file.id] else { continue }
            let normalised = Int((score / maxScore) * 100)
            let rating = normalised >= thresholdPercent ? 0 : -1

            if let recordIndex = cullingModel.savedFiles[catalogIndex].filerecords?.firstIndex(where: { $0.fileName == file.name }) {
                cullingModel.savedFiles[catalogIndex].filerecords?[recordIndex].rating = rating
            } else {
                let newRecord = FileRecord(fileName: file.name, dateTagged: date, dateCopied: nil, rating: rating)
                if cullingModel.savedFiles[catalogIndex].filerecords == nil {
                    cullingModel.savedFiles[catalogIndex].filerecords = [newRecord]
                } else {
                    cullingModel.savedFiles[catalogIndex].filerecords?.append(newRecord)
                }
            }
        }

        Task {
            await WriteSavedFilesJSON(cullingModel.savedFiles)
        }
        rebuildRatingCache()
    }

    func toggleTag(for file: FileItem) async {
        await cullingModel.toggleSelectionSavedFiles(
            in: file.url,
            toggledfilename: file.name,
        )
        rebuildRatingCache()
    }
}
