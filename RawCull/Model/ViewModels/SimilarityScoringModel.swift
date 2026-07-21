//
//  SimilarityScoringModel.swift
//  RawCull
//

import Foundation
import Observation
import OSLog
import PhotoAnalysisKit
import RawCullCore

// MARK: - Constants

/// Blend weight applied to the saliency-subject mismatch penalty.
/// 0 = ignore subject mismatch, 1 = equal weight with visual distance.
/// Keep small so the visual embedding remains the dominant signal.
private let kSubjectMismatchPenalty: Float = 0.10
private let kMinimumSamplesBeforeEstimation = 10
private let kEstimationWindowSize = 10

// MARK: - Model

@Observable @MainActor
final class SimilarityScoringModel {
    typealias EmbeddingProvider = @Sendable (URL, Int) async -> Data?

    nonisolated static let embeddingThumbnailMaxPixelSize = 512
    nonisolated static let embeddingPipelineVersion = 2
    nonisolated static let featurePrintRevision = VisionFeaturePrintBackend().revision

    // MARK: State

    /// Codable PhotoAnalysisKit feature prints keyed by FileItem.id.
    /// Data storage keeps the in-memory and persisted RawCull cache compact.
    var embeddings: [UUID: Data] = [:]

    /// Raw distances from the current anchor image (lower = more similar).
    /// Populated by rankSimilar(to:using:saliencyInfo:).
    var distances: [UUID: Float] = [:]

    /// UUID of the image used as the similarity anchor.
    var anchorFileID: UUID?

    // MARK: Indexing progress

    var isIndexing: Bool = false
    var indexingProgress: Int = 0
    var indexingTotal: Int = 0
    var indexingEstimatedSeconds: Int = 0

    // MARK: Sort flag

    /// When true, applyFilters sorts the file list by ascending distance.
    var sortBySimilarity: Bool = false

    // MARK: Burst grouping

    /// Burst groups computed by sequential distance clustering.
    var burstGroups: [BurstGroup] = []
    /// Quick lookup: fileID → group id.
    var burstGroupLookup: [UUID: Int] = [:]
    /// Distance threshold for burst clustering. Lower = tighter groups.
    var burstSensitivity: Float = 0.25
    /// When true, the grid renders a selected burst-group category instead of
    /// the burst-groups home view.
    var burstModeActive: Bool = false
    /// True while groupBursts() is running.
    var isGrouping: Bool = false
    /// Per-boundary evidence from the latest burst grouping run.
    var burstBoundaryEvidence: [BurstBoundaryEvidence] = []

    // MARK: Private

    @ObservationIgnored private var _indexingTask: Task<Void, Never>?
    @ObservationIgnored private var _indexingGeneration: Int = 0
    @ObservationIgnored private let embeddingProvider: EmbeddingProvider
    @ObservationIgnored private var _groupingTask: Task<BurstGroupingOutput?, Never>?
    @ObservationIgnored private var _groupingGeneration: Int = 0
    @ObservationIgnored private var _adjacentDistanceCache: [String: Float] = [:]
    @ObservationIgnored private var _adjacentDistanceCacheSignature: Int = 0

    init(
        embeddingProvider: @escaping EmbeddingProvider = SimilarityScoringModel.computeEmbedding,
    ) {
        self.embeddingProvider = embeddingProvider
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
    }

    func cancelIndexing() {
        _indexingTask?.cancel()
        _indexingTask = nil
        _indexingGeneration &+= 1
        isIndexing = false
        indexingProgress = 0
        indexingTotal = 0
        indexingEstimatedSeconds = 0
    }

    /// Compute Vision feature-print embeddings for all files using thumbnail-resolution
    /// images (same thumbnail size used by sharpness scoring).
    /// Already-embedded files are skipped for efficiency.
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
        // Separate files that need embedding from those already done.
        let toIndex = files.filter { embeddings[$0.id] == nil }
        if toIndex.isEmpty {
            _indexingTask = nil
            indexingProgress = files.count
            isIndexing = false
            return
        }
        indexingTotal = toIndex.count

        let thumbSize = thumbnailMaxPixelSize
        var iterator = toIndex.makeIterator()
        var active = 0
        let maxConcurrent = 4
        let embeddingProvider = self.embeddingProvider

        let workTask = Task {
            await withTaskGroup(of: (UUID, Data?).self) { group in
                while active < maxConcurrent, let file = iterator.next() {
                    let url = file.url
                    let id = file.id
                    group.addTask(priority: .userInitiated) {
                        let data = await embeddingProvider(url, thumbSize)
                        return (id, data)
                    }
                    active += 1
                }

                var localEmbeddings: [UUID: Data] = [:]
                var completedCount = 0
                var completionTimes: [TimeInterval] = []
                var lastCompletionTime: Date?

                for await (id, data) in group {
                    active -= 1
                    guard !Task.isCancelled else {
                        group.cancelAll()
                        break
                    }
                    guard self._indexingGeneration == generation else {
                        group.cancelAll()
                        break
                    }

                    if let data {
                        localEmbeddings[id] = data
                    }
                    completedCount += 1
                    self.indexingProgress = completedCount

                    let now = Date()
                    if let lastCompletionTime {
                        completionTimes.append(now.timeIntervalSince(lastCompletionTime))
                    }
                    lastCompletionTime = now

                    if completedCount >= kMinimumSamplesBeforeEstimation, !completionTimes.isEmpty {
                        let recentTimes = completionTimes.suffix(min(kEstimationWindowSize, completionTimes.count))
                        let avgSecondsPerCompletion = recentTimes.reduce(0, +) / Double(recentTimes.count)
                        let remainingItems = toIndex.count - completedCount
                        self.indexingEstimatedSeconds = Swift.max(0, Int(avgSecondsPerCompletion * Double(remainingItems)))
                    }

                    if let file = iterator.next() {
                        let url = file.url
                        let id = file.id
                        group.addTask(priority: .userInitiated) {
                            let data = await embeddingProvider(url, thumbSize)
                            return (id, data)
                        }
                        active += 1
                    }
                }

                guard !Task.isCancelled else { return }
                guard self._indexingGeneration == generation else { return }
                // Merge newly computed embeddings with any pre-existing ones.
                for (id, data) in localEmbeddings {
                    self.embeddings[id] = data
                }
                Logger.process.debugMessageOnly("SimilarityScoringModel: indexed \(localEmbeddings.count)/\(toIndex.count) files")
            }
        }

        _indexingTask = workTask
        await workTask.value
        guard _indexingGeneration == generation else { return }
        _indexingTask = nil
        guard !workTask.isCancelled else {
            isIndexing = false
            return
        }

        isIndexing = false
        indexingProgress = 0
        indexingTotal = 0
        indexingEstimatedSeconds = 0
    }

    /// Compute and store distances from `anchorID` to all other embedded images.
    /// Applies a small saliency-subject mismatch penalty when both images have
    /// subject labels and the labels differ.
    ///
    /// Feature-print decoding and distance calculation run away from the main actor.
    ///
    /// - Parameters:
    ///   - anchorID: The reference image's UUID.
    ///   - files: The full file list (used only to look up saliency info ordering).
    ///   - saliencyInfo: Optional subject labels from sharpness scoring.
    func rankSimilar(
        to anchorID: UUID,
        using _: [FileItem],
        saliencyInfo: [UUID: SaliencyInfo] = [:],
    ) async {
        guard let anchorData = embeddings[anchorID] else {
            distances = [:]
            anchorFileID = nil
            sortBySimilarity = false
            return
        }

        let anchorLabel = saliencyInfo[anchorID]?.subjectLabel
        let snapshot = embeddings
        let mismatchPenalty = kSubjectMismatchPenalty

        let result: [UUID: Float]? = await Task(priority: .userInitiated) { @concurrent in
            let backend = VisionFeaturePrintBackend(revision: Self.featurePrintRevision)
            guard let anchor = Self.decodeFeaturePrint(anchorData) else {
                Logger.process.warning("SimilarityScoringModel: failed to decode anchor embedding")
                return nil
            }

            var r: [UUID: Float] = [:]
            for (id, data) in snapshot where id != anchorID {
                guard let featurePrint = Self.decodeFeaturePrint(data),
                      let distance = try? backend.distance(from: anchor, to: featurePrint)
                else { continue }
                var d = distance

                // Apply a small saliency-subject mismatch penalty so images of a
                // different subject type are ranked slightly lower, while keeping
                // the visual embedding as the dominant signal.
                //   d_out = d_visual + kSubjectMismatchPenalty    (0.10, additive
                //   in Vision feature-print distance space — typical d ≈ 0.3–1.2
                //   between unrelated images, so +0.10 is meaningful but not dominant).
                if let al = anchorLabel, let cl = saliencyInfo[id]?.subjectLabel, al != cl {
                    d += mismatchPenalty
                }

                r[id] = d
            }
            return r
        }.value

        guard let result else {
            distances = [:]
            anchorFileID = nil
            sortBySimilarity = false
            return
        }

        anchorFileID = anchorID
        distances = result
        sortBySimilarity = true
    }

    // MARK: - Burst grouping

    /// Cluster `files` into burst groups using a sequential O(n) distance pass.
    /// `files` must be sorted by effective capture time before calling.
    /// Preserves the current home/category presentation on completion.
    ///
    /// Cancels any in-flight grouping work at the top so a dragging slider
    /// does not spawn multiple concurrent feature-print decoding passes over
    /// the full embedding snapshot. Otherwise, the cooperative thread pool
    /// saturates and the UI beach-balls on large catalogs.
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
        let myGeneration = _groupingGeneration

        let threshold = burstSensitivity
        let snapshot = embeddings // [UUID: Data], Sendable
        let config = BurstGroupingConfig(visualDistanceThreshold: threshold)
        let signature = cacheSignature(fileIDs: files.map(\.id), embeddingsCount: snapshot.count)
        let cachedAdjacentDistances = _adjacentDistanceCacheSignature == signature ? _adjacentDistanceCache : [:]

        let work = Task(priority: .userInitiated) { @concurrent () -> BurstGroupingOutput? in
            let adjacentDistances = Self.computeAdjacentDistances(
                files: files,
                embeddings: snapshot,
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

        // Drop our handle only if we're still the current job.
        if _groupingTask == work {
            _groupingTask = nil
        }

        // Only the latest generation's result is allowed to touch state, and
        // we flip isGrouping off here (not via defer) so a cancelled run does
        // not briefly clear the indicator while a newer run is still active.
        guard _groupingGeneration == myGeneration else { return }
        isGrouping = false

        guard let output else { return }

        var lookup: [UUID: Int] = [:]
        for group in output.groups {
            for id in group.fileIDs {
                lookup[id] = group.id
            }
        }
        burstGroups = output.groups
        burstGroupLookup = lookup
        burstBoundaryEvidence = output.boundaryEvidence
        _adjacentDistanceCache = Dictionary(
            uniqueKeysWithValues: output.boundaryEvidence.compactMap { evidence in
                guard let distance = evidence.visualDistance else { return nil }
                return (BurstPairKey.cacheKey(previousID: evidence.previousID, currentID: evidence.currentID), distance)
            },
        )
        _adjacentDistanceCacheSignature = signature
        Logger.process.debugMessageOnly("SimilarityScoringModel: \(burstGroups.count) burst groups from \(files.count) files (threshold \(threshold))")
    }

    func applyCachedBurstAnalysis(_ snapshot: BurstAnalysisCacheSnapshot) {
        embeddings = snapshot.embeddings
        burstGroups = snapshot.groups
        burstBoundaryEvidence = snapshot.boundaryEvidence
        burstGroupLookup = Dictionary(uniqueKeysWithValues: snapshot.groups.flatMap { group in
            group.fileIDs.map { ($0, group.id) }
        })
        _adjacentDistanceCache = Dictionary(
            uniqueKeysWithValues: snapshot.boundaryEvidence.compactMap { evidence in
                guard let distance = evidence.visualDistance else { return nil }
                return (BurstPairKey.cacheKey(previousID: evidence.previousID, currentID: evidence.currentID), distance)
            },
        )
        _adjacentDistanceCacheSignature = 0
    }

    // MARK: - Static helpers

    /// Decode a thumbnail through RawParserKit, then generate an opaque package feature print.
    @concurrent
    nonisolated static func computeEmbedding(url: URL, maxPixelSize: Int) async -> Data? {
        guard !Task.isCancelled else { return nil }
        guard let cgImage = await RawParserKitImageLoader.shared.thumbnailCGImage(
            for: url,
            maxPixelSize: maxPixelSize,
        ) else {
            Logger.process.debugMessageOnly("SimilarityScoringModel: could not decode image at \(url.lastPathComponent)")
            return nil
        }
        guard !Task.isCancelled else { return nil }

        let backend = VisionFeaturePrintBackend(revision: Self.featurePrintRevision)
        do {
            let featurePrint = try await backend.featurePrint(for: cgImage)
            return encodeFeaturePrint(featurePrint)
        } catch {
            Logger.process.warning("SimilarityScoringModel: Vision feature-print request failed for \(url.lastPathComponent): \(error)")
            return nil
        }
    }

    nonisolated static func computeAdjacentDistances(
        files: [FileItem],
        embeddings: [UUID: Data],
        cached: [String: Float] = [:],
    ) -> [String: Float] {
        guard files.count > 1 else { return [:] }

        var distances = cached
        let backend = VisionFeaturePrintBackend(revision: featurePrintRevision)
        var featurePrints: [UUID: VisionFeaturePrint] = [:]

        for index in files.indices.dropFirst() {
            if index & 0x3F == 0, Task.isCancelled {
                return distances
            }
            let previousID = files[index - 1].id
            let currentID = files[index].id
            let key = BurstPairKey.cacheKey(previousID: previousID, currentID: currentID)
            if distances[key] != nil {
                continue
            }

            guard let previous = featurePrint(for: previousID, embeddings: embeddings, featurePrints: &featurePrints),
                  let current = featurePrint(for: currentID, embeddings: embeddings, featurePrints: &featurePrints),
                  let distance = try? backend.distance(from: previous, to: current)
            else { continue }
            distances[key] = distance
        }

        return distances
    }

    private nonisolated static func featurePrint(
        for id: UUID,
        embeddings: [UUID: Data],
        featurePrints: inout [UUID: VisionFeaturePrint],
    ) -> VisionFeaturePrint? {
        if let featurePrint = featurePrints[id] {
            return featurePrint
        }
        guard let data = embeddings[id],
              let featurePrint = decodeFeaturePrint(data)
        else { return nil }
        featurePrints[id] = featurePrint
        return featurePrint
    }

    private nonisolated static func encodeFeaturePrint(_ featurePrint: VisionFeaturePrint) -> Data? {
        try? JSONEncoder().encode(featurePrint)
    }

    private nonisolated static func decodeFeaturePrint(_ data: Data) -> VisionFeaturePrint? {
        try? JSONDecoder().decode(VisionFeaturePrint.self, from: data)
    }

    private nonisolated func cacheSignature(fileIDs: [UUID], embeddingsCount: Int) -> Int {
        var hasher = Hasher()
        hasher.combine(embeddingsCount)
        for id in fileIDs {
            hasher.combine(id)
        }
        return hasher.finalize()
    }
}
