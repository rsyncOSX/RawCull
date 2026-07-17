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

private nonisolated enum SimilarityIndexingTaskResult: Sendable {
    case success(RawCullSimilarityIndexingOutput)
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
    nonisolated static let embeddingThumbnailMaxPixelSize = 512
    nonisolated static let embeddingPipelineVersion = 2

    // MARK: State

    /// Descriptor-complete PhotoAIKit artifacts keyed by FileItem.id.
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
    private(set) var indexingFailures: [RawCullSimilarityIndexingFailure] = []
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

    // MARK: Private

    @ObservationIgnored private var _indexingTask: Task<SimilarityIndexingTaskResult, Never>?
    @ObservationIgnored private var _indexingGeneration = 0
    @ObservationIgnored private let similarityService: any RawCullSimilarityServicing
    @ObservationIgnored private var _indexingStartedAt: Date?
    @ObservationIgnored private var _groupingTask: Task<BurstGroupingOutput?, Never>?
    @ObservationIgnored private var _groupingGeneration = 0
    @ObservationIgnored private var _adjacentDistanceCache: [String: Float] = [:]
    @ObservationIgnored private var _adjacentDistanceCacheSignature = 0

    init(
        similarityService: any RawCullSimilarityServicing = RawCullVisionSimilarityService(),
    ) {
        self.similarityService = similarityService
    }

    // MARK: - Public API

    func reset() {
        cancelIndexing()
        _groupingTask?.cancel()
        _groupingTask = nil
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
        indexingOperationFailure = nil
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
    }

    /// Generate descriptor-complete PhotoAIKit Vision artifacts from RawCull's
    /// thumbnail-resolution RAW decoding pipeline. Current artifacts are reused.
    func indexFiles(
        _ files: [FileItem],
        thumbnailMaxPixelSize: Int = SimilarityScoringModel.embeddingThumbnailMaxPixelSize,
    ) async {
        guard !files.isEmpty else { return }

        _indexingTask?.cancel()
        _indexingGeneration &+= 1
        let generation = _indexingGeneration
        isIndexing = true
        indexingProgress = 0
        indexingTotal = files.count
        indexingEstimatedSeconds = 0
        indexingFailures = []
        indexingOperationFailure = nil
        _indexingStartedAt = Date()

        let descriptor = similarityService.backendDescriptor
        let toIndex = files.filter { file in
            guard let artifact = embeddings[file.id] else { return true }
            return !RawCullSimilarityArtifactValidation.isCurrent(
                artifact,
                for: Self.source(for: file),
                backend: descriptor,
            )
        }
        if toIndex.isEmpty {
            _indexingTask = nil
            _indexingStartedAt = nil
            indexingProgress = files.count
            isIndexing = false
            return
        }
        indexingTotal = toIndex.count

        let sources = toIndex.map(Self.source(for:))
        let service = similarityService
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
                return .success(output)
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
        case let .success(output):
            let sourcesByID = Dictionary(uniqueKeysWithValues: sources.map { ($0.id, $0) })
            var invalidFailures: [RawCullSimilarityIndexingFailure] = []
            for (id, artifact) in output.artifacts {
                guard let source = sourcesByID[id],
                      RawCullSimilarityArtifactValidation.isCurrent(
                          artifact,
                          for: source,
                          backend: descriptor,
                      )
                else {
                    if let source = sourcesByID[id] {
                        invalidFailures.append(
                            RawCullSimilarityIndexingFailure(
                                source: source,
                                message: "PhotoAIKit returned an incompatible similarity artifact.",
                            ),
                        )
                    }
                    continue
                }
                embeddings[id] = artifact
            }
            indexingFailures = output.failures + invalidFailures
            if !indexingFailures.isEmpty {
                Logger.process.warning(
                    "SimilarityScoringModel: \(self.indexingFailures.count) artifacts failed validation or generation",
                )
            }
            Logger.process.debugMessageOnly(
                "SimilarityScoringModel: indexed \(output.artifacts.count)/\(toIndex.count) files with PhotoAIKit",
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
    }

    /// Compute and store distances from `anchorID` to all other artifacts.
    /// PhotoAIKit owns Vision distance semantics; RawCull retains the small
    /// subject-label mismatch policy adjustment.
    func rankSimilar(
        to anchorID: UUID,
        using _: [FileItem],
        saliencyInfo: [UUID: SaliencyInfo] = [:],
    ) async {
        guard let anchorArtifact = embeddings[anchorID] else {
            clearSimilarityRanking()
            return
        }

        let anchorLabel = saliencyInfo[anchorID]?.subjectLabel
        let snapshot = embeddings
        let service = similarityService
        let mismatchPenalty = kSubjectMismatchPenalty

        let computation = await Task { @concurrent in
            Self.computeDistances(
                anchorID: anchorID,
                anchorArtifact: anchorArtifact,
                artifacts: snapshot,
                service: service,
                anchorLabel: anchorLabel,
                saliencyInfo: saliencyInfo,
                mismatchPenalty: mismatchPenalty,
            )
        }.value

        guard !Task.isCancelled else { return }
        if computation.failureCount > 0 {
            Logger.process.warning(
                "SimilarityScoringModel: \(computation.failureCount) PhotoAIKit distance comparisons failed",
            )
        }
        anchorFileID = anchorID
        distances = computation.distances
        sortBySimilarity = true
    }

    // MARK: - Burst grouping

    /// Cluster `files` into burst groups using a sequential O(n) distance pass.
    /// `files` must be sorted by filename (= shot order) before calling.
    func groupBursts(files: [FileItem]) async {
        guard !files.isEmpty else {
            _groupingTask?.cancel()
            _groupingTask = nil
            burstGroups = []
            burstGroupLookup = [:]
            burstBoundaryEvidence = []
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
            let adjacentDistances = Self.computeAdjacentDistances(
                files: files,
                artifacts: snapshot,
                service: service,
                cached: cachedAdjacentDistances,
            )
            guard !Task.isCancelled else { return nil }
            return BurstGroupingEngine.group(
                files: files,
                adjacentDistances: adjacentDistances,
                config: config,
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
                    distance
                )
            },
        )
        _adjacentDistanceCacheSignature = signature
        Logger.process.debugMessageOnly(
            "SimilarityScoringModel: \(burstGroups.count) burst groups from \(files.count) files (threshold \(threshold))",
        )
    }

    func applyCachedBurstAnalysis(_ snapshot: BurstAnalysisCacheSnapshot) {
        embeddings = snapshot.embeddings
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
                    distance
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

    private nonisolated static func computeDistances(
        anchorID: UUID,
        anchorArtifact: SimilarityArtifact,
        artifacts: [UUID: SimilarityArtifact],
        service: any RawCullSimilarityServicing,
        anchorLabel: String?,
        saliencyInfo: [UUID: SaliencyInfo],
        mismatchPenalty: Float,
    ) -> SimilarityDistanceComputation {
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
                   anchorLabel != candidateLabel
                {
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
