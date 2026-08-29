import Foundation

nonisolated struct RawCullSemanticSearchResultEvidence: Equatable, Sendable {
    let rank: Int
    let score: Float
}

/// The narrow application edge needed to compose semantic results with RawCull's
/// catalog, navigation, selection, and burst-review policies.
@MainActor
protocol RawCullSemanticSearchApplicationTarget: AnyObject {
    func semanticSearchAdmissionSnapshot() async -> [FileItem]

    func prepareApplicationForNewSemanticSearch()

    func invalidateScopedBurstAnalysisForSemanticSelectionChange()

    func applySemanticSearchSelection() async

    func restoreOrdinaryCatalogAfterSemanticSearch() async
}

/// Stable semantic-search presentation and action surface.
///
/// Semantic state remains owned by `SimilarityScoringModel`. Every property here
/// is a computed projection, so views observe the existing model without a second
/// state store.
@MainActor
final class RawCullSemanticSearchFeature {
    nonisolated static let defaultResultLimit =
        SimilarityScoringModel.semanticSearchDefaultResultLimit

    private let similarityModel: SimilarityScoringModel
    private let similarityFeature: RawCullSimilarityFeature

    private weak var applicationTarget:
        (any RawCullSemanticSearchApplicationTarget)?
    private var actionGeneration = 0

    init(
        similarityModel: SimilarityScoringModel,
        similarityFeature: RawCullSimilarityFeature? = nil,
    ) {
        self.similarityModel = similarityModel
        self.similarityFeature = similarityFeature
            ?? RawCullSimilarityFeature(similarityModel: similarityModel)
    }

    func sharesSimilarityModelIdentity(
        with similarityModel: SimilarityScoringModel,
    ) -> Bool {
        self.similarityModel === similarityModel
    }

    func sharesSimilarityFeatureIdentity(with feature: RawCullSimilarityFeature) -> Bool {
        similarityFeature === feature
    }

    func bindApplicationTarget(
        _ target: any RawCullSemanticSearchApplicationTarget,
    ) {
        if let applicationTarget {
            precondition(
                applicationTarget === target,
                "Semantic search application target may only be bound once.",
            )
            return
        }
        applicationTarget = target
    }

    var presentation: SemanticSearchUIPresentation {
        let indexing = similarityFeature.indexing
        return SemanticSearchUIPresentation(
            capability: similarityModel.semanticSearchCapability,
            searchState: similarityModel.semanticSearchState,
            indexedFileCount: similarityModel.semanticIndexedFileCount,
            catalogFileCount: similarityModel.semanticCatalogFileCount,
            isIndexing: indexing.isIndexing
                && similarityModel.canIndexSemanticSearchArtifacts,
            indexingProgress: indexing.completed,
            indexingTotal: indexing.total,
            indexingPhase: indexing.phase,
            activeBackendCanIndex: similarityModel.canIndexSemanticSearchArtifacts,
        )
    }

    var state: RawCullSemanticSearchState {
        similarityModel.semanticSearchState
    }

    var progress: RawCullSemanticSearchProgress? {
        similarityModel.semanticSearchProgress
    }

    var resultSummary: RawCullSemanticSearchResultSummary? {
        guard case let .results(summary) = state else { return nil }
        return summary
    }

    var selectedFileIDs: Set<FileItem.ID> {
        similarityModel.semanticSearchSelectedFileIDs
    }

    var orderedResultIDs: [FileItem.ID] {
        similarityModel.semanticResultOrder
            .sorted { $0.value < $1.value }
            .map(\.key)
    }

    var indexedFileCount: Int {
        similarityModel.semanticIndexedFileCount
    }

    var catalogFileCount: Int {
        similarityModel.semanticCatalogFileCount
    }

    var hasResults: Bool {
        similarityModel.hasSemanticSearchResults
    }

    var hasEmptyIndex: Bool {
        similarityModel.semanticSearchHasEmptyIndex
    }

    var canIndexArtifacts: Bool {
        similarityModel.canIndexSemanticSearchArtifacts
    }

    var isIndexingCompatibleArtifacts: Bool {
        similarityFeature.indexing.isIndexing && canIndexArtifacts
    }

    func resultEvidence(
        for fileID: FileItem.ID,
    ) -> RawCullSemanticSearchResultEvidence? {
        guard similarityModel.semanticSearchBackendDescriptor?.backend == "clip",
              case .results = state,
              let zeroBasedRank = similarityModel.semanticResultOrder[fileID],
              let score = similarityModel.semanticScores[fileID]
        else { return nil }
        return RawCullSemanticSearchResultEvidence(
            rank: zeroBasedRank + 1,
            score: score,
        )
    }

    /// Rank only the admitted files that already have compatible cached CLIP
    /// artifacts. Image indexing and source decoding are intentionally absent.
    func search(for query: String) async {
        guard !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            await clear()
            return
        }

        actionGeneration &+= 1
        let generation = actionGeneration
        guard let applicationTarget else { return }

        let admittedFiles = await applicationTarget.semanticSearchAdmissionSnapshot()
        guard isCurrentAction(generation) else { return }

        applicationTarget.prepareApplicationForNewSemanticSearch()
        await similarityModel.rankSemantically(
            query: query,
            files: admittedFiles,
        )
        guard isCurrentAction(generation) else { return }

        await applicationTarget.applySemanticSearchSelection()
    }

    func setShowsAllResults(_ showsAll: Bool) async {
        guard let applicationTarget else { return }
        applicationTarget.invalidateScopedBurstAnalysisForSemanticSelectionChange()
        similarityModel.setSemanticSearchShowsAllResults(showsAll)
        await applicationTarget.applySemanticSearchSelection()
    }

    func adjustSelection(by delta: Int) async {
        guard let applicationTarget else { return }
        applicationTarget.invalidateScopedBurstAnalysisForSemanticSelectionChange()
        similarityModel.adjustSemanticSearchSelection(by: delta)
        await applicationTarget.applySemanticSearchSelection()
    }

    func clear() async {
        actionGeneration &+= 1
        similarityModel.clearSemanticSearch()
        await applicationTarget?.restoreOrdinaryCatalogAfterSemanticSearch()
    }

    func cancel() async {
        actionGeneration &+= 1
        similarityModel.cancelSemanticSearch()
        await applicationTarget?.restoreOrdinaryCatalogAfterSemanticSearch()
    }

    private func isCurrentAction(_ generation: Int) -> Bool {
        generation == actionGeneration && !Task.isCancelled
    }
}
