//
//  RawCullViewModel+Culling.swift
//  RawCull
//

import Foundation

extension RawCullViewModel {
    /// Rebuilds the O(1) rating and tagged-names caches from the current catalog entry.
    /// Must be called after any culling store mutation that affects ratings.
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
        guard let selectedSource else { return }
        cullingModel.updateRating(fileName: file.name, rating: rating, in: selectedSource.url)
        rebuildRatingCache()
    }

    func updateRating(for files: [FileItem], rating: Int) {
        guard let selectedSource else { return }
        cullingModel.updateRatings(fileNames: files.map(\.name), rating: rating, in: selectedSource.url)
        rebuildRatingCache()
    }

    func clearCurrentCatalogCullingState() {
        guard let selectedSource else { return }
        cullingModel.resetSavedFiles(in: selectedSource.url)
        ratingCache = [:]
        taggedNamesCache = []
        sharpnessModel.reset()
        similarityModel.reset()
    }
}
