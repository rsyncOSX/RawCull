import Foundation
import Observation
import OSLog
import RawCullCore

/// What file operations read from, and report to, the catalog workspace.
@MainActor
protocol FileOperationsCatalog: AnyObject {
    var catalog: CatalogWorkspace { get }
    /// The catalog files, or the scoped files while a semantic selection is active.
    var activeCatalogFiles: [FileItem] { get }
    var selection: SelectionModel { get }
    var presentation: WorkspacePresentationModel { get }
    func startSecurityScopedResource(_ url: URL) -> Bool
    func stopSecurityScopedResource(_ url: URL)
}

/// JPG extraction, JPG cache warming, and the progress shared by file
/// operations and the catalog thumbnail scan.
@Observable @MainActor
final class FileOperationsModel {
    @ObservationIgnored weak var workspace: (any FileOperationsCatalog)?

    var extractJPGExportMode: ExtractJPGExportMode = .embeddedJPG
    var extractJPGSelectedOnly = true
    var extractJPGDestination: ARWSourceCatalog?
    var remoteDataNumbers: RemoteDataNumbers?

    var fileOperationCompleted: Int = 0
    var fileOperationTotal: Int = 0
    var fileOperationEstimatedSeconds: Int = 0

    var currentExtractAndSaveJPGsActor: ExtractAndSaveJPGs?
    var currentScanAndExtractJPGsActor: ScanAndExtractJPGs?
    @ObservationIgnored var jpgCacheWarmTask: Task<Void, Never>?

    func bind(_ workspace: any FileOperationsCatalog) {
        self.workspace = workspace
    }

    func fileHandler(_ update: Int) {
        fileOperationCompleted = update
    }

    func maxfilesHandler(_ maxfiles: Int) {
        Logger.process.debugMessageOnly("FileOperationsModel.maxfilesHandler()")
        fileOperationTotal = maxfiles
    }

    func estimatedTimeHandler(_ seconds: Int) {
        fileOperationEstimatedSeconds = seconds
    }

    var selectedFilesForJPGExtraction: [FileItem] {
        guard let workspace else { return [] }
        if !workspace.selection.selectedFileIDs.isEmpty {
            return workspace.catalog.filteredFiles.filter { workspace.selection.selectedFileIDs.contains($0.id) }
        }

        guard let selectedFileID = workspace.selection.selectedFileID else { return [] }
        if let file = workspace.catalog.filteredFiles.first(where: { $0.id == selectedFileID }) {
            return [file]
        }
        return workspace.activeCatalogFiles
            .first(where: { $0.id == selectedFileID })
            .map { [$0] } ?? []
    }

    var filesForJPGExtraction: [FileItem] {
        extractJPGSelectedOnly ? selectedFilesForJPGExtraction : workspace?.activeCatalogFiles ?? []
    }

    func presentExtractJPGsSheet() {
        Logger.process.debugMessageOnly("FileOperationsModel.presentExtractJPGsSheet()")
        guard let workspace, !workspace.catalog.sources.isEmpty else { return }
        extractJPGSelectedOnly = !selectedFilesForJPGExtraction.isEmpty
        if extractJPGDestination == nil {
            extractJPGDestination = workspace.catalog.selectedSource ?? workspace.catalog.sources.first
        }
        workspace.presentation.activeSheet = .extractJPGs
    }

    func startSelectedJPGExtraction(destination: ARWSourceCatalog, exportMode: ExtractJPGExportMode) {
        Logger.process.debugMessageOnly("FileOperationsModel.startSelectedJPGExtraction()")
        let exportFiles = filesForJPGExtraction
        guard let workspace,
              currentScanAndExtractJPGsActor == nil,
              workspace.catalog.currentScanAndCreateThumbnailsActor == nil,
              currentExtractAndSaveJPGsActor == nil,
              !exportFiles.isEmpty
        else { return }

        fileOperationCompleted = 0
        fileOperationTotal = exportFiles.count
        fileOperationEstimatedSeconds = 0
        workspace.catalog.isCreatingThumbnails = true

        let handlers = CreateFileHandlers().createFileHandlers(
            fileHandler: fileHandler,
            maxfilesHandler: maxfilesHandler,
            estimatedTimeHandler: estimatedTimeHandler,
            memorypressurewarning: { _ in },
            onExtractionNeeded: {},
        )

        let destinationURL = destination.url
        let destinationAccessStarted = workspace.startSecurityScopedResource(destinationURL)
        guard destinationAccessStarted else {
            workspace.catalog.isCreatingThumbnails = false
            workspace.presentation.operationFailurePresentation = OperationFailurePresentation(
                title: "Export Not Started",
                message: "RawCull could not access the selected destination folder. Choose the folder again and retry.",
            )
            return
        }
        let extract = ExtractAndSaveJPGs(
            files: exportFiles,
            destinationCatalogURL: destinationURL,
            exportMode: exportMode,
        )
        currentExtractAndSaveJPGsActor = extract

        let sourceAccess = RawCullCatalogAccess.shared.retainAccess(for: exportFiles.map(\.url))
        Task(priority: .background) {
            defer { withExtendedLifetime(sourceAccess) {} }
            await extract.setFileHandlers(handlers)
            let result = await extract.extractAndSavejpgs()

            await MainActor.run {
                workspace.stopSecurityScopedResource(destinationURL)
                guard self.currentExtractAndSaveJPGsActor === extract else { return }
                self.currentExtractAndSaveJPGsActor = nil
                workspace.catalog.isCreatingThumbnails = false
                if !result.failures.isEmpty {
                    let firstFailure = result.failures[0]
                    workspace.presentation.operationFailurePresentation = OperationFailurePresentation(
                        title: "Export Incomplete",
                        message: "\(result.failures.count) of \(result.succeeded + result.failures.count) JPG files could not be saved. First failure: \(firstFailure.fileName): \(firstFailure.message)",
                    )
                }
            }
        }
    }

    func startScanAndExtractJPGs() {
        Logger.process.debugMessageOnly("FileOperationsModel.startScanAndExtractJPGs()")
        guard let workspace else { return }
        let extractionFiles = workspace.activeCatalogFiles
        guard currentScanAndExtractJPGsActor == nil,
              workspace.catalog.currentScanAndCreateThumbnailsActor == nil,
              currentExtractAndSaveJPGsActor == nil,
              !extractionFiles.isEmpty
        else { return }

        jpgCacheWarmTask?.cancel()

        fileOperationCompleted = 0
        fileOperationTotal = extractionFiles.count
        fileOperationEstimatedSeconds = 0
        workspace.catalog.isCreatingThumbnails = true

        let handlers = CreateFileHandlers().createFileHandlers(
            fileHandler: fileHandler,
            maxfilesHandler: maxfilesHandler,
            estimatedTimeHandler: estimatedTimeHandler,
            memorypressurewarning: { _ in },
            onExtractionNeeded: {},
        )

        let actor = ScanAndExtractJPGs(urls: extractionFiles.map(\.url))
        currentScanAndExtractJPGsActor = actor

        let access = RawCullCatalogAccess.shared.retainAccess(for: extractionFiles.map(\.url))
        jpgCacheWarmTask = Task(priority: .background) {
            defer { withExtendedLifetime(access) {} }
            await actor.setFileHandlers(handlers)
            await actor.extractCatalogJPGs()

            await MainActor.run {
                guard self.currentScanAndExtractJPGsActor === actor else { return }
                self.currentScanAndExtractJPGsActor = nil
                self.jpgCacheWarmTask = nil
                workspace.catalog.isCreatingThumbnails = false
            }
        }
    }

    /// Cancels JPG export and the JPG cache warm-up. Catalog loading is
    /// cancelled by the workspace's `abort()`.
    func cancelJPGOperations() {
        if let actor = currentExtractAndSaveJPGsActor {
            Task { await actor.cancelExtractJPGSTask() }
        }
        currentExtractAndSaveJPGsActor = nil

        cancelJPGCacheWarming()
    }

    /// Cancels the JPG cache warm-up only; used when the catalog changes.
    func cancelJPGCacheWarming() {
        jpgCacheWarmTask?.cancel()
        jpgCacheWarmTask = nil

        if let actor = currentScanAndExtractJPGsActor {
            Task { await actor.cancelExtraction() }
        }
        currentScanAndExtractJPGsActor = nil
    }
}
