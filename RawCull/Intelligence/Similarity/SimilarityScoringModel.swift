//
//  SimilarityScoringModel.swift
//  RawCull
//

import Foundation
import Observation
import OSLog
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

// MARK: - Model

@Observable @MainActor
final class SimilarityScoringModel {
    nonisolated static let artifactSchemaVersion = SimilarityArtifactDescriptor.currentSchemaVersion
    nonisolated static let embeddingThumbnailMaxPixelSize = 512
    nonisolated static let embeddingPipelineVersion = 3

    // MARK: State

    /// Vision feature-print artifacts keyed by FileItem.id.
    var embeddings: [UUID: SimilarityArtifact] = [:]

    /// Raw distances from the current anchor image (lower = more similar).
    /// Populated by rankSimilar(to:using:saliencyInfo:).
    var distances: [UUID: Float] = [:]

    /// UUID of the image used as the similarity anchor.
    var anchorFileID: UUID?

    // MARK: Indexing progress

    var isIndexing = false
    var indexingProgress = 0
    var indexingTotal = 0
    var indexingEstimatedSeconds = 0
    private(set) var indexingPhase = SimilarityIndexingPhase.idle
    private(set) var indexingFailures: [RawCullSimilarityIndexingFailure] = []
    private(set) var indexingPersistenceFailures: [PerFileAnalysisArtifactWriteFailure] = []
    private(set) var indexingOperationFailure: String?

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

    // MARK: Private

    @ObservationIgnored private var _indexingTask: Task<SimilarityIndexingTaskResult, Never>?
    @ObservationIgnored private var _indexingGeneration = 0
    @ObservationIgnored private var similarityService: any RawCullSimilarityServicing
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
        artifactStore: any SimilarityArtifactStoring,
    ) {
        self.similarityService = similarityService
        self.artifactStore = artifactStore
    }

    // MARK: - Public API

    func reset() {
        resetImageSimilarityState()
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
        return commitResult.committedSourceIDs.count
    }

    /// Generate descriptor-complete Vision similarity artifacts from
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
                                    message: "Vision returned an incompatible or invalid similarity artifact.",
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
            for (id, artifact) in durableOutput.artifacts {
                embeddings[id] = artifact
            }
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
                "SimilarityScoringModel.indexFiles(): indexed \(durableOutput.artifacts.count)/\(toIndex.count) files with Vision",
            )

        case let .failure(message):
            indexingOperationFailure = message
            Logger.process.warning(
                "SimilarityScoringModel: Vision indexing failed: \(message)",
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
    /// PhotoAnalysisKit owns Vision distance semantics; RawCull retains the small
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
                "SimilarityScoringModel: \(computation.failureCount) Vision distance comparisons failed",
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

    // MARK: - Burst grouping

    // Cluster `files` into burst groups using a sequential O(n) distance pass.
    // `files` must be sorted by effective capture time before calling.

    func groupBursts(
        files: [FileItem],
        configuration: BurstGroupingConfig? = nil,
    ) async {
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

        let snapshot = embeddings
        let service = similarityService
        let config = configuration ?? BurstGroupingConfig(
            visualDistanceThreshold: burstSensitivity,
        )
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
                + "without artifacts (threshold \(config.visualDistanceThreshold))",
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
            hasher.combine(artifact.featurePrint.payload)
        }
        return hasher.finalize()
    }
}
