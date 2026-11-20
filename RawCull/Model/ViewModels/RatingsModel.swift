import Foundation
import Observation
import RawCullCore

/// Ratings for the current catalog: the persisted culling store, the O(1)
/// rating lookup built from it, and the active rating filter.
///
/// `revision` advances whenever the rating lookup changes. Projections that
/// depend on ratings (the culling grid, zoom navigation) include it in their
/// cache keys instead of relying on a side effect elsewhere.
@Observable @MainActor
final class RatingsModel: ImageReviewRatingProviding {
    /// This is the only place CullingModel is initialised.
    var cullingModel = CullingModel()

    /// O(1) lookup: filename → rating for the current source catalog.
    /// Rebuilt by `rebuildRatingCache(catalog:)` after any culling state change.
    var ratingCache: [String: Int] = [:] {
        didSet { revision &+= 1 }
    }

    /// Filenames that have an explicit record in the current catalog.
    var taggedNamesCache: Set<String> = []

    var ratingFilter: RatingFilter = .all

    private(set) var revision: UInt64 = 0

    /// Rebuilds the rating and tagged-names caches from `catalog`'s entry.
    /// Must be called after any culling store mutation that affects ratings.
    func rebuildRatingCache(catalog: URL?) {
        guard let catalog,
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
            guard let name = record.fileName, let rating = record.rating else { continue }
            cache[name] = rating
            tagged.insert(name)
        }
        ratingCache = cache
        taggedNamesCache = tagged
    }

    func rating(for file: FileItem) -> Int? {
        ratingCache[file.name]
    }

    func getRating(for file: FileItem) -> Int {
        rating(for: file) ?? 0
    }

    func passesRatingFilter(_ file: FileItem) -> Bool {
        switch ratingFilter {
        case .all: true
        case .rejected: rating(for: file) == -1
        case .keepers: rating(for: file) == 0
        case let .stars(n): rating(for: file) == n
        }
    }

    func hasRating(in files: [FileItem], catalog: URL?) -> Bool {
        guard !files.isEmpty,
              let catalog,
              let records = cullingModel.savedFiles.first(where: { $0.catalog == catalog })?.filerecords
        else { return false }

        let fileNames = Set(files.map(\.name))
        return records.contains { record in
            guard let fileName = record.fileName else { return false }
            return record.rating != nil && fileNames.contains(fileName)
        }
    }

    /// Names of files rated 2 or more in `catalog` that are among `activeNames`.
    func taggedFileNames(catalog: URL?, activeNames: Set<String>) -> [String] {
        guard let index = cullingModel.savedFiles.firstIndex(where: { $0.catalog == catalog }),
              let taggedfilerecords = cullingModel.savedFiles[index].filerecords
        else { return [] }
        return taggedfilerecords
            .filter {
                ($0.rating ?? 0) >= 2
                    && $0.fileName.map(activeNames.contains) == true
            }
            .compactMap(\.fileName)
    }

    /// Clears the catalog-scoped presentation state. The persisted culling
    /// store is not touched.
    func resetForCatalogChange() {
        ratingFilter = .all
    }
}
