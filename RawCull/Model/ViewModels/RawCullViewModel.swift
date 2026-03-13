import Foundation
import Observation
import OSAKit
import OSLog

enum AlertType {
    case extractJPGs
    case clearToggledFiles
    case resetSavedFiles
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
    var isInspectorPresented = false
    var hideInspector = false
    var selectedFile: FileItem?
    var issorting: Bool = false
    var progress: Double = 0
    var max: Double = 0
    var estimatedSeconds: Int = 0 // Estimated seconds to completion
    var creatingthumbnails: Bool = false
    var scanning: Bool = true
    var showingAlert: Bool = false

    var focustagimage: Bool = false
    var focusaborttask: Bool = false
    var focushideInspector: Bool = false
    var focusExtractJPGs: Bool = false

    var showcopyARWFilesView: Bool = false
    var alertType: AlertType?
    var sheetType: SheetType? = .copytasksview
    var remotedatanumbers: RemoteDataNumbers?
    var rating: Int = 0

    // Zoom window state
    var zoomCGImageWindowFocused: Bool = false
    var zoomNSImageWindowFocused: Bool = false
    var pendingCGImageUpdate: CGImage?
    var pendingNSImageUpdate: NSImage?

    // Thumbnail preview zoom state
    var scale: CGFloat = 1.0
    var lastScale: CGFloat = 1.0
    var offset: CGSize = .zero

    // This is the oncly place the Culling Model is initialzed.
    var cullingModel = CullingModel()
    private var processedURLs: Set<URL> = []

    var memorypressurewarning: Bool = false

    /// If there is created Focus Data with exiftool
    var focusPoints: [FocusPointsModel]?

    /// Use Thumbnail as Zoom Preview - reads from SettingsViewModel
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

    /// Closure to count scanning files
    var countingScannedFiles: (@Sendable (Int) -> Void)?

    // Add a property to hold the current preload actor
    var currentScanAndCreateThumbnailsActor: ScanAndCreateThumbnails?
    var currentExtractAndSaveJPGsActor: ExtractAndSaveJPGs?
    var preloadTask: Task<Void, Never>?

    func handleSourceChange(url: URL) async {
        scanning = true

        let scan = ScanFiles()

        files = await scan.scanFiles(
            url: url,
            onProgress: countingScannedFiles,
        )
        // Get the focuspoints if created
        // Map raw decoded data → FocusPointsModel here on @MainActor — no isolation issue
        if let raw = await scan.decodedFocusPoints {
            focusPoints = raw.map {
                FocusPointsModel(sourceFile: $0.sourceFile, focusLocations: [$0.focusLocation])
            }
        } else {
            focusPoints = nil
        }

        Logger.process.debugMessageOnly("Finished scanning! Total files: \(files.count)")

        filteredFiles = await ScanFiles().sortFiles(
            files,
            by: sortOrder,
            searchText: searchText,
        )

        guard !files.isEmpty else {
            scanning = false
            return
        }

        scanning = false
        cullingModel.loadSavedFiles()

        if !processedURLs.contains(url) {
            processedURLs.insert(url)
            creatingthumbnails = true

            let settingsmanager = await SettingsViewModel.shared.asyncgetsettings()
            let thumbnailSizePreview = settingsmanager.thumbnailSizePreview

            let handlers = CreateFileHandlers().createFileHandlers(
                fileHandler: fileHandler,
                maxfilesHandler: maxfilesHandler,
                estimatedTimeHandler: estimatedTimeHandler,
                memorypressurewarning: memorypressurewarning,
            )

            let scanAndCreateThumbnails = ScanAndCreateThumbnails()
            await scanAndCreateThumbnails.setFileHandlers(handlers)
            currentScanAndCreateThumbnailsActor = scanAndCreateThumbnails

            preloadTask = Task {
                await scanAndCreateThumbnails.preloadCatalog(
                    at: url,
                    targetSize: thumbnailSizePreview,
                )
            }

            await preloadTask?.value // wait for completion (or cancellation)
            creatingthumbnails = false
            currentScanAndCreateThumbnailsActor = nil
        }
    }

    func handleSortOrderChange() async {
        issorting = true
        filteredFiles = await ScanFiles().sortFiles(
            files,
            by: sortOrder,
            searchText: searchText,
        )
        issorting = false
    }

    func handleSearchTextChange() async {
        issorting = true
        filteredFiles = await ScanFiles().sortFiles(
            files,
            by: sortOrder,
            searchText: searchText,
        )
        issorting = false
    }

    func clearMemoryCachesandTagging() async {
        sources.removeAll()
        selectedSource = nil
        filteredFiles.removeAll()
        files.removeAll()
        selectedFile = nil
    }

    func fileHandler(_ update: Int) {
        progress = Double(update)
    }

    func maxfilesHandler(_ maxfiles: Int) {
        max = Double(maxfiles)
    }

    func estimatedTimeHandler(_ seconds: Int) {
        estimatedSeconds = seconds
    }

    func abort() {
        Logger.process.debugMessageOnly("Abort scanning")

        // Cancel thumbnail preload
        preloadTask?.cancel()
        preloadTask = nil
        if let actor = currentScanAndCreateThumbnailsActor {
            Task { await actor.cancelPreload() }
        }
        currentScanAndCreateThumbnailsActor = nil

        // Cancel JPG extraction — same pattern
        if let actor = currentExtractAndSaveJPGsActor {
            Task { await actor.cancelExtractJPGSTask() }
        }
        currentExtractAndSaveJPGsActor = nil

        creatingthumbnails = false
    }

    /*
     abort()
       ├─ preloadTask?.cancel()          → cancels the outer Task (ViewModel)
       └─ actor.cancelPreload()          → cancels the INNER Task (actor.preloadTask)
            └─ actor.preloadTask.cancel()
                 └─ Task.isCancelled = true for the task group + all children
                      └─ processSingleFile checks fire → return immediately
     */

    func extractRatedfilenames(_ rating: Int) -> [String] {
        let result = filteredFiles.compactMap { file in
            (getRating(for: file) >= rating) ? file : nil
        }
        return result.map(\.name)
    }

    func extractTaggedfilenames() -> [String] {
        if let index = cullingModel.savedFiles.firstIndex(where: { $0.catalog == selectedSource?.url }),
           let taggedfilerecords = cullingModel.savedFiles[index].filerecords {
            return taggedfilerecords.compactMap(\.fileName)
        }
        return []
    }

    func getRating(for file: FileItem) -> Int {
        if let index = cullingModel.savedFiles.firstIndex(where: { $0.catalog == selectedSource?.url }),
           let filerecords = cullingModel.savedFiles[index].filerecords,
           let record = filerecords.first(where: { $0.fileName == file.name }) {
            return record.rating ?? 0
        }
        return 0
    }

    func updateRating(for file: FileItem, rating: Int) {
        Task {
            guard let selectedSource else { return }
            if let index = cullingModel.savedFiles.firstIndex(where: { $0.catalog == selectedSource.url }),
               let recordIndex = cullingModel.savedFiles[index].filerecords?.firstIndex(where: { $0.fileName == file.name }) {
                cullingModel.savedFiles[index].filerecords?[recordIndex].rating = rating
                await WriteSavedFilesJSON(cullingModel.savedFiles)
            }
        }
    }

    func memorypressurewarning(_ warning: Bool) {
        memorypressurewarning = warning
    }

    func resetZoom() {
        scale = 1.0
        lastScale = 1.0
        offset = .zero
    }

    /// Pick the right focus points
    func getFocusPoints() -> [FocusPoint]? {
        guard focusPoints != nil else {
            return nil
        }
        if let imageName = selectedFile?.name {
            if let points = focusPoints?.filter({ $0.sourceFile == imageName }) {
                guard points.count == 1 else {
                    return nil
                }
                return points[0].focusPoints
            }
        }
        return nil
    }
}
