//
//  MCPAnalysisWorkspace.swift
//  RawCull
//
//  The workspace surface `MCPAnalysisController` may use. MCP jobs run in the
//  live workspace (they open the job's catalog and run burst analysis there), so
//  this protocol names every piece of UI state a job reads or changes. Adding a
//  requirement here is the review point for "should an MCP job touch this?".
//

import Foundation
import PhotoAIContracts
import RawCullCore

@MainActor
protocol MCPAnalysisWorkspace: AnyObject {
    // MARK: Catalog

    var sources: [ARWSourceCatalog] { get set }
    var selectedSource: ARWSourceCatalog? { get set }
    /// The catalog the lifecycle coordinator has actually loaded.
    var loadedSource: ARWSourceCatalog? { get }
    var files: [FileItem] { get }
    var scanDiscoveredCount: Int { get }
    var catalogLoadFailure: CatalogLoadFailure? { get }
    var catalogPersistenceError: String? { get }
    /// A catalog transition or load task is running.
    var isCatalogTransitionActive: Bool { get }
    /// The file scan for the loaded catalog is still running.
    var isScanningCatalog: Bool { get }
    /// A catalog is loading, scanning, or creating thumbnails.
    var isMCPWorkspaceLoading: Bool { get }

    func hasActiveSecurityScopedAccess(for url: URL) -> Bool
    func retainSecurityScopedAccess(for url: URL) -> RawCullCatalogGrant?
    func startCatalogLoad(for source: ARWSourceCatalog?, scopedURL: URL?, retainedAccess: RawCullCatalogGrant?)
    func cancelCatalogLoad()

    // MARK: Availability

    var isMCPTerminationPending: Bool { get }
    var isDeepAIReviewBlockedByOtherWork: Bool { get }
    var isPreparingBurstCatalog: Bool { get }
    var isSharpnessCalibrationRunning: Bool { get }

    // MARK: Authorization

    func mcpCatalogSummary(scanId: UUID?) -> CatalogSummary?
    func authorizeCatalogForMCPJob(catalogId: UUID) throws

    // MARK: Burst analysis

    var isSemanticSearchActive: Bool { get }
    func clearActiveSemanticSearchForMCP() async
    var fullCatalogBurstAnalysisFiles: [FileItem] { get }
    var burstAnalysisGeneration: Int { get }
    var burstAnalysisProgress: BurstAnalysisProgress { get }
    var currentBurstSimilaritySignature: BurstSimilaritySignature { get }
    var currentSharpnessScoringSignature: SharpnessScoringSignature { get }
    func startBurstAnalysis(catalog: URL, files: [FileItem]) async -> BurstAnalysisPipelineResult?

    // MARK: Results and progress

    var currentSharpnessScores: [UUID: Float] { get }
    var currentSimilarityEmbeddings: [UUID: SimilarityArtifact] { get }
    var sharpnessScoringProgress: Int { get }
    var similarityIndexingProgress: Int { get }

    /// Shows the job's bursts after it opened a catalog for the analysis.
    func presentBurstResultsAfterMCPJob()
}

extension RawCullViewModel: MCPAnalysisWorkspace {
    // Catalog requirements; the state lives in `catalog`.
    var sources: [ARWSourceCatalog] {
        get { catalog.sources }
        set { catalog.sources = newValue }
    }

    var selectedSource: ARWSourceCatalog? {
        get { catalog.selectedSource }
        set { catalog.selectedSource = newValue }
    }

    var files: [FileItem] { catalog.files }
    var scanDiscoveredCount: Int { catalog.scanDiscoveredCount }
    var catalogLoadFailure: CatalogLoadFailure? { catalog.catalogLoadFailure }

    // Burst requirements; the state lives in `burstWorkflow`.
    var isDeepAIReviewBlockedByOtherWork: Bool { burstWorkflow.isDeepAIReviewBlockedByOtherWork }
    var isPreparingBurstCatalog: Bool { burstWorkflow.isPreparingBurstCatalog }
    var fullCatalogBurstAnalysisFiles: [FileItem] { burstWorkflow.fullCatalogBurstAnalysisFiles }
    var burstAnalysisGeneration: Int { burstWorkflow.burstAnalysisGeneration }
    var burstAnalysisProgress: BurstAnalysisProgress { burstWorkflow.burstAnalysisProgress }
    var currentBurstSimilaritySignature: BurstSimilaritySignature { burstWorkflow.currentBurstSimilaritySignature }

    func startBurstAnalysis(catalog: URL, files: [FileItem]) async -> BurstAnalysisPipelineResult? {
        await burstWorkflow.startBurstAnalysis(catalog: catalog, files: files)
    }

    var loadedSource: ARWSourceCatalog? { catalogLifecycle.currentSource }
    var catalogPersistenceError: String? { ratings.cullingModel.persistenceError }

    var isCatalogTransitionActive: Bool {
        catalogLifecycle.transitionTask != nil || catalogLifecycle.loadTask != nil
    }

    var isScanningCatalog: Bool { catalog.scanning }

    var isMCPWorkspaceLoading: Bool {
        isCatalogTransitionActive || catalog.scanning || catalog.isCreatingThumbnails
    }

    func retainSecurityScopedAccess(for url: URL) -> RawCullCatalogGrant? {
        catalogLifecycle.retainSecurityScopedAccess(for: url)
    }

    var isMCPTerminationPending: Bool { ratings.cullingModel.isTerminationPending }
    var isSharpnessCalibrationRunning: Bool { sharpnessModel.isCalibratingSharpnessScoring }

    func authorizeCatalogForMCPJob(catalogId: UUID) throws {
        _ = try authorizeMCPCatalog(allowAnalysis: true, catalogId: catalogId, preservingJob: true)
    }

    var isSemanticSearchActive: Bool { similarityModel.semanticSearchState != .idle }

    func clearActiveSemanticSearchForMCP() async {
        await semanticSearchFeature.clear()
    }

    var currentSharpnessScoringSignature: SharpnessScoringSignature { sharpnessModel.scoringSignature }
    var currentSharpnessScores: [UUID: Float] { sharpnessModel.scores }
    var currentSimilarityEmbeddings: [UUID: SimilarityArtifact] { similarityModel.embeddings }
    var sharpnessScoringProgress: Int { sharpnessModel.scoringProgress }
    var similarityIndexingProgress: Int { similarityModel.indexingProgress }

    func presentBurstResultsAfterMCPJob() {
        burstWorkflow.showsDetailedBurstComparison = false
        burstWorkflow.useExistingBurstGroupIndex()
    }
}
