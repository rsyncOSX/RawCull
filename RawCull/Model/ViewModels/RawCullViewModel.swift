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
        initialSource: .embeddedJPG,
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

    @ObservationIgnored var zoomNavigationCache: ZoomNavigationProjection?
    @ObservationIgnored var zoomNavigationBuildCount = 0
    @ObservationIgnored var gridProjectionCache: CullingGridProjection?
    @ObservationIgnored var gridProjectionBuildCount = 0

    /// The open catalog: sources, files, sorted and filtered projection, scan progress.
    let catalog = CatalogWorkspace()

    var selectedFile: FileItem? {
        catalog.file(withID: selection.selectedFileID)
    }

    /// Main content mode — drives which view fills the main window.
    var mainViewMode: MainViewMode = .loupe
    var canShowThumbnailWorkspace: Bool {
        catalog.selectedSource != nil
    }

    var showsDetailedBurstComparison = false
    var showsBurstGroups: Bool {
        mainViewMode == .similarityGrid && similarityModel.burstModeActive
    }

    /// In-window zoom overlay state.
    let zoomOverlay = ZoomOverlayModel()

    /// Pan and zoom of the main loupe image.
    let loupeViewport = LoupeViewportModel()

    /// Sheets, alerts, banners and menu-command flags of the main window.
    let presentation = WorkspacePresentationModel()

    /// JPG extraction, JPG cache warming and file-operation progress.
    let fileOperations = FileOperationsModel()

    /// Culling store, rating lookup and rating filter.
    let ratings = RatingsModel()

    /// Current file, multi-selection, comparison set and rendered grid order.
    let selection = SelectionModel()

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

    @ObservationIgnored var similarityCatalogGeneration: UInt64 = 0
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
        fileOperations.bind(self)
    }

    // MARK: - Computed

    // MARK: - Zoom

    func openZoomOverlay(
        navigationIDs: [FileItem.ID]? = nil,
        initialSource: ImagePreviewSource = .embeddedJPG,
        initialZoomMode: ZoomOverlayInitialZoomMode = .fit,
        showFocusPointsOnOpen: Bool = false,
    ) {
        Logger.process.debugMessageOnly("RawCullViewModel.openZoomOverlay()")
        zoomOverlay.open(
            axis: mainViewMode == .loupe ? .vertical : .horizontal,
            navigationIDs: navigationIDs,
            initialSource: initialSource,
            initialZoomMode: initialZoomMode,
            showFocusPointsOnOpen: showFocusPointsOnOpen,
        )
    }

    func closeZoomOverlay() {
        Logger.process.debugMessageOnly("RawCullViewModel.closeZoomOverlay()")
        zoomOverlay.close()
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

    // MARK: - Focus Points

    func getFocusPoints() -> [FocusPoint]? {
        // Logger.process.debugMessageOnly("RawCullViewModel.getFocusPoints()")
        guard let imageName = selectedFile?.name else { return nil }
        let points = catalog.focusPoints?
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
