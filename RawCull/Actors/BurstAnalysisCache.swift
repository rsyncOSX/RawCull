import Foundation
import PhotoAnalysisKit
import RawCullCore

nonisolated struct BurstAnalysisCacheSnapshot: Codable, Equatable {
    var schemaVersion: Int
    var algorithmVersion: Int
    var catalogPath: String
    var thumbnailMaxPixelSize: Int
    var sharpnessSignature: BurstSharpnessSignature
    var similaritySignature: BurstSimilaritySignature
    var files: [BurstAnalysisCacheFile]
    var embeddings: [UUID: Data]
    var sharpnessScores: [UUID: Float]
    var saliencyInfo: [UUID: SaliencyInfo]
    var groups: [BurstGroup]
    var boundaryEvidence: [BurstBoundaryEvidence]
    var results: [BurstAnalysisResult]
    var reviewStateSnapshots: [BurstReviewStateSnapshot]
}

nonisolated struct BurstSimilaritySignature: Codable, Equatable {
    var groupingConfig: BurstGroupingConfig
    var embeddingThumbnailMaxPixelSize: Int
    var visionFeaturePrintRevision: Int
    var embeddingPipelineVersion: Int

    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.groupingConfig == rhs.groupingConfig
            && lhs.embeddingThumbnailMaxPixelSize == rhs.embeddingThumbnailMaxPixelSize
            && lhs.visionFeaturePrintRevision == rhs.visionFeaturePrintRevision
            && lhs.embeddingPipelineVersion == rhs.embeddingPipelineVersion
    }
}

nonisolated struct SharpnessScoringSignature: Codable, Equatable {
    /// Nil only when decoding the legacy RawCull-owned signature. Legacy values
    /// remain readable but compare stale against every current package descriptor.
    var analysisDescriptor: SharpnessAnalysisDescriptor?
    var scoringSource: SharpnessScoringSource
    var thumbnailMaxPixelSize: Int

    @MainActor
    init(
        scoringSource: SharpnessScoringSource = .embeddedPreview,
        thumbnailMaxPixelSize: Int,
        config: FocusDetectorConfig,
    ) {
        analysisDescriptor = PhotoAnalyzer.sharpnessDescriptor(for: config)
        self.scoringSource = scoringSource
        self.thumbnailMaxPixelSize = thumbnailMaxPixelSize
    }

    private enum CodingKeys: String, CodingKey {
        case analysisDescriptor
        case scoringSource
        case thumbnailMaxPixelSize
    }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        analysisDescriptor = try values.decodeIfPresent(
            SharpnessAnalysisDescriptor.self,
            forKey: .analysisDescriptor,
        )
        scoringSource = (try? values.decode(
            SharpnessScoringSource.self,
            forKey: .scoringSource,
        )) ?? .embeddedPreview
        thumbnailMaxPixelSize = (try? values.decode(
            Int.self,
            forKey: .thumbnailMaxPixelSize,
        )) ?? 0
    }

    func encode(to encoder: Encoder) throws {
        var values = encoder.container(keyedBy: CodingKeys.self)
        try values.encodeIfPresent(
            analysisDescriptor,
            forKey: .analysisDescriptor,
        )
        try values.encode(scoringSource, forKey: .scoringSource)
        try values.encode(
            thumbnailMaxPixelSize,
            forKey: .thumbnailMaxPixelSize,
        )
    }
}

typealias BurstSharpnessSignature = SharpnessScoringSignature

nonisolated struct BurstAnalysisCacheFile: Codable, Equatable {
    var id: UUID
    var path: String
    var size: Int64
    var modificationDate: Date
}

actor BurstAnalysisCache {
    static let shared = BurstAnalysisCache()
    nonisolated static let schemaVersion = 4

    private let cacheDirectory: URL

    init(cacheDirectory: URL? = nil) {
        if let cacheDirectory {
            self.cacheDirectory = cacheDirectory
        } else {
            let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
                ?? FileManager.default.temporaryDirectory
            self.cacheDirectory = base
                .appendingPathComponent("RawCull", isDirectory: true)
                .appendingPathComponent("BurstAnalysis", isDirectory: true)
        }
    }

    func load(
        catalog: URL,
        files: [FileItem],
        thumbnailMaxPixelSize: Int,
        sharpnessSignature: BurstSharpnessSignature,
        similaritySignature: BurstSimilaritySignature,
    ) async -> BurstAnalysisCacheSnapshot? {
        guard !Task.isCancelled else { return nil }
        let url = cacheURL(for: catalog)
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        do {
            let data = try Data(contentsOf: url)
            guard !Task.isCancelled else { return nil }
            let snapshot = try JSONDecoder().decode(BurstAnalysisCacheSnapshot.self, from: data)
            guard !Task.isCancelled else { return nil }
            guard isValid(
                snapshot,
                catalog: catalog,
                files: files,
                thumbnailMaxPixelSize: thumbnailMaxPixelSize,
                sharpnessSignature: sharpnessSignature,
                similaritySignature: similaritySignature,
            ) else {
                return nil
            }
            return snapshot
        } catch {
            return nil
        }
    }

    func save(_ snapshot: BurstAnalysisCacheSnapshot, catalog: URL) async {
        guard !Task.isCancelled else { return }
        do {
            try FileManager.default.createDirectory(at: cacheDirectory, withIntermediateDirectories: true)
            let data = try JSONEncoder().encode(snapshot)
            guard !Task.isCancelled else { return }
            try data.write(to: cacheURL(for: catalog), options: [.atomic])
        } catch {
            return
        }
    }

    func delete(catalog: URL) async {
        let url = cacheURL(for: catalog)
        guard FileManager.default.fileExists(atPath: url.path) else { return }
        do {
            try FileManager.default.removeItem(at: url)
        } catch {
            return
        }
    }

    private func isValid(
        _ snapshot: BurstAnalysisCacheSnapshot,
        catalog: URL,
        files: [FileItem],
        thumbnailMaxPixelSize: Int,
        sharpnessSignature: BurstSharpnessSignature,
        similaritySignature: BurstSimilaritySignature,
    ) -> Bool {
        guard snapshot.schemaVersion == Self.schemaVersion,
              snapshot.algorithmVersion == BurstGroupingConfig.algorithmVersion,
              snapshot.catalogPath == catalog.path,
              snapshot.thumbnailMaxPixelSize == thumbnailMaxPixelSize,
              snapshot.sharpnessSignature == sharpnessSignature,
              snapshot.similaritySignature == similaritySignature,
              snapshot.files.count == files.count
        else { return false }

        let cached = Dictionary(uniqueKeysWithValues: snapshot.files.map { ($0.path, $0) })
        for file in files {
            guard let item = cached[file.url.path],
                  item.size == file.size,
                  abs(item.modificationDate.timeIntervalSince(file.dateModified)) < 0.001
            else { return false }
        }
        return true
    }

    private func cacheURL(for catalog: URL) -> URL {
        cacheDirectory.appendingPathComponent(cacheFileName(for: catalog), isDirectory: false)
    }

    private nonisolated func cacheFileName(for catalog: URL) -> String {
        let safe = Data(catalog.path.utf8)
            .base64EncodedString()
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "=", with: "")
        return "\(safe).json"
    }
}
