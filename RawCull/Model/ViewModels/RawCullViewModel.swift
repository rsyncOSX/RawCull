import Foundation
import Observation
import OSAKit
import OSLog

enum AlertType {
    case extractJPGs
    case clearToggledFiles
    case resetSavedFiles
}

enum RatingFilter: Hashable {
    case all
    case rejected       // rating == -1
    case keepers        // rating == 0
    case minimum(Int)   // rating >= n, n in 2...5
}

@Observable @MainActor
final class RawCullViewModel {
    /// Remember previous selected source to avoid a new rescan of
    /// already scanned catalog
    @ObservationIgnored var currentselectedSource: ARWSourceCatalog?

    var sources: [ARWSourceCatalog] = []
    var selectedSource: ARWSourceCatalog?
    var files: [FileItem] = []
    var filteredFiles: [FileItem] = []
    var searchText = ""
    var selectedFileID: FileItem.ID?
    var previouslySelectedFileID: FileItem.ID?
    var sortOrder = [KeyPathComparator(\FileItem.name)]
    var isShowingPicker = false
    var hideInspector = true
    var selectedFile: FileItem?
    var issorting: Bool = false
    var progress: Double = 0
    var max: Double = 0
    var estimatedSeconds: Int = 0
    var creatingthumbnails: Bool = false
    var scanning: Bool = true
    var showingAlert: Bool = false

    var focustagimage: Bool = false
    var focusaborttask: Bool = false
    var focusExtractJPGs: Bool = false

    var showcopyARWFilesView: Bool = false
    var alertType: AlertType?
    var sheetType: SheetType? = .copytasksview
    var remotedatanumbers: RemoteDataNumbers?
    var ratingFilter: RatingFilter = .all

    // Zoom window state
    var zoomCGImageWindowFocused: Bool = false
    var zoomNSImageWindowFocused: Bool = false
    var pendingCGImageUpdate: CGImage?
    var pendingNSImageUpdate: NSImage?

    // Thumbnail preview zoom state
    var scale: CGFloat = 1.0
    var lastScale: CGFloat = 1.0
    var offset: CGSize = .zero

    /// This is the only place CullingModel is initialised.
    var cullingModel = CullingModel()

    /// Single shared instance — config changes here affect both the zoom
    /// overlay and the sharpness scoring pipeline.
    var sharpnessModel = SharpnessScoringModel()

    /// URLs for which startAccessingSecurityScopedResource() has been called.
    /// Stopped in deinit to pair every start with a stop.
    @ObservationIgnored private var securityScopedURLs: Set<URL> = []

    /// URLs whose thumbnails have already been preloaded — skip on revisit.
    @ObservationIgnored var processedURLs: Set<URL> = []

    var memorypressurewarning: Bool = false

    /// Focus points created by exiftool, if available.
    var focusPoints: [FocusPointsModel]?

    var showSavedFiles: Bool = false

    /// Closure to count scanning files
    var countingScannedFiles: (@Sendable (Int) -> Void)?

    var currentScanAndCreateThumbnailsActor: ScanAndCreateThumbnails?
    var currentExtractAndSaveJPGsActor: ExtractAndSaveJPGs?
    var preloadTask: Task<Void, Never>?

    // MARK: - Computed

    var useThumbnailAsZoomPreview: Bool {
        SettingsViewModel.shared.useThumbnailAsZoomPreview
    }

    var alertTitle: String {
        switch alertType {
        case .extractJPGs: "Extract JPGs"
        case .clearToggledFiles: "Clear Tagged Files"
        case .resetSavedFiles: "Reset Saved Files"
        case .none: ""
        }
    }

    var alertMessage: String {
        switch alertType {
        case .extractJPGs: "Are you sure you want to extract JPG images from ARW files?"
        case .clearToggledFiles: "Are you sure you want to clear all tagged files?"
        case .resetSavedFiles: "Are you sure you want to reset all saved files?"
        case .none: ""
        }
    }

    // MARK: - Zoom

    func resetZoom() {
        scale = 1.0
        lastScale = 1.0
        offset = .zero
    }

    // MARK: - File Selection

    func selectFile(_ file: FileItem) {
        selectedFile = file
        selectedFileID = file.id
    }

    // MARK: - Focus Points

    func getFocusPoints() -> [FocusPoint]? {
        guard focusPoints != nil else { return nil }
        if let imageName = selectedFile?.name,
           let points = focusPoints?.filter({ $0.sourceFile == imageName }),
           points.count == 1 {
            return points[0].focusPoints
        }
        return nil
    }

    // MARK: - Security-scoped resource lifecycle

    /// Call after a successful startAccessingSecurityScopedResource() so the
    /// ViewModel can pair every start with a stop.
    func trackSecurityScopedAccess(for url: URL) {
        securityScopedURLs.insert(url)
    }

    /// Explicitly release access for a URL (e.g., when a catalog source is removed).
    func stopSecurityScopedAccess(for url: URL) {
        guard securityScopedURLs.contains(url) else { return }
        url.stopAccessingSecurityScopedResource()
        securityScopedURLs.remove(url)
    }

    deinit {
        for url in securityScopedURLs {
            url.stopAccessingSecurityScopedResource()
        }
    }
}
