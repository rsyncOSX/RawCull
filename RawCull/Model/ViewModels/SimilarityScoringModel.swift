//
//  SimilarityScoringModel.swift
//  RawCull
//

import Foundation
import ImageIO
import Observation
import Vision

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

    // MARK: Private

    @ObservationIgnored private var _indexingTask: Task<Void, Never>?

    // MARK: - Public API

    func reset() {
        cancelIndexing()
        embeddings = [:]
        distances = [:]
        anchorFileID = nil
        sortBySimilarity = false
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
    /// - Parameters:
    ///   - anchorID: The reference image's UUID.
    ///   - files: The full file list (used only to look up saliency info ordering).
    ///   - saliencyInfo: Optional subject labels from sharpness scoring.
    func rankSimilar(
        to anchorID: UUID,
        using files: [FileItem],
        saliencyInfo: [UUID: SaliencyInfo] = [:]
    ) {
        guard let anchorData = embeddings[anchorID],
              let anchor = try? NSKeyedUnarchiver.unarchivedObject(
                  ofClass: VNFeaturePrintObservation.self,
                  from: anchorData
              )
        else {
            distances = [:]
            anchorFileID = nil
            sortBySimilarity = false
            return
        }

        let anchorLabel = saliencyInfo[anchorID]?.subjectLabel

        var result: [UUID: Float] = [:]
        for (id, data) in embeddings where id != anchorID {
            guard let obs = try? NSKeyedUnarchiver.unarchivedObject(
                ofClass: VNFeaturePrintObservation.self,
                from: data
            ) else { continue }

            var d: Float = 0
            // VNFeaturePrintObservation.computeDistance(_:to:) is throws; skip on error.
            guard (try? anchor.computeDistance(&d, to: obs)) != nil else { continue }

            // Apply a small saliency-subject mismatch penalty so images of a
            // different subject type are ranked slightly lower, while keeping
            // the visual embedding as the dominant signal.
            let candidateLabel = saliencyInfo[id]?.subjectLabel
            if let al = anchorLabel, let cl = candidateLabel, al != cl {
                d += kSubjectMismatchPenalty
            }

            result[id] = d
        }

        anchorFileID = anchorID
        distances = result
        sortBySimilarity = true
    }

    // MARK: - Static helpers (nonisolated, used from detached tasks)

    /// Decode a thumbnail from a Sony ARW file and compute a Vision feature print.
    /// Returns the archived Data for the VNFeaturePrintObservation, or nil on failure.
    nonisolated static func computeEmbedding(url: URL, maxPixelSize: Int) async -> Data? {
        await Task.detached(priority: .userInitiated) {
            guard let cgImage = Self.decodeThumbnail(at: url, maxPixelSize: maxPixelSize)
                    ?? Self.decodeBinaryFallback(at: url, maxPixelSize: maxPixelSize)
            else { return nil }

            let request = VNGenerateImageFeaturePrintRequest()
            request.imageCropAndScaleOption = .scaleFill
            let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
            do {
                try handler.perform([request])
            } catch {
                return nil
            }

            guard let obs = request.results?.first as? VNFeaturePrintObservation else { return nil }
            return try? NSKeyedArchiver.archivedData(withRootObject: obs, requiringSecureCoding: true)
        }.value
    }

    /// Decode an embedded thumbnail from a Sony ARW via CGImageSource.
    nonisolated private static func decodeThumbnail(at url: URL, maxPixelSize: Int) -> CGImage? {
        let srcOptions: [CFString: Any] = [kCGImageSourceShouldCache: false]
        guard let source = CGImageSourceCreateWithURL(url as CFURL, srcOptions as CFDictionary) else { return nil }
        let thumbOptions: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageIfAbsent: false,
            kCGImageSourceCreateThumbnailFromImageAlways: false,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixelSize,
            kCGImageSourceShouldCacheImmediately: true,
        ]
        return CGImageSourceCreateThumbnailAtIndex(source, 0, thumbOptions as CFDictionary)
    }

    /// Binary fallback for ARW files where CGImageSourceCreateThumbnailAtIndex returns nil.
    nonisolated private static func decodeBinaryFallback(at url: URL, maxPixelSize: Int) -> CGImage? {
        guard let locations = SonyMakerNoteParser.embeddedJPEGLocations(from: url),
              let loc = locations.preview ?? locations.thumbnail ?? locations.fullJPEG,
              let data = SonyMakerNoteParser.readEmbeddedJPEGData(at: loc, from: url),
              let src = CGImageSourceCreateWithData(data as CFData, nil)
        else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixelSize,
            kCGImageSourceShouldCacheImmediately: true,
        ]
        return CGImageSourceCreateThumbnailAtIndex(src, 0, options as CFDictionary)
    }
}
