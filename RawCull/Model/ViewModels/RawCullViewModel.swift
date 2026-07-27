import Foundation
import Observation
import OSAKit
import OSLog
import RawCullCore

enum AlertType {
    case createJPGDiskCache
    case clearRatedFiles
}

enum RatingFilter: Hashable {
    case all
    case rejected // rating == -1
    case keepers // rating == 0
    case stars(Int) // rating == n, n in 2...5
}

enum MainViewMode: String, CaseIterable, Identifiable {
    case loupe
    case grid
    case similarityGrid
    case ratedGrid
    case comparisonGrid

    var id: String {
        rawValue
    }
}

enum ZoomOverlayNavigationAxis: Equatable {
    case vertical
    case horizontal
}

enum ZoomOverlayInitialZoomMode: Equatable {
    case fit
    case actualPixels
}

struct ZoomOverlayLaunchContext: Equatable {
    var initialSource: ImagePreviewSource
    var initialZoomMode: ZoomOverlayInitialZoomMode
    var showFocusPointsOnOpen: Bool

    static let `default` = ZoomOverlayLaunchContext(
        initialSource: .thumbnail,
        initialZoomMode: .fit,
        showFocusPointsOnOpen: false,
    )
}

enum ActiveSheet: String, Identifiable {
    case stats
    case scoringParams
    case extractJPGs

    var id: String {
        rawValue
    }
}

struct RawDiagnosticsPresentation: Identifiable {
    let id = UUID()
    let log: String
}

struct OperationFailurePresentation: Identifiable {
    let id = UUID()
    let title: String
    let message: String
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
    var selectedFile: FileItem? {
        files.first { $0.id == selectedFileID }
    }

    var selectedFileIDs: Set<FileItem.ID> = []
    var issorting: Bool = false
    var progress: Double = 0
    var max: Double = 0
    var estimatedSeconds: Int = 0
    var creatingthumbnails: Bool = false
    var scanning: Bool = true
    var showingAlert: Bool = false

    var focusaborttask: Bool = false
    var focusExtractJPGs: Bool = false
    var extractJPGExportMode: ExtractJPGExportMode = .embeddedJPG
    var extractJPGDestination: ARWSourceCatalog?

    var showcopyARWFilesView: Bool = false
    var alertType: AlertType?
    var sheetType: SheetType? = .copytasksview
    var remotedatanumbers: RemoteDataNumbers?
    var ratingFilter: RatingFilter = .all

    // Zoom window state
    var zoomCGImageWindowFocused: Bool = false
    var zoomNSImageWindowFocused: Bool = false

    /// Main content mode — drives which view fills the main window.
    var mainViewMode: MainViewMode = .loupe
    var comparisonFileIDs: [FileItem.ID] = []
    var showsBurstGroups: Bool {
        mainViewMode == .similarityGrid && similarityModel.burstModeActive
    }

    // In-window zoom overlay (replaces the old separate zoom windows).
    var zoomOverlayVisible: Bool = false
    var zoomOverlayNavigationAxis: ZoomOverlayNavigationAxis = .horizontal
    var zoomOverlayNavigationContext: ZoomOverlayNavigationContext?
    var zoomOverlayLaunchContext: ZoomOverlayLaunchContext = .default
    var zoomOverlayCGImage: CGImage?
    var zoomOverlayNSImage: NSImage?

    // Thumbnail preview zoom state
    var scale: CGFloat = 1.0
    var lastScale: CGFloat = 1.0
    var offset: CGSize = .zero
    var lastOffset: CGSize = .zero

    /// This is the only place CullingModel is initialised.
    var cullingModel = CullingModel()

    /// Single shared instance — config changes here affect both the zoom
    /// overlay and the sharpness scoring pipeline.
    var sharpnessModel = SharpnessScoringModel()

    /// Similarity scoring model — PhotoAIKit artifacts with RawCull-owned ranking policy.
    var similarityModel: SimilarityScoringModel

    /// Dedicated SAM 3 burst-review feature. It owns the in-process workflow
    /// and typed operation state; the central view model only adapts inputs and
    /// applies a user-confirmed recommendation.
    let deepAIReviewFeature: DeepAIReviewFeature

    /// Intelligent burst culling analysis state.
    var burstAnalysisResults: [Int: BurstAnalysisResult] = [:]
    var burstAnalysisProgress = BurstAnalysisProgress()
    var burstReviewStates: [Int: BurstReviewState] = [:]
    var burstReviewQueueFilter: BurstReviewQueueFilter = .all
    var activeBurstComparisonGroupID: Int?
    var lastBurstUndoEntry: BurstUndoEntry?

    /// Currently selected catalog for which startAccessingSecurityScopedResource()
    /// has succeeded. Access is scoped to the active catalog, not every catalog
    /// ever added to the sidebar.
    @ObservationIgnored private var activeSecurityScopedURL: URL?

    @ObservationIgnored var startSecurityScopedResource: @MainActor (URL) -> Bool = {
        $0.startAccessingSecurityScopedResource()
    }

    @ObservationIgnored var stopSecurityScopedResource: @MainActor (URL) -> Void = {
        $0.stopAccessingSecurityScopedResource()
    }

    /// URLs whose thumbnails have already been preloaded — skip on revisit.
    @ObservationIgnored var processedURLs: Set<URL> = []

    var memoryPressureWarning: Bool = false

    /// O(1) lookup: filename → rating for the current source catalog.
    /// Rebuilt by rebuildRatingCache() after any culling state change.
    var ratingCache: [String: Int] = [:]

    /// Filenames that have an explicit record in the current catalog.
    var taggedNamesCache: Set<String> = []

    /// Focus points created by exiftool, if available.
    var focusPoints: [FocusPointsModel]?

    var showSavedFiles: Bool = false

    /// Sheet currently presented from the main window toolbar
    /// (Scoring Parameters / Scan Statistics). Nil when no sheet is shown.
    var activeSheet: ActiveSheet?

    var rawDiagnosticsPresentation: RawDiagnosticsPresentation?
    var operationFailurePresentation: OperationFailurePresentation?

    /// Closure to count scanning files
    var countingScannedFiles: (@Sendable (Int) -> Void)?

    var currentScanAndCreateThumbnailsActor: ScanAndCreateThumbnails?
    var currentExtractAndSaveJPGsActor: ExtractAndSaveJPGs?
    var currentScanAndExtractJPGsActor: ScanAndExtractJPGs?
    var preloadTask: Task<Void, Never>?
    @ObservationIgnored var jpgCacheWarmTask: Task<Void, Never>?
    @ObservationIgnored var catalogLoadTask: Task<Void, Never>?
    @ObservationIgnored var similarityHydrationTask: Task<Void, Never>?
    @ObservationIgnored var activeCatalogLoadURL: URL?
    /// In-flight ARW→JPEG extraction or thumbnail load task for the zoom window.
    /// Cancelled when the zoom window closes or a new file is opened for zoom.
    var zoomExtractionTask: Task<Void, Never>?
    @ObservationIgnored var burstAnalysisTask: Task<Void, Never>?
    @ObservationIgnored var burstAnalysisGeneration: Int = 0
    @ObservationIgnored var completedBurstAnalysisContext: CompletedBurstAnalysisContext?
    @ObservationIgnored var burstAnalysisCache = BurstAnalysisCache.shared
    @ObservationIgnored var burstAnalysisCacheLoad: @MainActor (
        URL,
        [FileItem],
        Int,
        BurstSharpnessSignature,
        BurstSimilaritySignature,
    ) async -> BurstAnalysisCacheSnapshot? = {
        catalog,
        files,
        thumbnailMaxPixelSize,
        sharpnessSignature,
        similaritySignature in
        await BurstAnalysisCache.shared.load(
            catalog: catalog,
            files: files,
            thumbnailMaxPixelSize: thumbnailMaxPixelSize,
            sharpnessSignature: sharpnessSignature,
            similaritySignature: similaritySignature,
        )
    }
    @ObservationIgnored var burstAnalysisMigrationLoad: @MainActor (
        URL
    ) async -> BurstAnalysisCacheSnapshot? = { catalog in
        await BurstAnalysisCache.shared.loadMigrationCandidate(catalog: catalog)
    }

    @ObservationIgnored var burstAnalysisCacheSave: @MainActor (
        BurstAnalysisCacheSnapshot,
        URL,
    ) async -> Void = { snapshot, catalog in
        await BurstAnalysisCache.shared.save(snapshot, catalog: catalog)
    }

    init(
        similarityService: any RawCullSimilarityServicing = RawCullVisionSimilarityService(),
        similarityArtifactStore: PerFileAnalysisArtifactStore = .shared,
        deepAIReviewFeature: DeepAIReviewFeature = DeepAIReviewFeature(),
    ) {
        self.similarityModel = SimilarityScoringModel(
            similarityService: similarityService,
            artifactStore: similarityArtifactStore,
        )
        self.deepAIReviewFeature = deepAIReviewFeature
    }

    func setSimilarityService(_ service: any RawCullSimilarityServicing) {
        guard similarityModel.backendDescriptor != service.backendDescriptor
            || similarityModel.artifactBackendDescriptors != service.artifactBackendDescriptors
        else { return }

        cancelAndResetBurstAnalysis()
        similarityModel.setSimilarityService(service)
        similarityHydrationTask?.cancel()
        let currentFiles = files
        similarityHydrationTask = Task { [weak self] in
            guard let self else { return }
            await self.similarityModel.hydrateArtifacts(currentFiles)
            guard !Task.isCancelled else { return }
            self.similarityHydrationTask = nil
        }
    }

    // MARK: - Computed

    var alertTitle: String {
        switch alertType {
        case .createJPGDiskCache: "Create JPG Disk Cache"
        case .clearRatedFiles: "Clear Rated Images"
        case .none: ""
        }
    }

    var alertMessage: String {
        switch alertType {
        case .createJPGDiskCache:
            "RawCull will create missing extracted JPG preview cache images for \(files.count) RAW files in this catalog. Existing cached images will be skipped."

        case .clearRatedFiles: "Are you sure you want to clear all rated images?"

        case .none: ""
        }
    }

    // MARK: - Zoom

    func resetZoom() {
        scale = 1.0
        lastScale = 1.0
        offset = .zero
        lastOffset = .zero
    }

    func openZoomOverlay(
        navigationIDs: [FileItem.ID]? = nil,
        initialSource: ImagePreviewSource = .thumbnail,
        initialZoomMode: ZoomOverlayInitialZoomMode = .fit,
        showFocusPointsOnOpen: Bool = false,
    ) {
        zoomOverlayNavigationAxis = mainViewMode == .loupe ? .vertical : .horizontal
        zoomOverlayNavigationContext = navigationIDs.map(ZoomOverlayNavigationContext.init(orderedFileIDs:))
        zoomOverlayLaunchContext = ZoomOverlayLaunchContext(
            initialSource: initialSource,
            initialZoomMode: initialZoomMode,
            showFocusPointsOnOpen: showFocusPointsOnOpen,
        )
        zoomOverlayVisible = true
    }

    func closeZoomOverlay() {
        zoomExtractionTask?.cancel()
        zoomExtractionTask = nil
        zoomOverlayVisible = false
        zoomOverlayNavigationContext = nil
        zoomOverlayLaunchContext = .default
        zoomOverlayCGImage = nil
        zoomOverlayNSImage = nil
    }

    // MARK: - File Selection

    func selectMainViewMode(_ mode: MainViewMode) {
        closeZoomOverlay()
        if mode != .similarityGrid {
            similarityModel.burstModeActive = false
        }
        mainViewMode = mode
    }

    func selectFile(_ file: FileItem) {
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

    /// Starts access for the active catalog, stopping any previously active
    /// catalog first. Re-selecting the same active catalog is a no-op.
    @discardableResult
    func startSecurityScopedAccess(for url: URL) -> Bool {
        if activeSecurityScopedURL == url {
            return true
        }

        stopActiveSecurityScopedAccess()

        guard startSecurityScopedResource(url) else {
            return false
        }

        activeSecurityScopedURL = url
        return true
    }

    func hasActiveSecurityScopedAccess(for url: URL) -> Bool {
        activeSecurityScopedURL == url
    }

    func stopActiveSecurityScopedAccess() {
        guard let url = activeSecurityScopedURL else { return }
        stopSecurityScopedResource(url)
        activeSecurityScopedURL = nil
    }

    isolated deinit {
        stopActiveSecurityScopedAccess()
    }
}
