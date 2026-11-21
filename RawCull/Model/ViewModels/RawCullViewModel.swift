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
final class RawCullViewModel {
    /// Owns catalog transitions, scan task lifetime, and security-scoped access.
    @ObservationIgnored let catalogLifecycle = CatalogLifecycleCoordinator()

    /// The open catalog: sources, files, sorted and filtered projection, scan progress.
    let catalog: CatalogWorkspace

    var selectedFile: FileItem? {
        catalog.file(withID: selection.selectedFileID)
    }

    /// Main view mode and opening or closing the zoom overlay.
    let navigation: WorkspaceNavigationModel

    /// In-window zoom overlay state.
    let zoomOverlay: ZoomOverlayModel

    /// Pan and zoom of the main loupe image.
    let loupeViewport = LoupeViewportModel()

    /// Sheets, alerts, banners and menu-command flags of the main window.
    let presentation = WorkspacePresentationModel()

    /// JPG extraction, JPG cache warming and file-operation progress.
    let fileOperations = FileOperationsModel()

    /// Culling store, rating lookup and rating filter.
    let ratings: RatingsModel

    /// Current file, multi-selection, comparison set and rendered grid order.
    let selection: SelectionModel

    /// Single shared instance — config changes here affect both the zoom
    /// overlay and the sharpness scoring pipeline.
    let sharpnessModel: SharpnessScoringModel

    /// Stable feature boundary for image-similarity work and presentation.
    let similarityFeature: RawCullSimilarityFeature

    /// Shared state used by culling commands and burst-analysis coordination.
    let similarityModel: SimilarityScoringModel

    /// Semantic-only presentation and actions backed by `similarityModel`.
    let semanticSearchFeature: RawCullSemanticSearchFeature

    /// Subject masks from Review results, for the subject outline and mask badge.
    let subjectMasks: ReviewSubjectMasks

    /// Burst analysis, review queue, keep-best and undo.
    let burstWorkflow: BurstWorkflowController

    /// Catalog loading, sorting, filtering, scoring and semantic selection.
    let catalogController: CatalogController

    /// Rating updates, clearing and culling-store recovery.
    let culling: CullingController

    init(
        similarityModel: SimilarityScoringModel,
        similarityFeature: RawCullSimilarityFeature,
        semanticSearchFeature: RawCullSemanticSearchFeature,
        subjectMasks: ReviewSubjectMasks = ReviewSubjectMasks(),
        burstAnalysisCacheRepository: any BurstAnalysisCacheRepository
            = LiveBurstAnalysisCacheRepository(),
        sharpnessModel: SharpnessScoringModel = SharpnessScoringModel(),
    ) {
        Logger.process.debugMessageOnly("RawCullViewModel.init()")
        let catalog = CatalogWorkspace()
        let zoomOverlay = ZoomOverlayModel()
        self.zoomOverlay = zoomOverlay
        let ratings = RatingsModel()
        let selection = SelectionModel()
        self.catalog = catalog
        self.ratings = ratings
        self.selection = selection
        self.sharpnessModel = sharpnessModel
        self.similarityFeature = similarityFeature
        self.similarityModel = similarityModel
        self.semanticSearchFeature = semanticSearchFeature
        self.subjectMasks = subjectMasks
        navigation = WorkspaceNavigationModel(
            zoomOverlay: zoomOverlay, catalog: catalog, similarityModel: similarityModel,
        )
        burstWorkflow = BurstWorkflowController(
            navigation: navigation,
            catalog: catalog,
            selection: selection,
            ratings: ratings,
            sharpnessModel: sharpnessModel,
            similarityFeature: similarityFeature,
            similarityModel: similarityModel,
            cacheRepository: burstAnalysisCacheRepository,
        )

        catalogController = CatalogController(
            catalogLifecycle: catalogLifecycle,
            catalog: catalog,
            selection: selection,
            ratings: ratings,
            presentation: presentation,
            fileOperations: fileOperations,
            navigation: navigation,
            zoomOverlay: zoomOverlay,
            burstWorkflow: burstWorkflow,
            sharpnessModel: sharpnessModel,
            similarityFeature: similarityFeature,
            similarityModel: similarityModel,
            semanticSearchFeature: semanticSearchFeature,
        )
        culling = CullingController(catalogController: catalogController)

        assert(similarityFeature.sharesSimilarityModelIdentity(with: similarityModel))
        assert(
            semanticSearchFeature.sharesSimilarityModelIdentity(
                with: similarityModel,
            ),
        )
        similarityFeature.bindApplicationContext(catalogController)
        fileOperations.bind(catalogController)
        burstWorkflow.bind(host: culling)
    }

    // MARK: - Computed

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
