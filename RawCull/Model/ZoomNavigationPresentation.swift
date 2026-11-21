import Foundation
import RawCullCore

struct ZoomNavigationProjectionKey: Equatable {
    let catalogRevision: UInt64
    let gridRevision: UInt64
    let ratingRevision: UInt64
    let contextRevision: UInt64
    let sourceURL: URL?
    let ratingFilter: RatingFilter
    let usesAnalysisSortOrder: Bool
}

struct ZoomNavigationProjection {
    let key: ZoomNavigationProjectionKey
    let files: [FileItem]
    let indexByID: [FileItem.ID: Int]
    let catalogIDs: Set<FileItem.ID>
}

extension CatalogController {
    func zoomNavigationProjection() -> ZoomNavigationProjection {
        // Read observable inputs even on cache hits so views retain dependencies.
        let key = ZoomNavigationProjectionKey(
            catalogRevision: catalog.contentRevision,
            gridRevision: catalog.gridRevision,
            ratingRevision: ratings.revision,
            contextRevision: zoomOverlay.contextRevision,
            sourceURL: catalog.selectedSource?.url,
            ratingFilter: ratings.ratingFilter,
            usesAnalysisSortOrder: sharpnessModel.sortBySharpness || similarityFeature.isSimilaritySortingActive,
        )
        if let cached = zoomNavigationCache, cached.key == key {
            return cached
        }
        let catalogIDs = Set(catalog.files.map(\.id))
        var ordered: [FileItem] = []
        if let context = zoomOverlay.navigationContext {
            let filesByID = Dictionary(uniqueKeysWithValues: catalog.files.map { ($0.id, $0) })
            ordered = context.orderedFileIDs.compactMap { filesByID[$0] }
        }
        if ordered.isEmpty {
            let filtered = catalog.filteredFiles.filter { ratings.passesRatingFilter($0) }
            ordered = key.usesAnalysisSortOrder
                ? filtered
                : filtered.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        }
        let projection = ZoomNavigationProjection(
            key: key,
            files: ordered,
            indexByID: Dictionary(ordered.enumerated().map { ($0.element.id, $0.offset) },
                                  uniquingKeysWith: { first, _ in first }),
            catalogIDs: catalogIDs,
        )
        // Memoization is not presentation state and must not trigger updates.
        zoomNavigationCache = projection
        zoomNavigationBuildCount += 1
        return projection
    }
}

@MainActor
struct ZoomNavigationPresentation {
    let catalogController: CatalogController
    let selection: SelectionModel

    var orderedZoomFiles: [FileItem] {
        catalogController.zoomNavigationProjection().files
    }

    var currentZoomIndex: Int? {
        guard let selectedID = selection.selectedFileID else { return nil }
        let projection = catalogController.zoomNavigationProjection()
        guard projection.catalogIDs.contains(selectedID) else { return nil }
        return projection.indexByID[selectedID]
    }

    var canNavigatePrevious: Bool {
        guard let currentZoomIndex else { return false }
        return currentZoomIndex > 0
    }

    var canNavigateNext: Bool {
        guard let currentZoomIndex else { return false }
        return currentZoomIndex + 1 < orderedZoomFiles.count
    }
}
