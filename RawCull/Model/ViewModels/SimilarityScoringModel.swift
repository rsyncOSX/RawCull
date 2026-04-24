//
//  SimilarityScoringModel.swift
//  RawCull
//

import Foundation
import ImageIO
import Observation
import OSLog
import Vision

// MARK: - BurstGroup

/// A burst group: a sequence of consecutive frames that are visually similar.
struct BurstGroup: Identifiable {
    let id: Int
    let fileIDs: [UUID] // sequential (name-sorted) order
}

// MARK: - Constants

/// Blend weight applied to the saliency-subject mismatch penalty.
/// 0 = ignore subject mismatch, 1 = equal weight with visual distance.
/// Keep small so the visual embedding remains the dominant signal.
private let kSubjectMismatchPenalty: Float = 0.10

// MARK: - Model

@Observable @MainActor
final class SimilarityScoringModel {
    // MARK: State

    /// Archived VNFeaturePrintObservation data keyed by FileItem.id.
    /// Stored as NSKeyedArchiver-encoded Data to avoid holding many
    /// large objects alive simultaneously.
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
    /// When true, the grid renders burst group section headers.
    var burstModeActive: Bool = false
    /// True while groupBursts() is running.
    var isGrouping: Bool = false

    // MARK: Private

    @ObservationIgnored private var _indexingTask: Task<Void, Never>?
    @ObservationIgnored private var _groupingTask: Task<[[UUID]]?, Never>?
    @ObservationIgnored private var _groupingGeneration: Int = 0

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
        burstModeActive = false
        isGrouping = false
        _groupingGeneration = 0
    }

    func cancelIndexing() {
        _indexingTask?.cancel()
        _indexingTask = nil
        isIndexing = false
        indexingProgress = 0
        indexingTotal = 0
        indexingEstimatedSeconds = 0
    }

    /// Compute Vision feature-print embeddings for all files using thumbnail-resolution
    /// images (same thumbnail size used by sharpness scoring).
    /// Already-embedded files are skipped for efficiency.
    func indexFiles(_ files: [FileItem], thumbnailMaxPixelSize: Int = 512) async {
        guard !files.isEmpty else { return }

        isIndexing = true
        indexingProgress = 0
        indexingTotal = files.count
        indexingEstimatedSeconds = 0
        defer { isIndexing = false }

        // Separate files that need embedding from those already done.
        let toIndex = files.filter { embeddings[$0.id] == nil }
        if toIndex.isEmpty {
            indexingProgress = files.count
            return
        }
        indexingTotal = toIndex.count

        let thumbSize = thumbnailMaxPixelSize
        let startTime = Date()
        var iterator = toIndex.makeIterator()
        var active = 0
        let maxConcurrent = 4

        let workTask = Task {
            await withTaskGroup(of: (UUID, Data?).self) { group in
                while active < maxConcurrent, let file = iterator.next() {
                    let url = file.url
                    let id = file.id
                    group.addTask(priority: .userInitiated) {
                        let data = await Self.computeEmbedding(url: url, maxPixelSize: thumbSize)
                        return (id, data)
                    }
                    active += 1
                }

                var localEmbeddings: [UUID: Data] = [:]
                var completedCount = 0

                for await (id, data) in group {
                    active -= 1
                    guard !Task.isCancelled else { break }

                    if let data { localEmbeddings[id] = data }
                    completedCount += 1
                    self.indexingProgress = completedCount

                    let elapsed = Date().timeIntervalSince(startTime)
                    if completedCount > 0, elapsed > 0 {
                        let rate = Double(completedCount) / elapsed
                        if rate > 0 {
                            let remaining = toIndex.count - completedCount
                            self.indexingEstimatedSeconds = max(0, Int(Double(remaining) / rate))
                        }
                    }

                    if let file = iterator.next() {
                        let url = file.url
                        let id = file.id
                        group.addTask(priority: .userInitiated) {
                            let data = await Self.computeEmbedding(url: url, maxPixelSize: thumbSize)
                            return (id, data)
                        }
                        active += 1
                    }
                }

                guard !Task.isCancelled else { return }
                // Merge newly computed embeddings with any pre-existing ones.
                for (id, data) in localEmbeddings {
                    self.embeddings[id] = data
                }
                Logger.process.debugMessageOnly("SimilarityScoringModel: indexed \(localEmbeddings.count)/\(toIndex.count) files")
            }
        }

        _indexingTask = workTask
        await workTask.value
        _indexingTask = nil
        guard !workTask.isCancelled else { return }

        indexingProgress = 0
        indexingTotal = 0
        indexingEstimatedSeconds = 0
    }

    /// Compute and store distances from `anchorID` to all other embedded images.
    /// Applies a small saliency-subject mismatch penalty when both images have
    /// subject labels and the labels differ.
    ///
    /// The heavy unarchiving + distance loop runs on the cooperative thread pool
    /// (via Task.detached) to avoid blocking the main thread on large catalogs.
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
        // Snapshot both dicts before hopping off the main actor — both are [UUID: Sendable].
        let snapshot = embeddings
        // Capture as a local so the file-scope constant (implicitly @MainActor under
        // SWIFT_DEFAULT_ACTOR_ISOLATION=MainActor) is safe to use inside Task.detached.
        let mismatchPenalty = kSubjectMismatchPenalty

        let result: [UUID: Float]? = await Task.detached(priority: .userInitiated) {
            // Unarchive the anchor inside the detached task so no NSObject crosses
            // actor boundaries; anchorData (Data) is Sendable.
            guard let anchor = try? NSKeyedUnarchiver.unarchivedObject(
                ofClass: VNFeaturePrintObservation.self,
                from: anchorData,
            ) else {
                Logger.process.warning("SimilarityScoringModel: failed to unarchive anchor embedding")
                return nil
            }

            var r: [UUID: Float] = [:]
            for (id, data) in snapshot where id != anchorID {
                guard let obs = try? NSKeyedUnarchiver.unarchivedObject(
                    ofClass: VNFeaturePrintObservation.self,
                    from: data,
                ) else { continue }

                var d: Float = 0
                // VNFeaturePrintObservation.computeDistance(_:to:) throws; skip on error.
                guard (try? anchor.computeDistance(&d, to: obs)) != nil else { continue }

                // Apply a small saliency-subject mismatch penalty so images of a
                // different subject type are ranked slightly lower, while keeping
                // the visual embedding as the dominant signal.
                //   d_out = d_visual + kSubjectMismatchPenalty    (0.10, additive
                //   in VNFeaturePrintObservation distance space — typical d ≈ 0.3–1.2
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
    /// `files` must be sorted by filename (= shot order) before calling.
    /// Sets `burstModeActive = true` on completion.
    ///
    /// Cancels any in-flight grouping work at the top so a dragging slider
    /// does not spawn multiple concurrent unarchive passes over the full
    /// embedding snapshot — otherwise the cooperative thread pool saturates
    /// and the UI beach-balls on large catalogs.
    func groupBursts(files: [FileItem]) async {
        guard !files.isEmpty else {
            _groupingTask?.cancel()
            _groupingTask = nil
            burstGroups = []
            burstGroupLookup = [:]
            burstModeActive = true
            return
        }

        _groupingTask?.cancel()
        _groupingTask = nil

        isGrouping = true
        _groupingGeneration &+= 1
        let myGeneration = _groupingGeneration

        let threshold = burstSensitivity
        let snapshot = embeddings // [UUID: Data], Sendable
        let fileIDs = files.map(\.id)

        let work = Task.detached(priority: .userInitiated) { () -> [[UUID]]? in
            var observations: [UUID: VNFeaturePrintObservation] = [:]
            var unarchiveCount = 0
            for (id, data) in snapshot {
                if let obs = try? NSKeyedUnarchiver.unarchivedObject(
                    ofClass: VNFeaturePrintObservation.self,
                    from: data,
                ) {
                    observations[id] = obs
                }
                unarchiveCount &+= 1
                if unarchiveCount & 0x3F == 0, Task.isCancelled { return nil }
            }

            var groups: [[UUID]] = []
            var current: [UUID] = []

            for (i, id) in fileIDs.enumerated() {
                if i & 0x3F == 0, Task.isCancelled { return nil }
                if i == 0 {
                    current.append(id)
                    continue
                }
                let prevID = fileIDs[i - 1]

                guard let obs = observations[id], let prevObs = observations[prevID] else {
                    groups.append(current)
                    current = [id]
                    continue
                }

                // Distance between the current frame and its immediate predecessor
                // in the VNFeaturePrintObservation embedding space. Smaller d ⇒ more
                // visually similar. `d >= threshold` closes the current group and
                // starts a new one; lowering `burstSensitivity` produces tighter
                // (more numerous, smaller) burst groups.
                var d: Float = 0
                let computed = (try? prevObs.computeDistance(&d, to: obs)) != nil
                let startNewGroup = !computed || d >= threshold

                if startNewGroup {
                    groups.append(current)
                    current = [id]
                } else {
                    current.append(id)
                }
            }
            if !current.isEmpty { groups.append(current) }
            return groups
        }
        _groupingTask = work

        let rawGroups = await work.value

        // Drop our handle only if we're still the current job.
        if _groupingTask == work { _groupingTask = nil }

        // Only the latest generation's result is allowed to touch state, and
        // we flip isGrouping off here (not via defer) so a cancelled run does
        // not briefly clear the indicator while a newer run is still active.
        guard _groupingGeneration == myGeneration else { return }
        isGrouping = false

        guard let rawGroups else { return }

        var lookup: [UUID: Int] = [:]
        burstGroups = rawGroups.enumerated().map { i, ids in
            for id in ids {
                lookup[id] = i
            }
            return BurstGroup(id: i, fileIDs: ids)
        }
        burstGroupLookup = lookup
        burstModeActive = true
        Logger.process.debugMessageOnly("SimilarityScoringModel: \(burstGroups.count) burst groups from \(files.count) files (threshold \(threshold))")
    }

    // MARK: - Static helpers (nonisolated, used from detached tasks)

    /// Decode a thumbnail from a Sony ARW file and compute a Vision feature print.
    /// Returns the archived Data for the VNFeaturePrintObservation, or nil on failure.
    nonisolated static func computeEmbedding(url: URL, maxPixelSize: Int) async -> Data? {
        await Task.detached(priority: .userInitiated) {
            guard let cgImage = decodeThumbnail(at: url, maxPixelSize: maxPixelSize)
                ?? decodeBinaryFallback(at: url, maxPixelSize: maxPixelSize)
            else {
                Logger.process.debugMessageOnly("SimilarityScoringModel: could not decode image at \(url.lastPathComponent)")
                return nil
            }

            let request = VNGenerateImageFeaturePrintRequest()
            request.revision = VNGenerateImageFeaturePrintRequestRevision2

            request.imageCropAndScaleOption = .scaleFill
            let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
            do {
                try handler.perform([request])
            } catch {
                Logger.process.warning("SimilarityScoringModel: Vision feature-print request failed for \(url.lastPathComponent): \(error)")
                return nil
            }

            guard let obs = request.results?.first as? VNFeaturePrintObservation else { return nil }
            return try? NSKeyedArchiver.archivedData(withRootObject: obs, requiringSecureCoding: true)
        }.value
    }

    /// Decode an embedded thumbnail from a Sony ARW via CGImageSource.
    private nonisolated static func decodeThumbnail(at url: URL, maxPixelSize: Int) -> CGImage? {
        let srcOptions: [CFString: Any] = [kCGImageSourceShouldCache: false]
        guard let source = CGImageSourceCreateWithURL(url as CFURL, srcOptions as CFDictionary) else { return nil }
        let thumbOptions: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageIfAbsent: false,
            kCGImageSourceCreateThumbnailFromImageAlways: false,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixelSize,
            kCGImageSourceShouldCacheImmediately: true
        ]
        return CGImageSourceCreateThumbnailAtIndex(source, 0, thumbOptions as CFDictionary)
    }

    /// Binary fallback for ARW files where CGImageSourceCreateThumbnailAtIndex returns nil.
    /// Sony-only: parses the Sony MakerNote directly. Other RAW formats have their own
    /// embedded-JPEG extraction paths that ImageIO handles correctly without a fallback.
    private nonisolated static func decodeBinaryFallback(at url: URL, maxPixelSize: Int) -> CGImage? {
        guard RawFormatRegistry.format(for: url) is SonyRawFormat.Type else { return nil }
        guard let locations = SonyMakerNoteParser.embeddedJPEGLocations(from: url),
              let loc = locations.preview ?? locations.thumbnail ?? locations.fullJPEG,
              let data = SonyMakerNoteParser.readEmbeddedJPEGData(at: loc, from: url),
              let src = CGImageSourceCreateWithData(data as CFData, nil)
        else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixelSize,
            kCGImageSourceShouldCacheImmediately: true
        ]
        return CGImageSourceCreateThumbnailAtIndex(src, 0, options as CFDictionary)
    }
}
