import Foundation
import Observation
import RawCullCore

/// Why the last catalog load produced no usable catalog.
enum CatalogLoadFailure {
    case folderAccess
    case noPhotos
}

/// The open catalog: its sources, files, the sorted and filtered projection the
/// views show, and the progress of scanning it.
///
/// `contentRevision` advances when `files` changes and `gridRevision` when
/// `filteredFiles` changes. Projections that depend on the catalog include them
/// in their cache keys.
@Observable @MainActor
final class CatalogWorkspace {
    var sources: [ARWSourceCatalog] = []
    var selectedSource: ARWSourceCatalog?
    @ObservationIgnored var pendingCatalogTransitionSource: ARWSourceCatalog?
    @ObservationIgnored var catalogLoadFailure: CatalogLoadFailure?

    var files: [FileItem] = [] {
        didSet {
            contentRevision &+= 1
            fileIndexByID = Dictionary(
                files.enumerated().map { ($0.element.id, $0.offset) },
                uniquingKeysWith: { first, _ in first },
            )
        }
    }

    private(set) var contentRevision: UInt64 = 0
    @ObservationIgnored private var fileIndexByID: [FileItem.ID: Int] = [:]

    var filteredFiles: [FileItem] = [] {
        didSet { gridRevision &+= 1 }
    }

    private(set) var gridRevision: UInt64 = 0

    /// Full name-sorted/search-filtered catalog projection before rating,
    /// sharpness, and similarity filters are applied.
    @ObservationIgnored var catalogDisplayCandidates: [FileItem] = []

    var searchText = ""
    var sortOrder = FileItemSortDescriptor()
    @ObservationIgnored var sortGeneration: UInt64 = 0
    @ObservationIgnored var sortFiles: @MainActor (
        [FileItem], FileItemSortDescriptor, String,
    ) async -> [FileItem] = { files, order, text in
        await ScanFiles.sortFiles(files, by: order, searchText: text)
    }

    var isSorting = false

    /// Number of RAW files discovered by the active catalog scan. This is
    /// reset with the catalog working set and is the source of truth for the
    /// scanning progress label.
    var scanDiscoveredCount = 0
    @ObservationIgnored var metadataProgress: CatalogProgressCoalescer<Int>?
    @ObservationIgnored var thumbnailProgress: CatalogProgressCoalescer<CatalogThumbnailProgress>?
    var isCreatingThumbnails = false
    var scanning = true
    var currentScanAndCreateThumbnailsActor: ScanAndCreateThumbnails?
    var preloadTask: Task<Void, Never>?
    /// URLs whose thumbnails have already been preloaded — skip on revisit.
    @ObservationIgnored var processedURLs: Set<URL> = []

    /// Focus points created by exiftool, if available.
    var focusPoints: [FocusPointsModel]?

    /// The catalog file with `id`. Reading it registers observation of `files`.
    func file(withID id: FileItem.ID?) -> FileItem? {
        guard let id else { return nil }
        // Read `files` so views that call this keep their dependency.
        let files = files
        guard let index = fileIndexByID[id], files.indices.contains(index), files[index].id == id else {
            return nil
        }
        return files[index]
    }
}
