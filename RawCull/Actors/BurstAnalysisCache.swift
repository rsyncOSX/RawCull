import CryptoKit
import Foundation
import OSLog
import PhotoAIContracts
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
    var embeddings: [UUID: SimilarityArtifact]
    var sharpnessScores: [UUID: Float]
    var saliencyInfo: [UUID: SaliencyInfo]
    var groups: [BurstGroup]
    var boundaryEvidence: [BurstBoundaryEvidence]
    var results: [BurstAnalysisResult]
    var reviewStateSnapshots: [BurstReviewStateSnapshot]
    var similarityArtifactSetDigest: String?
}

nonisolated struct BurstSimilaritySignature: Codable, Equatable {
    var groupingConfig: BurstGroupingConfig
    var backendDescriptor: SimilarityBackendDescriptor
    var artifactBackendDescriptors: [SimilarityBackendDescriptor]
    var artifactSchemaVersion: Int
    var embeddingThumbnailMaxPixelSize: Int
    var embeddingPipelineVersion: Int

    init(
        groupingConfig: BurstGroupingConfig,
        backendDescriptor: SimilarityBackendDescriptor,
        artifactBackendDescriptors: [SimilarityBackendDescriptor]? = nil,
        artifactSchemaVersion: Int,
        embeddingThumbnailMaxPixelSize: Int,
        embeddingPipelineVersion: Int,
    ) {
        self.groupingConfig = groupingConfig
        self.backendDescriptor = backendDescriptor
        self.artifactBackendDescriptors = artifactBackendDescriptors ?? [backendDescriptor]
        self.artifactSchemaVersion = artifactSchemaVersion
        self.embeddingThumbnailMaxPixelSize = embeddingThumbnailMaxPixelSize
        self.embeddingPipelineVersion = embeddingPipelineVersion
    }

    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.groupingConfig == rhs.groupingConfig
            && lhs.backendDescriptor == rhs.backendDescriptor
            && lhs.artifactBackendDescriptors == rhs.artifactBackendDescriptors
            && lhs.artifactSchemaVersion == rhs.artifactSchemaVersion
            && lhs.embeddingThumbnailMaxPixelSize == rhs.embeddingThumbnailMaxPixelSize
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
    nonisolated static let schemaVersion = 9
    nonisolated static let legacyArtifactMigrationSchemaVersion = 8

    private let cacheDirectory: URL

    nonisolated var storageDirectory: URL {
        cacheDirectory
    }

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
        Logger.process.debugMessageOnly(
            "BurstAnalysisCache.load(): checking cache for \(files.count) files",
        )
        guard !Task.isCancelled else {
            Logger.process.debugMessageOnly(
                "BurstAnalysisCache.load(): cancelled before loading",
            )
            return nil
        }
        let url = cacheURL(for: catalog)
        guard FileManager.default.fileExists(atPath: url.path) else {
            Logger.process.debugMessageOnly(
                "BurstAnalysisCache.load(): no cache file exists",
            )
            return nil
        }
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
                Logger.process.debugMessageOnly(
                    "BurstAnalysisCache.load(): cache snapshot is stale or invalid",
                )
                return nil
            }
            Logger.process.debugMessageOnly(
                "BurstAnalysisCache.load(): valid cache snapshot loaded",
            )
            return snapshot
        } catch {
            Logger.process.debugMessageOnly(
                "BurstAnalysisCache.load(): cache read failed: \(error)",
            )
            return nil
        }
    }

    func save(_ snapshot: BurstAnalysisCacheSnapshot, catalog: URL) async {
        Logger.process.debugMessageOnly(
            "BurstAnalysisCache.save(): saving snapshot with \(snapshot.files.count) files",
        )
        guard !Task.isCancelled else {
            Logger.process.debugMessageOnly(
                "BurstAnalysisCache.save(): cancelled before saving",
            )
            return
        }
        do {
            try FileManager.default.createDirectory(at: cacheDirectory, withIntermediateDirectories: true)
            let data = try JSONEncoder().encode(snapshot)
            guard !Task.isCancelled else { return }
            try data.write(to: cacheURL(for: catalog), options: [.atomic])
            Logger.process.debugMessageOnly(
                "BurstAnalysisCache.save(): snapshot saved",
            )
        } catch {
            Logger.process.debugMessageOnly(
                "BurstAnalysisCache.save(): cache write failed: \(error)",
            )
            return
        }
    }

    /// Decode a known burst-cache schema without applying catalog-wide
    /// validity rules. Callers may import only individually validated artifacts
    /// and stable review-state signatures from this migration candidate.
    func loadMigrationCandidate(catalog: URL) -> BurstAnalysisCacheSnapshot? {
        let url = cacheURL(for: catalog)
        guard FileManager.default.fileExists(atPath: url.path),
              let data = try? Data(contentsOf: url, options: .mappedIfSafe),
              let snapshot = try? JSONDecoder().decode(
                  BurstAnalysisCacheSnapshot.self,
                  from: data,
              ),
              snapshot.schemaVersion == Self.schemaVersion
              || snapshot.schemaVersion == Self.legacyArtifactMigrationSchemaVersion
        else { return nil }
        return snapshot
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

    func getDiskCacheUsage() async -> (size: Int, fileCount: Int) {
        let directory = cacheDirectory

        return await Task.detached(priority: .utility) {
            let fileManager = FileManager.default
            let resourceKeys: Set<URLResourceKey> = [
                .isRegularFileKey,
                .totalFileAllocatedSizeKey
            ]

            guard let urls = try? fileManager.contentsOfDirectory(
                at: directory,
                includingPropertiesForKeys: Array(resourceKeys),
                options: .skipsHiddenFiles,
            ) else { return (0, 0) }

            var size = 0
            var fileCount = 0
            for fileURL in urls {
                guard let values = try? fileURL.resourceValues(forKeys: resourceKeys),
                      values.isRegularFile == true
                else { continue }
                size += values.totalFileAllocatedSize ?? 0
                fileCount += 1
            }
            return (size, fileCount)
        }.value
    }

    func clear() async {
        let directory = cacheDirectory

        await Task.detached(priority: .utility) {
            let fileManager = FileManager.default
            guard let urls = try? fileManager.contentsOfDirectory(
                at: directory,
                includingPropertiesForKeys: nil,
                options: .skipsHiddenFiles,
            ) else { return }

            for fileURL in urls {
                try? fileManager.removeItem(at: fileURL)
            }
        }.value
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
              snapshot.similarityArtifactSetDigest != nil,
              snapshot.similaritySignature.artifactSchemaVersion
              == SimilarityArtifactDescriptor.currentSchemaVersion,
              snapshot.files.count == files.count
        else { return false }

        let cached = Dictionary(uniqueKeysWithValues: snapshot.files.map { ($0.path, $0) })
        for file in files {
            guard let item = cached[file.url.path],
                  item.size == file.size,
                  abs(item.modificationDate.timeIntervalSince(file.dateModified)) < 0.001
            else { return false }
            if let artifact = snapshot.embeddings[item.id],
               !RawCullSimilarityArtifactValidation.isCurrent(
                   artifact,
                   for: SimilarityScoringModel.source(for: file),
                   backends: similaritySignature.artifactBackendDescriptors,
               ) {
                return false
            }
        }

        let cachedFileIDs = Set(snapshot.files.map(\.id))
        let embeddedFileIDs = Set(snapshot.embeddings.keys)
        guard embeddedFileIDs.isSubset(of: cachedFileIDs),
              snapshot.groups.allSatisfy({ group in
                  group.fileIDs.allSatisfy(embeddedFileIDs.contains)
              }),
              snapshot.boundaryEvidence.allSatisfy({ evidence in
                  embeddedFileIDs.contains(evidence.previousID)
                      && embeddedFileIDs.contains(evidence.currentID)
              }),
              snapshot.results.allSatisfy({ result in
                  result.fileIDs.allSatisfy(embeddedFileIDs.contains)
                      && result.candidates.allSatisfy {
                          embeddedFileIDs.contains($0.fileID)
                      }
                      && (result.recommendedFileID.map(embeddedFileIDs.contains) ?? true)
                      && (result.secondBestFileID.map(embeddedFileIDs.contains) ?? true)
              })
        else { return false }
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

    nonisolated static func artifactSetDigest(
        files: [FileItem],
        artifacts: [UUID: SimilarityArtifact],
    ) -> String {
        let entries = files.compactMap { file -> ArtifactDigestEntry? in
            guard let artifact = artifacts[file.id] else { return nil }
            return ArtifactDigestEntry(
                standardizedPath: file.url.standardizedFileURL.path,
                descriptor: artifact.descriptor,
                payloadDigest: SHA256.hash(data: artifact.payload).map {
                    String(format: "%02x", $0)
                }.joined(),
            )
        }.sorted { $0.standardizedPath < $1.standardizedPath }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let data = (try? encoder.encode(entries)) ?? Data()
        return SHA256.hash(data: data).map {
            String(format: "%02x", $0)
        }.joined()
    }
}

private nonisolated struct ArtifactDigestEntry: Codable, Sendable {
    let standardizedPath: String
    let descriptor: SimilarityArtifactDescriptor
    let payloadDigest: String
}
