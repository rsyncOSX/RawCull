import Foundation
import Observation
import OSLog
import RawCullCore

/// Catalog operations: loading and switching catalogs, sorting and filtering
/// the catalog projection, sharpness scoring targets and persistence,
/// similarity and semantic-search selection, and AI-analysis input.
///
/// The state lives in the slices it takes in `init`; this type only
/// orchestrates them.
@Observable @MainActor
final class CatalogController: FileOperationsCatalog {
    @ObservationIgnored let catalogLifecycle: CatalogLifecycleCoordinator
    @ObservationIgnored let catalog: CatalogWorkspace
    @ObservationIgnored let selection: SelectionModel
    @ObservationIgnored let ratings: RatingsModel
    @ObservationIgnored let presentation: WorkspacePresentationModel
    @ObservationIgnored let fileOperations: FileOperationsModel
    @ObservationIgnored let navigation: WorkspaceNavigationModel
    @ObservationIgnored let zoomOverlay: ZoomOverlayModel
    @ObservationIgnored let burstWorkflow: BurstWorkflowController
    @ObservationIgnored let sharpnessModel: SharpnessScoringModel
    @ObservationIgnored let similarityFeature: RawCullSimilarityFeature
    @ObservationIgnored let similarityModel: SimilarityScoringModel
    @ObservationIgnored let semanticSearchFeature: RawCullSemanticSearchFeature

    // Projection memoization; not presentation state, so never observed.
    @ObservationIgnored var zoomNavigationCache: ZoomNavigationProjection?
    @ObservationIgnored var zoomNavigationBuildCount = 0
    @ObservationIgnored var gridProjectionCache: CullingGridProjection?
    @ObservationIgnored var gridProjectionBuildCount = 0

    /// Advances when the catalog the similarity feature works on changes.
    @ObservationIgnored var similarityCatalogGeneration: UInt64 = 0

    init(
        catalogLifecycle: CatalogLifecycleCoordinator,
        catalog: CatalogWorkspace,
        selection: SelectionModel,
        ratings: RatingsModel,
        presentation: WorkspacePresentationModel,
        fileOperations: FileOperationsModel,
        navigation: WorkspaceNavigationModel,
        zoomOverlay: ZoomOverlayModel,
        burstWorkflow: BurstWorkflowController,
        sharpnessModel: SharpnessScoringModel,
        similarityFeature: RawCullSimilarityFeature,
        similarityModel: SimilarityScoringModel,
        semanticSearchFeature: RawCullSemanticSearchFeature,
    ) {
        self.catalogLifecycle = catalogLifecycle
        self.catalog = catalog
        self.selection = selection
        self.ratings = ratings
        self.presentation = presentation
        self.fileOperations = fileOperations
        self.navigation = navigation
        self.zoomOverlay = zoomOverlay
        self.burstWorkflow = burstWorkflow
        self.sharpnessModel = sharpnessModel
        self.similarityFeature = similarityFeature
        self.similarityModel = similarityModel
        self.semanticSearchFeature = semanticSearchFeature
    }

    var selectedFile: FileItem? {
        catalog.file(withID: selection.selectedFileID)
    }

    func stopActiveSecurityScopedAccess() {
        catalogLifecycle.stopActiveSecurityScopedAccess()
    }

    @discardableResult
    func startSecurityScopedAccess(for url: URL) -> Bool {
        catalogLifecycle.startSecurityScopedAccess(for: url)
    }

    func hasActiveSecurityScopedAccess(for url: URL) -> Bool {
        catalogLifecycle.hasActiveSecurityScopedAccess(for: url)
    }

    func startSecurityScopedResource(_ url: URL) -> Bool {
        catalogLifecycle.startSecurityScopedResource(url)
    }

    func stopSecurityScopedResource(_ url: URL) {
        catalogLifecycle.stopSecurityScopedResource(url)
    }

    func setMemoryPressureWarning(_ warning: Bool) {
        Logger.process.debugMessageOnly("CatalogController.setMemoryPressureWarning()")
        presentation.memoryPressureWarning = warning
    }
}
