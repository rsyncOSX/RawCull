import Foundation
import Observation
import OSAKit
import OSLog

@Observable @MainActor
final class RawCullViewModel {
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

    var focustogglerow: Bool = false
    var focusaborttask: Bool = false
    var focushideInspector: Bool = false
    var focusExtractJPGs: Bool = false
    var focusPressEnter: Bool = false

    var showcopytask: Bool = false
    var alertType: RawCullAlertView.AlertType?
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

    var cullingModel = CullingModel()
    private var processedURLs: Set<URL> = []

    var memorypressurewarning: Bool = false

    /// Use Thumbnail as Zoom Preview - reads from SettingsViewModel
    var useThumbnailAsZoomPreview: Bool {
        SettingsViewModel.shared.useThumbnailAsZoomPreview
    }

    func handleSourceChange(url: URL) async {
        scanning = true

        files = await ScanFiles().scanFiles(url: url)
        filteredFiles = await ScanFiles().sortFiles(
            files,
            by: sortOrder,
            searchText: searchText
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

            Logger.process.debugMessageOnly("SidebarRawCullViewModel: targetSize: \(thumbnailSizePreview)")

            let handlers = CreateFileHandlers().createFileHandlers(
                fileHandler: fileHandler,
                maxfilesHandler: maxfilesHandler,
                estimatedTimeHandler: estimatedTimeHandler,
                memorypressurewarning: memorypressurewarning
            )

            let scanAndCreateThumbnails = ScanAndCreateThumbnails()
            await scanAndCreateThumbnails.setFileHandlers(handlers)
            await scanAndCreateThumbnails.preloadCatalog(
                at: url,
                targetSize: thumbnailSizePreview
            )

            creatingthumbnails = false
        }
    }

    func handleSortOrderChange() async {
        issorting = true
        filteredFiles = await ScanFiles().sortFiles(
            files,
            by: sortOrder,
            searchText: searchText
        )
        issorting = false
    }

    func handleSearchTextChange() async {
        issorting = true
        filteredFiles = await ScanFiles().sortFiles(
            files,
            by: sortOrder,
            searchText: searchText
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
        // Implementation deferred - abort functionality to be added
    }

    func extractRatedfilenames(_ rating: Int) -> [String] {
        let result = filteredFiles.compactMap { file in
            (getRating(for: file) >= rating) ? file : nil
        }
        return result.map { $0.name }
    }

    func extractTaggedfilenames() -> [String] {
        if let index = cullingModel.savedFiles.firstIndex(where: { $0.catalog == selectedSource?.url }),
           let taggedfilerecords = cullingModel.savedFiles[index].filerecords {
            return taggedfilerecords.compactMap { $0.fileName }
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
        guard let selectedSource = selectedSource else { return }
        if let index = cullingModel.savedFiles.firstIndex(where: { $0.catalog == selectedSource.url }),
           let recordIndex = cullingModel.savedFiles[index].filerecords?.firstIndex(where: { $0.fileName == file.name }) {
            cullingModel.savedFiles[index].filerecords?[recordIndex].rating = rating
            WriteSavedFilesJSON(cullingModel.savedFiles)
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
}
