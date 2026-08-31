import Foundation
import Observation
import RawCullCore

nonisolated struct RawCullSimilarityCatalogIdentity: Equatable, Hashable, Sendable {
    let catalogURL: URL?
    let generation: UInt64
}

nonisolated struct RawCullSimilarityCatalogSnapshot: Equatable, Sendable {
    let files: [FileItem]
    let identity: RawCullSimilarityCatalogIdentity
}

nonisolated struct RawCullSimilarityCatalogHydrationRequest: Equatable, Sendable {
    let files: [FileItem]
    let catalogIdentity: RawCullSimilarityCatalogIdentity
}

nonisolated struct RawCullSimilarityIndexRequest: Equatable, Sendable {
    let files: [FileItem]
    let catalogIdentity: RawCullSimilarityCatalogIdentity
    let thumbnailMaxPixelSize: Int
    let forceRefresh: Bool

    init(
        files: [FileItem],
        catalogIdentity: RawCullSimilarityCatalogIdentity,
        thumbnailMaxPixelSize: Int = SimilarityScoringModel.embeddingThumbnailMaxPixelSize,
        forceRefresh: Bool = false,
    ) {
        self.files = files
        self.catalogIdentity = catalogIdentity
        self.thumbnailMaxPixelSize = thumbnailMaxPixelSize
        self.forceRefresh = forceRefresh
    }
}

nonisolated struct RawCullSimilarityRankingRequest: Equatable, Sendable {
    let anchorFileID: UUID
    let files: [FileItem]
    let saliencyInfo: [UUID: SaliencyInfo]
    let catalogIdentity: RawCullSimilarityCatalogIdentity
}

nonisolated struct RawCullSimilarityRankingCompletion: Equatable, Sendable {
    let anchorFileID: UUID
    let catalogIdentity: RawCullSimilarityCatalogIdentity
    let backendIdentity: SimilarityBackendDescriptor
}

nonisolated enum RawCullSimilarityBackendKind: Equatable, Sendable {
    case vision
}

nonisolated struct RawCullSimilarityBackendPresentation: Equatable, Sendable {
    let kind: RawCullSimilarityBackendKind
    let displayName: String
}

nonisolated struct RawCullSimilarityIndexingPresentation: Equatable, Sendable {
    let isIndexing: Bool
    let phase: SimilarityIndexingPhase
    let completed: Int
    let total: Int
    let estimatedSeconds: Int
    let generationFailureCount: Int
    let persistenceFailureCount: Int
    let operationFailure: String?
}

nonisolated enum RawCullSimilarityEvidence: Equatable, Sendable {
    case anchor
    case distance(Float)
}

@MainActor
protocol RawCullSimilarityApplicationContext: AnyObject {
    var currentSimilarityCatalogSnapshot: RawCullSimilarityCatalogSnapshot { get }
}

/// Application feature boundary for image-similarity hydration, indexing,
/// ranking, and presentation. `SimilarityScoringModel` remains the single
/// observable state owner. The remaining burst-state projection is explicitly
/// tracked as part of the separately scoped persistence boundary.
@Observable @MainActor
final class RawCullSimilarityFeature {
    @ObservationIgnored private let model: SimilarityScoringModel
    @ObservationIgnored private weak var applicationContext:
        (any RawCullSimilarityApplicationContext)?

    @ObservationIgnored private(set) var imageHydrationTask: Task<Void, Never>?
    @ObservationIgnored private(set) var catalogHydrationTask: Task<Void, Never>?
    @ObservationIgnored private var imageHydrationGeneration: UInt64 = 0
    @ObservationIgnored private var catalogHydrationGeneration: UInt64 = 0
    @ObservationIgnored private var rankingGeneration: UInt64 = 0

    init(similarityModel: SimilarityScoringModel) {
        model = similarityModel
    }

    func bindApplicationContext(_ context: any RawCullSimilarityApplicationContext) {
        if let applicationContext {
            precondition(
                applicationContext === context,
                "Similarity application context may only be bound once.",
            )
            return
        }
        applicationContext = context
    }

    func sharesSimilarityModelIdentity(with other: SimilarityScoringModel) -> Bool {
        model === other
    }

    var backend: RawCullSimilarityBackendPresentation {
        RawCullSimilarityBackendPresentation(kind: .vision, displayName: "Vision")
    }

    var indexing: RawCullSimilarityIndexingPresentation {
        RawCullSimilarityIndexingPresentation(
            isIndexing: model.isIndexing,
            phase: model.indexingPhase,
            completed: model.indexingProgress,
            total: model.indexingTotal,
            estimatedSeconds: model.indexingEstimatedSeconds,
            generationFailureCount: model.indexingFailures.count,
            persistenceFailureCount: model.indexingPersistenceFailures.count,
            operationFailure: model.indexingOperationFailure,
        )
    }

    var isSimilaritySortingActive: Bool {
        model.sortBySimilarity
    }

    var isGrouping: Bool {
        model.isGrouping
    }

    var burstGroups: [BurstGroup] {
        model.burstGroups
    }

    var burstGroupLookup: [UUID: Int] {
        model.burstGroupLookup
    }

    var burstSensitivity: Float {
        get { model.burstSensitivity }
        set { model.burstSensitivity = newValue }
    }

    var burstModeActive: Bool {
        get { model.burstModeActive }
        set { model.burstModeActive = newValue }
    }

    var isBusy: Bool {
        model.isIndexing || model.isGrouping
    }

    var indexedFileCount: Int {
        model.embeddings.count
    }

    func hasCompleteIndex(for files: [FileItem]) -> Bool {
        model.hasCompleteSimilarityIndex(for: files)
    }

    func evidence(for fileID: UUID) -> RawCullSimilarityEvidence? {
        guard model.sortBySimilarity,
              let anchorID = model.anchorFileID,
              model.embeddings[fileID] != nil,
              model.embeddings[anchorID] != nil
        else { return nil }

        if fileID == anchorID {
            return .anchor
        }
        return model.distances[fileID].map(RawCullSimilarityEvidence.distance)
    }

    func setSimilaritySortingActive(_ isActive: Bool) {
        model.sortBySimilarity = isActive
    }

    @discardableResult
    func hydrateCatalog(_ request: RawCullSimilarityCatalogHydrationRequest) async -> Bool {
        catalogHydrationTask?.cancel()
        catalogHydrationGeneration &+= 1
        let generation = catalogHydrationGeneration
        let task = Task { [weak self] in
            guard let self else { return }
            await self.model.hydrateArtifacts(request.files)
        }
        catalogHydrationTask = task
        await task.value
        guard generation == catalogHydrationGeneration else { return false }
        catalogHydrationTask = nil
        return !task.isCancelled
            && !Task.isCancelled
            && applicationContext?.currentSimilarityCatalogSnapshot.identity
            == request.catalogIdentity
    }

    func cancelHydration() {
        imageHydrationTask?.cancel()
        imageHydrationTask = nil
        catalogHydrationTask?.cancel()
        catalogHydrationTask = nil
        imageHydrationGeneration &+= 1
        catalogHydrationGeneration &+= 1
    }

    func resetCatalogState() {
        cancelHydration()
        cancelRanking()
        model.reset()
    }

    func index(_ request: RawCullSimilarityIndexRequest) async {
        await model.hydrateArtifacts(request.files)
        guard requestIsCurrent(request.catalogIdentity) else { return }
        await model.indexFiles(
            request.files,
            thumbnailMaxPixelSize: request.thumbnailMaxPixelSize,
            forceRefresh: request.forceRefresh,
        )
    }

    func indexCurrentCatalog(forceRefresh: Bool = false) async {
        guard let snapshot = applicationContext?.currentSimilarityCatalogSnapshot else {
            return
        }
        await index(
            RawCullSimilarityIndexRequest(
                files: snapshot.files,
                catalogIdentity: snapshot.identity,
                forceRefresh: forceRefresh,
            ),
        )
    }

    // MARK: - Burst pipeline operations

    @discardableResult
    func hydrateBurstArtifacts(_ files: [FileItem]) async -> Int {
        await model.hydrateArtifacts(files)
    }

    func indexBurstFiles(_ files: [FileItem], forceRefresh: Bool = false) async {
        await model.indexFiles(files, forceRefresh: forceRefresh)
    }

    func rank(
        _ request: RawCullSimilarityRankingRequest,
    ) async -> RawCullSimilarityRankingCompletion? {
        rankingGeneration &+= 1
        let generation = rankingGeneration
        let backendIdentity = model.backendDescriptor

        if !model.hasCompleteSimilarityIndex(for: request.files) {
            await index(
                RawCullSimilarityIndexRequest(
                    files: request.files,
                    catalogIdentity: request.catalogIdentity,
                ),
            )
        }
        guard rankingRequestIsCurrent(
            request,
            generation: generation,
            backendIdentity: backendIdentity,
        ) else { return nil }

        await model.rankSimilar(
            to: request.anchorFileID,
            using: request.files,
            saliencyInfo: request.saliencyInfo,
        )
        guard rankingRequestIsCurrent(
            request,
            generation: generation,
            backendIdentity: backendIdentity,
        ), model.anchorFileID == request.anchorFileID
        else { return nil }

        return RawCullSimilarityRankingCompletion(
            anchorFileID: request.anchorFileID,
            catalogIdentity: request.catalogIdentity,
            backendIdentity: backendIdentity,
        )
    }

    func cancelRanking() {
        rankingGeneration &+= 1
        model.cancelSimilarityRanking()
    }

    private func requestIsCurrent(_ identity: RawCullSimilarityCatalogIdentity) -> Bool {
        !Task.isCancelled
            && applicationContext?.currentSimilarityCatalogSnapshot.identity == identity
    }

    private func rankingRequestIsCurrent(
        _ request: RawCullSimilarityRankingRequest,
        generation: UInt64,
        backendIdentity: SimilarityBackendDescriptor,
    ) -> Bool {
        !Task.isCancelled
            && rankingGeneration == generation
            && model.backendDescriptor == backendIdentity
            && requestIsCurrent(request.catalogIdentity)
    }
}
