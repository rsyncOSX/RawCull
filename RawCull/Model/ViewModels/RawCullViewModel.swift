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
    case aiAnalysis
    case combinedReview

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

struct OperationFailurePresentation: Identifiable {
    let id = UUID()
    let title: String
    let message: String
}

@Observable @MainActor
final class RawCullViewModel: DeepAIReviewApplicationContext {
    /// Owns catalog transitions, scan task lifetime, and security-scoped access.
    @ObservationIgnored let catalogLifecycle = CatalogLifecycleCoordinator()

    var sources: [ARWSourceCatalog] = []
    var selectedSource: ARWSourceCatalog?
    var files: [FileItem] = [] {
        didSet {
            catalogContentRevision &+= 1
            zoomNavigationCache = nil
        }
    }

    private(set) var catalogContentRevision: UInt64 = 0
    private(set) var zoomContextRevision: UInt64 = 0
    @ObservationIgnored var zoomNavigationCache: ZoomNavigationProjection?
    @ObservationIgnored var zoomNavigationBuildCount = 0
    private(set) var gridContentRevision: UInt64 = 0
    @ObservationIgnored var gridProjectionCache: CullingGridProjection?
    @ObservationIgnored var gridProjectionBuildCount = 0
    var filteredFiles: [FileItem] = [] {
        didSet { gridContentRevision &+= 1 }
    }

    var searchText = ""
    var selectedFileID: FileItem.ID?
    var previouslySelectedFileID: FileItem.ID?
    @ObservationIgnored var sortGeneration: UInt64 = 0
    @ObservationIgnored var sortFiles: @MainActor (
        [FileItem], FileItemSortDescriptor, String,
    ) async -> [FileItem] = { files, order, text in
        await ScanFiles.sortFiles(files, by: order, searchText: text)
    }

    var sortOrder = FileItemSortDescriptor()
    var isShowingPicker = false
    var showsLoupeMetadataPanel = true
    var selectedFile: FileItem? {
        files.first { $0.id == selectedFileID }
    }

    var selectedFileIDs: Set<FileItem.ID> = []
    /// Ordered IDs currently rendered by the culling grid. Keyboard and loupe
    /// navigation use this projection so hidden burst frames cannot become targets.
    var cullingGridRenderedFileIDs: [FileItem.ID] = []
    var isSorting: Bool = false
    /// Number of RAW files discovered by the active catalog scan. This is
    /// reset with the catalog working set and is the source of truth for the
    /// scanning progress label.
    @ObservationIgnored var metadataProgress: CatalogProgressCoalescer<Int>?
    @ObservationIgnored var thumbnailProgress: CatalogProgressCoalescer<CatalogThumbnailProgress>?
    var scanDiscoveredCount: Int = 0
    var fileOperationCompleted: Int = 0
    var fileOperationTotal: Int = 0
    var fileOperationEstimatedSeconds: Int = 0
    var isCreatingThumbnails: Bool = false
    var scanning: Bool = true
    var showingAlert: Bool = false

    var focusAbortTask: Bool = false
    var focusExtractJPGs: Bool = false
    var focusCopyTaggedFiles: Bool = false
    var extractJPGExportMode: ExtractJPGExportMode = .embeddedJPG
    var extractJPGSelectedOnly = true
    var extractJPGDestination: ARWSourceCatalog?

    var showCopyARWFilesView: Bool = false
    var alertType: AlertType?
    var sheetType: SheetType? = .copytasksview
    var remoteDataNumbers: RemoteDataNumbers?
    var ratingFilter: RatingFilter = .all

    // Zoom window state
    var zoomCGImageWindowFocused: Bool = false
    var zoomNSImageWindowFocused: Bool = false

    /// Main content mode — drives which view fills the main window.
    var mainViewMode: MainViewMode = .loupe
    var canShowThumbnailWorkspace: Bool {
        selectedSource != nil
    }

    var showsDetailedBurstComparison = false
    var comparisonFileIDs: [FileItem.ID] = []
    var showsBurstGroups: Bool {
        mainViewMode == .similarityGrid && similarityModel.burstModeActive
    }

    // In-window zoom overlay (replaces the old separate zoom windows).
    var zoomOverlayVisible: Bool = false
    var zoomOverlayNavigationAxis: ZoomOverlayNavigationAxis = .horizontal
    var zoomOverlayNavigationContext: ZoomOverlayNavigationContext? {
        didSet { zoomContextRevision &+= 1 }
    }

    var zoomOverlayLaunchContext: ZoomOverlayLaunchContext = .default
    var zoomOverlayCGImage: CGImage?
    var zoomOverlayAnalysisCGImage: CGImage?
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

    /// Stable feature boundary for image-similarity work and presentation.
    let similarityFeature: RawCullSimilarityFeature

    /// Shared state used by culling commands and burst-analysis coordination.
    let similarityModel: SimilarityScoringModel

    /// Semantic-only presentation and actions backed by `similarityModel`.
    let semanticSearchFeature: RawCullSemanticSearchFeature

    /// Runtime-owned optional Deep Review capability. The central view model only
    /// supplies application burst evidence, resets catalog-scoped state, and applies
    /// a user-confirmed recommendation.
    let deepAIReviewController: DeepAIReviewController

    /// Stable worker boundary for burst cache and compute orchestration.
    @ObservationIgnored let burstAnalysisCoordinator: BurstAnalysisCoordinator

    /// Stable application session; viewport/image state has a separate owner.
    let burstReviewSession = BurstReviewSessionModel()

    var burstAnalysisResults: [Int: BurstAnalysisResult] {
        burstReviewSession.results
    }

    var burstAnalysisProgress: BurstAnalysisProgress {
        burstAnalysisCoordinator.progress
    }

    var burstAnalysisGeneration: Int {
        burstAnalysisCoordinator.generation
    }

    var burstReviewStates: [Int: BurstReviewState] {
        burstReviewSession.reviewStates
    }

    var burstReviewQueueFilter: BurstReviewQueueFilter {
        get { burstReviewSession.queueFilter }
        set { burstReviewSession.queueFilter = newValue }
    }

    var activeBurstComparisonGroupID: Int? {
        get { burstReviewSession.activeComparisonGroupID }
        set { burstReviewSession.activeComparisonGroupID = newValue }
    }

    var lastBurstUndoEntry: BurstUndoEntry? {
        get { burstReviewSession.lastUndoEntry }
        set { burstReviewSession.lastUndoEntry = newValue }
    }

    var burstFullReindexRequest: BurstFullReindexRequest?
    var isPreparingBurstCatalog = false
    @ObservationIgnored var burstCatalogPreparationGeneration = 0

    /// URLs whose thumbnails have already been preloaded — skip on revisit.
    @ObservationIgnored var processedURLs: Set<URL> = []

    var memoryPressureWarning: Bool = false

    /// O(1) lookup: filename → rating for the current source catalog.
    /// Rebuilt by rebuildRatingCache() after any culling state change.
    var ratingCache: [String: Int] = [:] {
        didSet { gridContentRevision &+= 1 }
    }

    /// Filenames that have an explicit record in the current catalog.
    var taggedNamesCache: Set<String> = []

    /// Focus points created by exiftool, if available.
    var focusPoints: [FocusPointsModel]?

    /// Sheet currently presented from the main window toolbar
    /// (Scoring Parameters / Scan Statistics). Nil when no sheet is shown.
    var activeSheet: ActiveSheet?

    var operationFailurePresentation: OperationFailurePresentation?

    var currentScanAndCreateThumbnailsActor: ScanAndCreateThumbnails?
    var currentExtractAndSaveJPGsActor: ExtractAndSaveJPGs?
    var currentScanAndExtractJPGsActor: ScanAndExtractJPGs?
    var preloadTask: Task<Void, Never>?
    @ObservationIgnored var jpgCacheWarmTask: Task<Void, Never>?
    @ObservationIgnored var similarityCatalogGeneration: UInt64 = 0
    /// Full name-sorted/search-filtered catalog projection before rating,
    /// sharpness, and similarity filters are applied.
    @ObservationIgnored var catalogDisplayCandidates: [FileItem] = []
    /// In-flight ARW→JPEG extraction or thumbnail load task for the zoom window.
    /// Cancelled when the zoom window closes or a new file is opened for zoom.
    var zoomExtractionTask: Task<Void, Never>?
    @ObservationIgnored var completedBurstAnalysisContext: CompletedBurstAnalysisContext?
    init(
        similarityModel: SimilarityScoringModel,
        similarityFeature: RawCullSimilarityFeature,
        semanticSearchFeature: RawCullSemanticSearchFeature,
        deepAIReviewController: DeepAIReviewController,
        burstAnalysisCacheRepository: any BurstAnalysisCacheRepository
            = LiveBurstAnalysisCacheRepository(),
    ) {
        Logger.process.debugMessageOnly("RawCullViewModel.init()")
        let sharpnessModel = SharpnessScoringModel()
        self.sharpnessModel = sharpnessModel
        self.similarityFeature = similarityFeature
        self.similarityModel = similarityModel
        self.semanticSearchFeature = semanticSearchFeature
        self.deepAIReviewController = deepAIReviewController
        burstAnalysisCoordinator = BurstAnalysisCoordinator(
            sharpnessModel: sharpnessModel,
            similarityFeature: similarityFeature,
            similarityModel: similarityModel,
            cacheRepository: burstAnalysisCacheRepository,
        )

        assert(similarityFeature.sharesSimilarityModelIdentity(with: similarityModel))
        assert(
            semanticSearchFeature.sharesSimilarityModelIdentity(
                with: similarityModel,
            ),
        )
        similarityFeature.bindApplicationContext(self)
        deepAIReviewController.bindApplicationContext(self)
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
        Logger.process.debugMessageOnly("RawCullViewModel.resetZoom()")
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
        Logger.process.debugMessageOnly("RawCullViewModel.openZoomOverlay()")
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
        Logger.process.debugMessageOnly("RawCullViewModel.closeZoomOverlay()")
        zoomExtractionTask?.cancel()
        zoomExtractionTask = nil
        zoomOverlayVisible = false
        zoomOverlayNavigationContext = nil
        zoomOverlayLaunchContext = .default
        zoomOverlayCGImage = nil
        zoomOverlayAnalysisCGImage = nil
        zoomOverlayNSImage = nil
    }

    // MARK: - File Selection

    func selectMainViewMode(_ mode: MainViewMode) {
        Logger.process.debugMessageOnly("RawCullViewModel.selectMainViewMode()")
        closeZoomOverlay()
        if mode != .similarityGrid {
            similarityModel.burstModeActive = false
        }
        mainViewMode = mode
    }

    func selectFile(_ file: FileItem) {
        Logger.process.debugMessageOnly("RawCullViewModel.selectFile()")
        selectedFileID = file.id
    }

    // MARK: - Focus Points

    func getFocusPoints() -> [FocusPoint]? {
        // Logger.process.debugMessageOnly("RawCullViewModel.getFocusPoints()")
        guard let imageName = selectedFile?.name else { return nil }
        let points = focusPoints?
            .filter { $0.sourceFile == imageName }
            .flatMap(\.focusPoints) ?? []
        return points.isEmpty ? nil : points
    }

    // MARK: - Catalog access used by application workflows

    @discardableResult
    func startSecurityScopedAccess(for url: URL) -> Bool {
        catalogLifecycle.startSecurityScopedAccess(for: url)
    }

    func hasActiveSecurityScopedAccess(for url: URL) -> Bool {
        catalogLifecycle.hasActiveSecurityScopedAccess(for: url)
    }

    func stopActiveSecurityScopedAccess() {
        catalogLifecycle.stopActiveSecurityScopedAccess()
    }
}
