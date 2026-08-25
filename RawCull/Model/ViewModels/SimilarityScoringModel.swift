//
//  SimilarityScoringModel.swift
//  RawCull
//

import Foundation
import Observation
import OSLog
import PhotoAIContracts
import RawCullCore

// MARK: - Constants

/// Blend weight applied to the saliency-subject mismatch penalty.
/// 0 = ignore subject mismatch, 1 = equal weight with visual distance.
/// Keep small so the visual artifact remains the dominant signal.
private nonisolated let kSubjectMismatchPenalty: Float = 0.10

nonisolated enum SimilarityIndexingPhase: Equatable, Sendable {
    case idle
    case generating
    case saving
}

private nonisolated struct DurableSimilarityIndexingOutput: Sendable {
    let serviceOutput: RawCullSimilarityIndexingOutput
    let artifacts: [UUID: SimilarityArtifact]
    let invalidFailures: [RawCullSimilarityIndexingFailure]
    let commitResult: PerFileAnalysisArtifactCommitResult
}

private nonisolated enum SimilarityIndexingTaskResult: Sendable {
    case success(DurableSimilarityIndexingOutput)
    case failure(String)
    case cancelled
}

private nonisolated struct SimilarityDistanceComputation: Sendable {
    let distances: [UUID: Float]
    let failureCount: Int
}

nonisolated struct RawCullSemanticSearchResultSummary: Equatable, Sendable {
    let query: String
    /// Images currently admitted to the grid.
    let resultCount: Int
    /// Every compatible image that produced a valid cosine score.
    let rankedImageCount: Int
    let indexedFileCount: Int
    let excludedFileCount: Int
    let scoringFailureCount: Int

    init(
        query: String,
        resultCount: Int,
        rankedImageCount: Int? = nil,
        indexedFileCount: Int,
        excludedFileCount: Int,
        scoringFailureCount: Int,
    ) {
        self.query = query
        self.resultCount = resultCount
        self.rankedImageCount = rankedImageCount ?? resultCount
        self.indexedFileCount = indexedFileCount
        self.excludedFileCount = excludedFileCount
        self.scoringFailureCount = scoringFailureCount
    }

    var hiddenRankedImageCount: Int {
        max(0, rankedImageCount - resultCount)
    }
}

nonisolated enum RawCullSemanticSearchState: Equatable, Sendable {
    case idle
    case searching(query: String)
    case results(RawCullSemanticSearchResultSummary)
    case emptyIndex(query: String, excludedFileCount: Int)
    case failed(query: String, message: String)
}

private nonisolated enum SemanticSearchTaskResult: Sendable {
    case success(RawCullSemanticSearchOutput)
    case failure(String)
    case emptyIndex
    case cancelled
}

// MARK: - Model

@Observable @MainActor
final class SimilarityScoringModel {
    nonisolated static let embeddingThumbnailMaxPixelSize = 512
    nonisolated static let embeddingPipelineVersion = 3
    nonisolated static let semanticSearchDefaultResultLimit = 20

    // MARK: State

    /// Descriptor-complete PhotoAIKit artifacts keyed by FileItem.id.
    var embeddings: [UUID: SimilarityArtifact] = [:]

    /// Raw distances from the current anchor image (lower = more similar).
    /// Populated by rankSimilar(to:using:saliencyInfo:).
    var distances: [UUID: Float] = [:]

    /// UUID of the image used as the similarity anchor.
    var anchorFileID: UUID?

    // MARK: Semantic search

    private(set) var semanticSearchCapability: RawCullSemanticSearchCapabilityStatus
    private(set) var semanticSearchState = RawCullSemanticSearchState.idle
    private(set) var semanticMatches: [RawCullSemanticSearchMatch] = []
    private(set) var semanticScores: [UUID: Float] = [:]
    private(set) var semanticResultOrder: [UUID: Int] = [:]
    private(set) var semanticSearchProgress: RawCullSemanticSearchProgress?
    private(set) var semanticIndexedFileCount = 0
    private(set) var semanticCatalogFileCount = 0

    var semanticSearchSelectionCount: Int {
        semanticResultOrder.count
    }

    var semanticSearchSelectedFileIDs: Set<UUID> {
        Set(semanticResultOrder.keys)
    }

    var hasSemanticSearchResults: Bool {
        if case .results = semanticSearchState {
            true
        } else {
            false
        }
    }

    var semanticSearchHasEmptyIndex: Bool {
        if case .emptyIndex = semanticSearchState {
            true
        } else {
            false
        }
    }

    // MARK: Indexing progress

    var isIndexing = false
    var indexingProgress = 0
    var indexingTotal = 0
    var indexingEstimatedSeconds = 0
    private(set) var indexingPhase = SimilarityIndexingPhase.idle
    private(set) var indexingFailures: [RawCullSimilarityIndexingFailure] = []
    private(set) var indexingPersistenceFailures: [PerFileAnalysisArtifactWriteFailure] = []
    private(set) var indexingOperationFailure: String?
    private(set) var indexingDiagnostic: String?

    // MARK: Sort flag

    /// When true, applyFilters sorts the file list by ascending distance.
    var sortBySimilarity = false

    // MARK: Burst grouping

    /// Burst groups computed by sequential distance clustering.
    var burstGroups: [BurstGroup] = []
    /// Quick lookup: fileID → group id.
    var burstGroupLookup: [UUID: Int] = [:]
    /// Distance threshold for burst clustering. Lower = tighter groups.
    var burstSensitivity: Float = 0.25
    /// When true, the grid renders a selected burst-group category instead of
    /// the burst-groups home view.
    var burstModeActive = false
    /// True while groupBursts() is running.
    var isGrouping = false
    /// Per-boundary evidence from the latest burst grouping run.
    var burstBoundaryEvidence: [BurstBoundaryEvidence] = []

    var backendDescriptor: SimilarityBackendDescriptor {
        similarityService.backendDescriptor
    }

    var artifactBackendDescriptors: [SimilarityBackendDescriptor] {
        similarityService.artifactBackendDescriptors
    }

    func hasCompleteSimilarityIndex(for files: [FileItem]) -> Bool {
        !files.isEmpty && files.allSatisfy { embeddings[$0.id] != nil }
    }

    var semanticSearchBackendDescriptor: SimilarityBackendDescriptor? {
        semanticSearchService?.backendDescriptor
    }

    var canIndexSemanticSearchArtifacts: Bool {
        guard let semanticBackend = semanticSearchBackendDescriptor else {
            return false
        }
        return artifactBackendDescriptors.contains(semanticBackend)
    }

    // MARK: Private

    @ObservationIgnored private var _indexingTask: Task<SimilarityIndexingTaskResult, Never>?
    @ObservationIgnored private var _indexingGeneration = 0
    @ObservationIgnored private var similarityService: any RawCullSimilarityServicing
    @ObservationIgnored private var semanticSearchService:
        (any RawCullSemanticSearchServicing)?
    @ObservationIgnored private var semanticArtifacts: [UUID: SimilarityArtifact] = [:]
    @ObservationIgnored private var _semanticSearchTask:
        Task<SemanticSearchTaskResult, Never>?
    @ObservationIgnored private var _semanticSearchGeneration = 0
    @ObservationIgnored private var _semanticHydrationGeneration = 0
    @ObservationIgnored private let artifactStore: any SimilarityArtifactStoring
    @ObservationIgnored private var _artifactHydrationGeneration = 0
    @ObservationIgnored private var _indexingStartedAt: Date?
    @ObservationIgnored private var _groupingTask: Task<BurstGroupingOutput?, Never>?
    @ObservationIgnored private var _groupingGeneration = 0
    @ObservationIgnored private var _rankingTask: Task<SimilarityDistanceComputation, Never>?
    @ObservationIgnored private var _rankingGeneration = 0
    @ObservationIgnored private var _adjacentDistanceCache: [String: Float] = [:]
    @ObservationIgnored private var _adjacentDistanceCacheSignature = 0

    init(
        similarityService: any RawCullSimilarityServicing = RawCullVisionSimilarityService(),
        semanticSearchCapability: RawCullSemanticSearchCapabilityStatus = .unavailable(
            reason: "Semantic search requires a valid CLIP model.",
            expectedLocations: [],
        ),
        semanticSearchService: (any RawCullSemanticSearchServicing)? = nil,
        artifactStore: any SimilarityArtifactStoring,
    ) {
        self.similarityService = similarityService
        self.semanticSearchCapability = semanticSearchCapability
        self.semanticSearchService = semanticSearchService
        self.artifactStore = artifactStore
    }

    // MARK: - Public API

    func reset() {
        resetImageSimilarityState()
        cancelSemanticSearch()
        _semanticHydrationGeneration &+= 1
        semanticArtifacts = [:]
        semanticMatches = []
        semanticScores = [:]
        semanticResultOrder = [:]
        semanticSearchProgress = nil
        semanticIndexedFileCount = 0
        semanticCatalogFileCount = 0
        semanticSearchState = .idle
    }

    private func resetImageSimilarityState() {
        cancelIndexing()
        _groupingTask?.cancel()
        _groupingTask = nil
        _rankingTask?.cancel()
        _rankingTask = nil
        _rankingGeneration &+= 1
        _artifactHydrationGeneration &+= 1
        embeddings = [:]
        distances = [:]
        anchorFileID = nil
        sortBySimilarity = false
        burstGroups = []
        burstGroupLookup = [:]
        burstBoundaryEvidence = []
        burstModeActive = false
        isGrouping = false
        _groupingGeneration = 0
        _adjacentDistanceCache = [:]
        _adjacentDistanceCacheSignature = 0
        indexingFailures = []
        indexingPersistenceFailures = []
        indexingOperationFailure = nil
        indexingDiagnostic = nil
        indexingPhase = .idle
    }

    func clearBurstGrouping() {
        _groupingTask?.cancel()
        _groupingTask = nil
        _groupingGeneration &+= 1
        burstGroups = []
        burstGroupLookup = [:]
        burstBoundaryEvidence = []
        burstModeActive = false
        isGrouping = false
        _adjacentDistanceCache = [:]
        _adjacentDistanceCacheSignature = 0
    }

    func cancelIndexing() {
        _indexingTask?.cancel()
        _indexingTask = nil
        _indexingGeneration &+= 1
        _indexingStartedAt = nil
        isIndexing = false
        indexingProgress = 0
        indexingTotal = 0
        indexingEstimatedSeconds = 0
        indexingPhase = .idle
    }

    func cancelSemanticSearch() {
        _semanticSearchTask?.cancel()
        _semanticSearchTask = nil
        _semanticSearchGeneration &+= 1
        semanticMatches = []
        semanticScores = [:]
        semanticResultOrder = [:]
        semanticSearchProgress = nil
        semanticSearchState = .idle
    }

    func clearSemanticSearch() {
        cancelSemanticSearch()
    }

    func setSimilarityService(_ service: any RawCullSimilarityServicing) {
        guard backendDescriptor != service.backendDescriptor
            || artifactBackendDescriptors != service.artifactBackendDescriptors
        else { return }

        resetImageSimilarityState()
        similarityService = service
    }

    func setSemanticSearchCapability(
        _ capability: RawCullSemanticSearchCapabilityStatus,
        service: (any RawCullSemanticSearchServicing)?,
    ) {
        let currentDescriptor = semanticSearchService?.backendDescriptor
        let replacementDescriptor = service?.backendDescriptor
        guard semanticSearchCapability != capability
            || currentDescriptor != replacementDescriptor
        else { return }

        cancelSemanticSearch()
        _semanticHydrationGeneration &+= 1
        semanticSearchCapability = capability
        semanticSearchService = service
        semanticArtifacts = [:]
        semanticMatches = []
        semanticScores = [:]
        semanticResultOrder = [:]
        semanticSearchProgress = nil
        semanticIndexedFileCount = 0
        semanticCatalogFileCount = 0
        semanticSearchState = .idle
    }

    nonisolated static var artifactPipelineSignature: SimilarityArtifactPipelineSignature {
        SimilarityArtifactPipelineSignature(
            thumbnailMaxPixelSize: embeddingThumbnailMaxPixelSize,
            pipelineVersion: embeddingPipelineVersion,
        )
    }

    /// Restore descriptor- and payload-valid artifacts for the current
    /// in-memory FileItem identifiers.
    @discardableResult
    func hydrateArtifacts(_ files: [FileItem]) async -> Int {
        guard !files.isEmpty else { return 0 }

        _artifactHydrationGeneration &+= 1
        let generation = _artifactHydrationGeneration
        let service = similarityService
        let descriptors = service.artifactBackendDescriptors
        let sources = files.map(Self.source(for:))
        let loadResult = await artifactStore.load(
            sources: sources,
            allowedBackends: descriptors,
            pipeline: Self.artifactPipelineSignature,
        )

        guard generation == _artifactHydrationGeneration,
              service.backendDescriptor == similarityService.backendDescriptor,
              descriptors == similarityService.artifactBackendDescriptors,
              !Task.isCancelled
        else { return 0 }

        let sourcesByID = Dictionary(uniqueKeysWithValues: sources.map { ($0.id, $0) })
        var validated: [UUID: SimilarityArtifact] = [:]
        var invalidEntries: [(AIImageSource, SimilarityBackendDescriptor)] = []
        for (id, artifact) in loadResult.artifacts {
            guard let source = sourcesByID[id],
                  Self.isUsable(
                      artifact,
                      for: source,
                      backends: descriptors,
                      service: service,
                  )
            else {
                if let source = sourcesByID[id],
                   let backend = descriptors.first(where: {
                       $0.backend == artifact.descriptor.backend
                           && $0.modelFingerprint == artifact.descriptor.modelFingerprint
                   }) {
                    invalidEntries.append((source, backend))
                }
                continue
            }
            validated[id] = artifact
        }

        for (source, backend) in invalidEntries {
            await artifactStore.remove(
                source: source,
                backend: backend,
                pipeline: Self.artifactPipelineSignature,
            )
        }
        guard generation == _artifactHydrationGeneration,
              !Task.isCancelled
        else { return 0 }

        for file in files {
            if let existing = embeddings[file.id],
               !Self.isUsable(
                   existing,
                   for: Self.source(for: file),
                   backends: descriptors,
                   service: service,
               ) {
                embeddings.removeValue(forKey: file.id)
            }
        }
        embeddings.merge(validated) { _, cached in cached }
        return validated.count
    }

    /// Restore only artifacts compatible with the active text-capable CLIP
    /// provider. This cache is independent of the Vision/CLIP backend selected
    /// for burst similarity.
    @discardableResult
    func hydrateSemanticArtifacts(_ files: [FileItem]) async -> Int {
        _semanticHydrationGeneration &+= 1
        let generation = _semanticHydrationGeneration
        semanticCatalogFileCount = files.count

        guard let service = semanticSearchService, !files.isEmpty else {
            semanticArtifacts = [:]
            semanticIndexedFileCount = 0
            return 0
        }

        let backend = service.backendDescriptor
        let sources = files.map(Self.source(for:))
        let loadResult = await artifactStore.load(
            sources: sources,
            allowedBackends: [backend],
            pipeline: Self.artifactPipelineSignature,
        )
        guard generation == _semanticHydrationGeneration,
              semanticSearchService?.backendDescriptor == backend,
              !Task.isCancelled
        else { return 0 }

        let sourcesByID = Dictionary(uniqueKeysWithValues: sources.map { ($0.id, $0) })
        semanticArtifacts = loadResult.artifacts.filter { id, artifact in
            guard let source = sourcesByID[id] else { return false }
            return RawCullSimilarityArtifactValidation.isCurrent(
                artifact,
                for: source,
                backend: backend,
            )
        }
        semanticIndexedFileCount = semanticArtifacts.count
        dismissStaleEmptySemanticIndexState()
        return semanticIndexedFileCount
    }

    /// Import compatible artifacts retained by the catalog-wide legacy cache.
    /// UUID remapping is performed by RawCull before this boundary.
    @discardableResult
    func importLegacyArtifacts(
        _ artifacts: [UUID: SimilarityArtifact],
        files: [FileItem],
        signature: BurstSimilaritySignature,
    ) async -> Int {
        guard signature.artifactSchemaVersion
            == SimilarityArtifactDescriptor.currentSchemaVersion,
            signature.embeddingThumbnailMaxPixelSize
            == Self.embeddingThumbnailMaxPixelSize,
            signature.embeddingPipelineVersion == Self.embeddingPipelineVersion
        else { return 0 }

        let service = similarityService
        let descriptors = service.artifactBackendDescriptors
        let sources = files.map(Self.source(for:))
        let sourcesByID = Dictionary(uniqueKeysWithValues: sources.map { ($0.id, $0) })
        let validated = artifacts.filter { id, artifact in
            guard embeddings[id] == nil,
                  let source = sourcesByID[id]
            else { return false }
            return Self.isUsable(
                artifact,
                for: source,
                backends: descriptors,
                service: service,
            )
        }
        guard !validated.isEmpty else { return 0 }

        let commitResult = await artifactStore.upsert(
            artifacts: validated,
            sources: sourcesByID,
            pipeline: Self.artifactPipelineSignature,
        )
        guard service.backendDescriptor == similarityService.backendDescriptor,
              descriptors == similarityService.artifactBackendDescriptors,
              !Task.isCancelled
        else { return 0 }

        embeddings.merge(validated) { current, _ in current }
        if let semanticBackend = semanticSearchService?.backendDescriptor {
            let semanticImports = validated.filter { id, artifact in
                guard let source = sourcesByID[id] else { return false }
                return RawCullSimilarityArtifactValidation.isCurrent(
                    artifact,
                    for: source,
                    backend: semanticBackend,
                )
            }
            semanticArtifacts.merge(semanticImports) { current, _ in current }
            semanticCatalogFileCount = files.count
            semanticIndexedFileCount = semanticArtifacts.count
            dismissStaleEmptySemanticIndexState()
        }
        return commitResult.committedSourceIDs.count
    }

    /// Generate descriptor-complete PhotoAIKit similarity artifacts from
    /// RawCull's thumbnail-resolution RAW decoding pipeline. Current artifacts
    /// are reused when they match the selected backend or its batch fallback.
    func indexFiles(
        _ files: [FileItem],
        thumbnailMaxPixelSize: Int = SimilarityScoringModel.embeddingThumbnailMaxPixelSize,
        forceRefresh: Bool = false,
    ) async {
        Logger.process.debugMessageOnly(
            "SimilarityScoringModel.indexFiles(): requested indexing for \(files.count) files",
        )
        guard !files.isEmpty else {
            Logger.process.debugMessageOnly(
                "SimilarityScoringModel.indexFiles(): skipped because no files were supplied",
            )
            return
        }
        if semanticSearchService != nil {
            semanticCatalogFileCount = files.count
        }

        _indexingTask?.cancel()
        _indexingGeneration &+= 1
        let generation = _indexingGeneration
        isIndexing = true
        indexingProgress = 0
        indexingTotal = files.count
        indexingEstimatedSeconds = 0
        indexingPhase = .generating
        indexingFailures = []
        indexingPersistenceFailures = []
        indexingOperationFailure = nil
        indexingDiagnostic = nil
        _indexingStartedAt = Date()

        let service = similarityService
        let descriptors = service.artifactBackendDescriptors
        var toIndex = files.filter { file in
            guard let artifact = embeddings[file.id] else { return true }
            guard Self.isUsable(
                artifact,
                for: Self.source(for: file),
                backends: descriptors,
                service: service,
            ) else {
                embeddings.removeValue(forKey: file.id)
                return true
            }
            return false
        }
        if forceRefresh {
            toIndex = files
        }
        if service.requiresHomogeneousBatch, !toIndex.isEmpty {
            toIndex = files
        }
        if toIndex.isEmpty {
            Logger.process.debugMessageOnly(
                "SimilarityScoringModel.indexFiles(): all similarity artifacts are current",
            )
            _indexingTask = nil
            _indexingStartedAt = nil
            indexingProgress = files.count
            isIndexing = false
            indexingPhase = .idle
            return
        }
        indexingTotal = toIndex.count

        let sources = toIndex.map(Self.source(for:))
        let sourcesByID = Dictionary(uniqueKeysWithValues: sources.map { ($0.id, $0) })
        let store = artifactStore
        let pipeline = SimilarityArtifactPipelineSignature(
            thumbnailMaxPixelSize: thumbnailMaxPixelSize,
            pipelineVersion: Self.embeddingPipelineVersion,
        )
        let workTask = Task<SimilarityIndexingTaskResult, Never> {
            @concurrent [weak self] in
            do {
                let output = try await service.index(
                    sources: sources,
                    maxPixelSize: thumbnailMaxPixelSize,
                ) { update in
                    await MainActor.run {
                        guard let self,
                              self._indexingGeneration == generation
                        else { return }
                        self.recordIndexingProgress(update)
                    }
                }

                var artifacts: [UUID: SimilarityArtifact] = [:]
                var invalidFailures: [RawCullSimilarityIndexingFailure] = []
                for (id, artifact) in output.artifacts {
                    guard let source = sourcesByID[id],
                          Self.isUsable(
                              artifact,
                              for: source,
                              backends: descriptors,
                              service: service,
                          )
                    else {
                        if let source = sourcesByID[id] {
                            invalidFailures.append(
                                RawCullSimilarityIndexingFailure(
                                    source: source,
                                    message: "PhotoAIKit returned an incompatible or invalid similarity artifact.",
                                ),
                            )
                        }
                        continue
                    }
                    artifacts[id] = artifact
                }

                await MainActor.run {
                    guard let self,
                          self._indexingGeneration == generation
                    else { return }
                    self.indexingPhase = .saving
                    self.indexingProgress = 0
                    self.indexingTotal = artifacts.count
                }
                let commitResult = await store.upsert(
                    artifacts: artifacts,
                    sources: sourcesByID,
                    pipeline: pipeline,
                )
                guard !Task.isCancelled, !commitResult.wasCancelled else {
                    return .cancelled
                }
                return .success(
                    DurableSimilarityIndexingOutput(
                        serviceOutput: output,
                        artifacts: artifacts,
                        invalidFailures: invalidFailures,
                        commitResult: commitResult,
                    ),
                )
            } catch is CancellationError {
                return .cancelled
            } catch {
                return .failure(String(describing: error))
            }
        }

        _indexingTask = workTask
        let result = await workTask.value
        guard _indexingGeneration == generation else { return }
        _indexingTask = nil
        _indexingStartedAt = nil

        guard !workTask.isCancelled else {
            finishIndexing()
            return
        }

        switch result {
        case let .success(durableOutput):
            let output = durableOutput.serviceOutput
            indexingDiagnostic = output.primaryFailureDiagnostic
            if let diagnostic = output.primaryFailureDiagnostic {
                Logger.process.warning(
                    "SimilarityScoringModel: \(diagnostic, privacy: .public)",
                )
            }
            for (id, artifact) in durableOutput.artifacts {
                embeddings[id] = artifact
                if let semanticBackend = semanticSearchService?.backendDescriptor,
                   let source = sourcesByID[id],
                   RawCullSimilarityArtifactValidation.isCurrent(
                       artifact,
                       for: source,
                       backend: semanticBackend,
                   ) {
                    semanticArtifacts[id] = artifact
                }
            }
            semanticIndexedFileCount = semanticArtifacts.count
            dismissStaleEmptySemanticIndexState()
            indexingFailures = output.failures + durableOutput.invalidFailures
            indexingPersistenceFailures = durableOutput.commitResult.failures
            if !indexingPersistenceFailures.isEmpty {
                indexingOperationFailure = "Could not save \(indexingPersistenceFailures.count) similarity artifact(s)."
                Logger.process.warning(
                    "SimilarityScoringModel: \(self.indexingPersistenceFailures.count) artifacts could not be saved",
                )
            }
            if !indexingFailures.isEmpty {
                Logger.process.warning(
                    "SimilarityScoringModel: \(self.indexingFailures.count) artifacts failed validation or generation",
                )
            }
            Logger.process.debugMessageOnly(
                "SimilarityScoringModel.indexFiles(): indexed \(durableOutput.artifacts.count)/\(toIndex.count) files with PhotoAIKit"
                    + (output.usedWholeBatchFallback ? " using Vision fallback" : ""),
            )

        case let .failure(message):
            indexingOperationFailure = message
            Logger.process.warning(
                "SimilarityScoringModel: PhotoAIKit indexing failed: \(message)",
            )

        case .cancelled:
            break
        }

        finishIndexing()
        Logger.process.debugMessageOnly(
            "SimilarityScoringModel.indexFiles(): indexing finished with \(embeddings.count) stored artifacts",
        )
    }

    /// Compute and store distances from `anchorID` to all other artifacts.
    /// PhotoAIKit owns backend distance semantics; RawCull retains the small
    /// subject-label mismatch policy adjustment.
    func rankSimilar(
        to anchorID: UUID,
        using _: [FileItem],
        saliencyInfo: [UUID: SaliencyInfo] = [:],
    ) async {
        _rankingTask?.cancel()
        _rankingTask = nil
        _rankingGeneration &+= 1
        let generation = _rankingGeneration

        guard let anchorArtifact = embeddings[anchorID] else {
            clearSimilarityRanking()
            return
        }

        let anchorLabel = saliencyInfo[anchorID]?.subjectLabel
        let snapshot = embeddings
        let service = similarityService
        let mismatchPenalty = kSubjectMismatchPenalty

        let work = Task { @concurrent in
            await Self.computeDistances(
                anchorID: anchorID,
                anchorArtifact: anchorArtifact,
                artifacts: snapshot,
                service: service,
                anchorLabel: anchorLabel,
                saliencyInfo: saliencyInfo,
                mismatchPenalty: mismatchPenalty,
            )
        }
        _rankingTask = work
        let computation = await withTaskCancellationHandler {
            await work.value
        } onCancel: {
            work.cancel()
        }

        if _rankingTask == work {
            _rankingTask = nil
        }

        guard _rankingGeneration == generation,
              !work.isCancelled,
              !Task.isCancelled
        else { return }
        if computation.failureCount > 0 {
            Logger.process.warning(
                "SimilarityScoringModel: \(computation.failureCount) PhotoAIKit distance comparisons failed",
            )
        }
        anchorFileID = anchorID
        distances = computation.distances
        sortBySimilarity = true
    }

    /// Stop only the current image-to-image ranking operation while retaining
    /// the last completed distances and their displayed order.
    func cancelSimilarityRanking() {
        _rankingTask?.cancel()
        _rankingTask = nil
        _rankingGeneration &+= 1
    }

    /// Rank an admitted catalog snapshot using only compatible cached CLIP
    /// artifacts. No source image decoding or image embedding generation is
    /// reachable from this operation.
    func rankSemantically(
        query: String,
        files: [FileItem],
    ) async {
        let trimmedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedQuery.isEmpty else {
            clearSemanticSearch()
            return
        }

        cancelSemanticSearch()
        let generation = _semanticSearchGeneration
        semanticMatches = []
        semanticScores = [:]
        semanticResultOrder = [:]
        semanticSearchProgress = nil

        guard let service = semanticSearchService else {
            semanticSearchState = .failed(
                query: trimmedQuery,
                message: Self.semanticUnavailableReason(semanticSearchCapability),
            )
            return
        }

        let candidates: [RawCullSemanticSearchCandidate] = files.enumerated().compactMap {
            element -> RawCullSemanticSearchCandidate? in
            let (offset, file) = element
            guard let artifact = semanticArtifacts[file.id] else { return nil }
            return RawCullSemanticSearchCandidate(
                fileID: file.id,
                fileName: file.name,
                catalogOrder: offset,
                artifact: artifact,
            )
        }
        let admittedFileCount = files.count
        guard !candidates.isEmpty else {
            semanticSearchState = .emptyIndex(
                query: trimmedQuery,
                excludedFileCount: admittedFileCount,
            )
            return
        }

        semanticSearchProgress = .encodingText(
            query: trimmedQuery,
            candidateCount: candidates.count,
        )
        semanticSearchState = .searching(query: trimmedQuery)
        let progressHandler: @Sendable (
            RawCullSemanticSearchProgress,
        ) async -> Void = { [model = self] progress in
            await model.acceptSemanticSearchProgress(
                progress,
                generation: generation,
            )
        }
        let work = Task<SemanticSearchTaskResult, Never> { @concurrent in
            do {
                return try await .success(
                    service.rank(
                        query: trimmedQuery,
                        candidates: candidates,
                        progress: progressHandler,
                    ),
                )
            } catch is CancellationError {
                return .cancelled
            } catch RawCullSemanticSearchError.noCompatibleArtifacts {
                return .emptyIndex
            } catch {
                return .failure(String(describing: error))
            }
        }
        _semanticSearchTask = work
        let result = await withTaskCancellationHandler {
            await work.value
        } onCancel: {
            work.cancel()
        }

        if _semanticSearchTask == work {
            _semanticSearchTask = nil
        }
        guard _semanticSearchGeneration == generation,
              !work.isCancelled,
              !Task.isCancelled
        else {
            if _semanticSearchGeneration == generation {
                semanticSearchState = .idle
            }
            return
        }

        switch result {
        case let .success(output):
            semanticMatches = output.matches
            semanticScores = Dictionary(
                uniqueKeysWithValues: output.matches.map {
                    ($0.fileID, $0.score)
                },
            )
            semanticSearchProgress = .scoring(
                query: output.query,
                completedCount: output.compatibleArtifactCount,
                candidateCount: output.compatibleArtifactCount,
            )
            applySemanticSearchResultPresentation(
                output: output,
                admittedFileCount: admittedFileCount,
            )
            if !output.failures.isEmpty {
                Logger.process.warning(
                    "SimilarityScoringModel: \(output.failures.count) cached CLIP artifacts failed semantic scoring",
                )
            }

        case .emptyIndex:
            semanticSearchProgress = nil
            semanticSearchState = .emptyIndex(
                query: trimmedQuery,
                excludedFileCount: admittedFileCount,
            )

        case let .failure(message):
            semanticSearchProgress = nil
            semanticSearchState = .failed(
                query: trimmedQuery,
                message: message,
            )

        case .cancelled:
            semanticSearchProgress = nil
            semanticSearchState = .idle
        }
    }

    func setSemanticSearchShowsAllResults(_ showsAll: Bool) {
        let count = showsAll
            ? semanticMatches.count
            : min(
                Self.semanticSearchDefaultResultLimit,
                semanticMatches.count,
            )
        setSemanticSearchSelectionCount(count)
    }

    func adjustSemanticSearchSelection(by delta: Int) {
        guard delta != 0 else { return }
        setSemanticSearchSelectionCount(
            semanticSearchSelectionCount + delta,
        )
    }

    func setSemanticSearchSelectionCount(_ requestedCount: Int) {
        guard !semanticMatches.isEmpty,
              case let .results(summary) = semanticSearchState
        else { return }

        let selectedCount = min(
            max(1, requestedCount),
            semanticMatches.count,
        )
        guard selectedCount != semanticSearchSelectionCount else { return }

        let selectedMatches = semanticMatches.prefix(selectedCount)
        semanticResultOrder = Dictionary(
            uniqueKeysWithValues: selectedMatches.enumerated().map {
                ($0.element.fileID, $0.offset)
            },
        )
        semanticSearchState = .results(
            RawCullSemanticSearchResultSummary(
                query: summary.query,
                resultCount: selectedCount,
                rankedImageCount: summary.rankedImageCount,
                indexedFileCount: summary.indexedFileCount,
                excludedFileCount: summary.excludedFileCount,
                scoringFailureCount: summary.scoringFailureCount,
            ),
        )
    }

    private func acceptSemanticSearchProgress(
        _ progress: RawCullSemanticSearchProgress,
        generation: Int,
    ) {
        guard _semanticSearchGeneration == generation,
              case let .searching(activeQuery) = semanticSearchState,
              activeQuery == progress.query
        else { return }
        semanticSearchProgress = progress
    }

    private func applySemanticSearchResultPresentation(
        output: RawCullSemanticSearchOutput,
        admittedFileCount: Int,
    ) {
        let visibleMatches = output.matches.prefix(
            Self.semanticSearchDefaultResultLimit,
        )
        semanticResultOrder = Dictionary(
            uniqueKeysWithValues: visibleMatches.enumerated().map {
                ($0.element.fileID, $0.offset)
            },
        )
        semanticSearchState = .results(
            RawCullSemanticSearchResultSummary(
                query: output.query,
                resultCount: visibleMatches.count,
                rankedImageCount: output.matches.count,
                indexedFileCount: output.compatibleArtifactCount,
                excludedFileCount: max(
                    0,
                    admittedFileCount - output.matches.count,
                ),
                scoringFailureCount: output.failures.count,
            ),
        )
    }

    // MARK: - Burst grouping

    // Cluster `files` into burst groups using a sequential O(n) distance pass.
    // `files` must be sorted by effective capture time before calling.

    func groupBursts(files: [FileItem]) async {
        Logger.process.debugMessageOnly(
            "SimilarityScoringModel.groupBursts(): grouping \(files.count) files",
        )
        guard !files.isEmpty else {
            _groupingTask?.cancel()
            _groupingTask = nil
            burstGroups = []
            burstGroupLookup = [:]
            burstBoundaryEvidence = []
            Logger.process.debugMessageOnly(
                "SimilarityScoringModel.groupBursts(): cleared groups because no files were supplied",
            )
            return
        }

        _groupingTask?.cancel()
        _groupingTask = nil

        isGrouping = true
        _groupingGeneration &+= 1
        let generation = _groupingGeneration

        let threshold = burstSensitivity
        let snapshot = embeddings
        let service = similarityService
        let config = BurstGroupingConfig(visualDistanceThreshold: threshold)
        let signature = Self.cacheSignature(files: files, artifacts: snapshot)
        let cachedAdjacentDistances = _adjacentDistanceCacheSignature == signature
            ? _adjacentDistanceCache
            : [:]

        let work = Task { @concurrent () -> BurstGroupingOutput? in
            let eligibleRuns = files.split { snapshot[$0.id] == nil }
            var groups: [BurstGroup] = []
            var boundaryEvidence: [BurstBoundaryEvidence] = []

            for runSlice in eligibleRuns {
                guard !Task.isCancelled else { return nil }
                let run = Array(runSlice)
                let adjacentDistances = Self.computeAdjacentDistances(
                    files: run,
                    artifacts: snapshot,
                    service: service,
                    cached: cachedAdjacentDistances,
                )
                let output = BurstGroupingEngine.group(
                    files: run,
                    adjacentDistances: adjacentDistances,
                    config: config,
                )
                for group in output.groups {
                    groups.append(
                        BurstGroup(id: groups.count, fileIDs: group.fileIDs),
                    )
                }
                boundaryEvidence.append(contentsOf: output.boundaryEvidence)
            }
            return BurstGroupingOutput(
                groups: groups,
                boundaryEvidence: boundaryEvidence,
            )
        }
        _groupingTask = work

        let output = await work.value

        if _groupingTask == work {
            _groupingTask = nil
        }

        guard _groupingGeneration == generation else { return }
        isGrouping = false
        guard let output else { return }

        burstGroups = output.groups
        burstGroupLookup = Dictionary(
            uniqueKeysWithValues: output.groups.flatMap { group in
                group.fileIDs.map { ($0, group.id) }
            },
        )
        burstBoundaryEvidence = output.boundaryEvidence
        _adjacentDistanceCache = Dictionary(
            uniqueKeysWithValues: output.boundaryEvidence.compactMap { evidence in
                guard let distance = evidence.visualDistance else { return nil }
                return (
                    BurstPairKey.cacheKey(
                        previousID: evidence.previousID,
                        currentID: evidence.currentID,
                    ),
                    distance,
                )
            },
        )
        _adjacentDistanceCacheSignature = signature
        let eligibleCount = files.lazy.filter { snapshot[$0.id] != nil }.count
        let excludedCount = files.count - eligibleCount
        Logger.process.debugMessageOnly(
            "SimilarityScoringModel.groupBursts(): \(burstGroups.count) burst groups from "
                + "\(eligibleCount) similarity-indexed files; excluded \(excludedCount) files "
                + "without artifacts (threshold \(threshold))",
        )
    }

    func applyCachedBurstAnalysis(_ snapshot: BurstAnalysisCacheSnapshot) {
        Logger.process.debugMessageOnly(
            "SimilarityScoringModel.applyCachedBurstAnalysis(): applying \(snapshot.groups.count) cached groups",
        )
        burstGroups = snapshot.groups
        burstBoundaryEvidence = snapshot.boundaryEvidence
        burstGroupLookup = Dictionary(
            uniqueKeysWithValues: snapshot.groups.flatMap { group in
                group.fileIDs.map { ($0, group.id) }
            },
        )
        _adjacentDistanceCache = Dictionary(
            uniqueKeysWithValues: snapshot.boundaryEvidence.compactMap { evidence in
                guard let distance = evidence.visualDistance else { return nil }
                return (
                    BurstPairKey.cacheKey(
                        previousID: evidence.previousID,
                        currentID: evidence.currentID,
                    ),
                    distance,
                )
            },
        )
        _adjacentDistanceCacheSignature = 0
    }

    // MARK: - Private state helpers

    private func finishIndexing() {
        isIndexing = false
        indexingProgress = 0
        indexingTotal = 0
        indexingEstimatedSeconds = 0
        indexingPhase = .idle
    }

    private nonisolated static func isUsable(
        _ artifact: SimilarityArtifact,
        for source: AIImageSource,
        backends: [SimilarityBackendDescriptor],
        service: any RawCullSimilarityServicing,
    ) -> Bool {
        guard RawCullSimilarityArtifactValidation.isCurrent(
            artifact,
            for: source,
            backends: backends,
        ) else { return false }
        do {
            guard let distance = try service.distance(
                from: artifact,
                to: artifact,
            ) else { return false }
            return distance.isFinite
        } catch {
            return false
        }
    }

    private func clearSimilarityRanking() {
        distances = [:]
        anchorFileID = nil
        sortBySimilarity = false
    }

    private func dismissStaleEmptySemanticIndexState() {
        guard semanticIndexedFileCount > 0,
              case .emptyIndex = semanticSearchState
        else { return }
        semanticSearchState = .idle
    }

    private func recordIndexingProgress(
        _ progress: RawCullSimilarityIndexingProgress,
    ) {
        indexingProgress = progress.completed
        indexingTotal = progress.total
        guard progress.completed > 0,
              let startedAt = _indexingStartedAt
        else { return }
        let average = Date().timeIntervalSince(startedAt) / Double(progress.completed)
        indexingEstimatedSeconds = max(
            0,
            Int(average * Double(progress.total - progress.completed)),
        )
    }

    // MARK: - Static helpers

    private nonisolated static func semanticUnavailableReason(
        _ capability: RawCullSemanticSearchCapabilityStatus,
    ) -> String {
        switch capability {
        case .checking:
            "Semantic search capability is still being checked."

        case .ready:
            "The semantic-search provider is not available."

        case let .unavailable(reason, _):
            reason

        case let .failed(_, reason):
            reason
        }
    }

    nonisolated static func source(for file: FileItem) -> AIImageSource {
        AIImageSource(id: file.id, url: file.url, displayName: file.name)
    }

    nonisolated static func computeAdjacentDistances(
        files: [FileItem],
        artifacts: [UUID: SimilarityArtifact],
        service: any RawCullSimilarityServicing,
        cached: [String: Float] = [:],
    ) -> [String: Float] {
        guard files.count > 1 else { return [:] }

        var distances = cached
        for index in files.indices.dropFirst() {
            if index & 0x3F == 0, Task.isCancelled {
                return distances
            }
            let previousID = files[index - 1].id
            let currentID = files[index].id
            let key = BurstPairKey.cacheKey(
                previousID: previousID,
                currentID: currentID,
            )
            if distances[key] != nil {
                continue
            }

            guard let previous = artifacts[previousID],
                  let current = artifacts[currentID]
            else { continue }

            do {
                if let distance = try service.distance(from: previous, to: current) {
                    distances[key] = distance
                }
            } catch {
                continue
            }
        }
        return distances
    }

    @concurrent
    private nonisolated static func computeDistances(
        anchorID: UUID,
        anchorArtifact: SimilarityArtifact,
        artifacts: [UUID: SimilarityArtifact],
        service: any RawCullSimilarityServicing,
        anchorLabel: String?,
        saliencyInfo: [UUID: SaliencyInfo],
        mismatchPenalty: Float,
    ) async -> SimilarityDistanceComputation {
        var result: [UUID: Float] = [:]
        var failureCount = 0
        for (id, artifact) in artifacts where id != anchorID {
            if result.count & 0x3F == 0, Task.isCancelled {
                break
            }
            do {
                guard var distance = try service.distance(
                    from: anchorArtifact,
                    to: artifact,
                ) else {
                    failureCount += 1
                    continue
                }
                if let anchorLabel,
                   let candidateLabel = saliencyInfo[id]?.subjectLabel,
                   anchorLabel != candidateLabel {
                    distance += mismatchPenalty
                }
                result[id] = distance
            } catch {
                failureCount += 1
            }
        }
        return SimilarityDistanceComputation(
            distances: result,
            failureCount: failureCount,
        )
    }

    private nonisolated static func cacheSignature(
        files: [FileItem],
        artifacts: [UUID: SimilarityArtifact],
    ) -> Int {
        var hasher = Hasher()
        hasher.combine(files.count)
        for file in files {
            hasher.combine(file.id)
            guard let artifact = artifacts[file.id] else {
                hasher.combine(0)
                continue
            }
            hasher.combine(artifact.descriptor)
            hasher.combine(artifact.payload)
        }
        return hasher.finalize()
    }
}
