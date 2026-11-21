import Foundation
import Observation
import RawCullCore

/// The workspace operations the burst workflow needs that span several slices.
/// The workspace root implements this; the controller holds it weakly.
@MainActor
protocol BurstWorkflowHost: AnyObject {
    var activeCatalogFiles: [FileItem] { get }
    var hasActiveSemanticSearchSelection: Bool { get }
    func hasRating(in files: [FileItem]) -> Bool
    func updateRating(for files: [FileItem], rating: Int)
    func updateRating(for file: FileItem, rating: Int)
    func refreshCullingDerivedState()
    func handleSortOrderChange() async
    func applyBurstSharpnessScoringSideEffects(_ files: [FileItem]) async
}

/// Owns burst analysis and review: starting, reindexing and regrouping the
/// analysis, the review queue and review states, keep-best and undo, cache
/// persistence.
@Observable @MainActor
final class BurstWorkflowController {
    @ObservationIgnored let navigation: WorkspaceNavigationModel
    @ObservationIgnored let catalog: CatalogWorkspace
    @ObservationIgnored let selection: SelectionModel
    @ObservationIgnored let ratings: RatingsModel
    @ObservationIgnored let sharpnessModel: SharpnessScoringModel
    @ObservationIgnored let similarityFeature: RawCullSimilarityFeature
    @ObservationIgnored let similarityModel: SimilarityScoringModel
    @ObservationIgnored private weak var weakHost: (any BurstWorkflowHost)?

    /// Stable worker boundary for burst cache and compute orchestration.
    @ObservationIgnored let burstAnalysisCoordinator: BurstAnalysisCoordinator

    /// Stable application session; viewport/image state has a separate owner.
    let burstReviewSession = BurstReviewSessionModel()

    var burstFullReindexRequest: BurstFullReindexRequest?
    var isPreparingBurstCatalog = false
    @ObservationIgnored var burstCatalogPreparationGeneration = 0
    @ObservationIgnored var completedBurstAnalysisContext: CompletedBurstAnalysisContext?
    var showsDetailedBurstComparison = false

    init(
        navigation: WorkspaceNavigationModel,
        catalog: CatalogWorkspace,
        selection: SelectionModel,
        ratings: RatingsModel,
        sharpnessModel: SharpnessScoringModel,
        similarityFeature: RawCullSimilarityFeature,
        similarityModel: SimilarityScoringModel,
        cacheRepository: any BurstAnalysisCacheRepository,
    ) {
        self.navigation = navigation
        self.catalog = catalog
        self.selection = selection
        self.ratings = ratings
        self.sharpnessModel = sharpnessModel
        self.similarityFeature = similarityFeature
        self.similarityModel = similarityModel
        burstAnalysisCoordinator = BurstAnalysisCoordinator(
            sharpnessModel: sharpnessModel,
            similarityFeature: similarityFeature,
            similarityModel: similarityModel,
            cacheRepository: cacheRepository,
        )
    }

    func bind(host: any BurstWorkflowHost) {
        weakHost = host
    }

    /// The host for callbacks that may run after the workspace is gone.
    var weakHostForCallbacks: (any BurstWorkflowHost)? {
        weakHost
    }

    /// The workspace root; it outlives this controller, which it owns.
    var host: any BurstWorkflowHost {
        guard let weakHost else { preconditionFailure("BurstWorkflowController used before bind(host:)") }
        return weakHost
    }

    // MARK: Review session state

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
}
