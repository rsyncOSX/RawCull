import CryptoKit
import Foundation

nonisolated struct SimilarityArtifactPipelineSignature: Codable, Equatable, Hashable, Sendable {
    let thumbnailMaxPixelSize: Int
    let pipelineVersion: Int
}

nonisolated enum PerFileAnalysisArtifactCacheMissReason: Equatable, Sendable {
    case notFound
    case corrupt
    case incompatible
}

nonisolated struct PerFileAnalysisArtifactCacheMiss: Equatable, Sendable {
    let sourceID: UUID
    let reason: PerFileAnalysisArtifactCacheMissReason
}

nonisolated struct PerFileAnalysisArtifactLoadResult: Sendable {
    let artifacts: [UUID: SimilarityArtifact]
    let misses: [PerFileAnalysisArtifactCacheMiss]
}

nonisolated struct PerFileAnalysisArtifactWriteFailure: Equatable, Sendable {
    let sourceID: UUID
    let sourcePath: String
    let message: String
}

nonisolated struct PerFileAnalysisArtifactCommitResult: Sendable {
    let committedSourceIDs: Set<UUID>
    let failures: [PerFileAnalysisArtifactWriteFailure]
    let wasCancelled: Bool
}

nonisolated struct PerFileAnalysisArtifactStoreUsage: Equatable, Sendable {
    let size: Int
    let entryCount: Int
}

protocol SimilarityArtifactStoring: Actor {
    func load(
        sources: [AIImageSource],
        allowedBackends: [SimilarityBackendDescriptor],
        pipeline: SimilarityArtifactPipelineSignature,
    ) async -> PerFileAnalysisArtifactLoadResult

    func upsert(
        artifacts: [UUID: SimilarityArtifact],
        sources: [UUID: AIImageSource],
        pipeline: SimilarityArtifactPipelineSignature,
    ) async -> PerFileAnalysisArtifactCommitResult

    func remove(
        source: AIImageSource,
        backend: SimilarityBackendDescriptor,
        pipeline: SimilarityArtifactPipelineSignature,
    ) async
}

typealias PerFileAnalysisArtifactWriteBarrier = @Sendable (
    _ sourceID: UUID,
    _ committedSourceIDs: Set<UUID>,
) async -> Void

/// RawCull-owned, per-source persistence for Vision feature-print artifacts.
///
/// Records are deliberately stored one per file/backend/pipeline identity. Each
/// mutation is actor-isolated and uses atomic replacement, so cancellation can
/// stop later commits without invalidating records already written.
/// Source paths follow `SourceFingerprint` semantics: moving or renaming a file
/// is a cache miss; this store does not add implicit content hashing.
actor PerFileAnalysisArtifactStore: SimilarityArtifactStoring {
    static let shared = PerFileAnalysisArtifactStore()
    nonisolated static let recordSchemaVersion = 2

    nonisolated let storageDirectory: URL
    private let writeBarrier: PerFileAnalysisArtifactWriteBarrier?

    init(
        storageDirectory: URL? = nil,
        writeBarrier: PerFileAnalysisArtifactWriteBarrier? = nil,
    ) {
        self.writeBarrier = writeBarrier
        if let storageDirectory {
            self.storageDirectory = storageDirectory
        } else {
            let base = FileManager.default.urls(
                for: .applicationSupportDirectory,
                in: .userDomainMask,
            ).first ?? FileManager.default.temporaryDirectory
            self.storageDirectory = base
                .appendingPathComponent("RawCull", isDirectory: true)
                .appendingPathComponent("AnalysisArtifacts", isDirectory: true)
                .appendingPathComponent("VisionSimilarity", isDirectory: true)
        }
    }

    func load(
        sources: [AIImageSource],
        allowedBackends: [SimilarityBackendDescriptor],
        pipeline: SimilarityArtifactPipelineSignature,
    ) async -> PerFileAnalysisArtifactLoadResult {
        var artifacts: [UUID: SimilarityArtifact] = [:]
        var misses: [PerFileAnalysisArtifactCacheMiss] = []
        artifacts.reserveCapacity(sources.count)
        misses.reserveCapacity(sources.count)

        for source in sources {
            if Task.isCancelled {
                break
            }

            let sourceFingerprint = SourceFingerprint(source: source)
            var sourceMissReason: PerFileAnalysisArtifactCacheMissReason = .notFound

            for backend in allowedBackends {
                let identity = LookupIdentity(
                    sourceFingerprint: sourceFingerprint,
                    artifactSchemaVersion: SimilarityArtifactDescriptor.currentSchemaVersion,
                    backend: backend,
                    pipeline: pipeline,
                )
                let url = recordURL(for: identity)
                guard FileManager.default.fileExists(atPath: url.path) else {
                    continue
                }

                do {
                    var record = try decodeRecord(at: url)
                    guard record.schemaVersion == Self.recordSchemaVersion,
                          record.identity == identity
                    else {
                        sourceMissReason = .incompatible
                        try? FileManager.default.removeItem(at: url)
                        continue
                    }
                    let artifact = record.artifact
                    guard RawCullSimilarityArtifactValidation.isCurrent(
                        artifact,
                        for: source,
                        backend: backend,
                    )
                    else {
                        sourceMissReason = .incompatible
                        try? FileManager.default.removeItem(at: url)
                        continue
                    }

                    artifacts[source.id] = artifact
                    if Date().timeIntervalSince(record.lastAccessedAt) >= 86400 {
                        record.lastAccessedAt = Date()
                        try? encode(record).write(to: url, options: .atomic)
                    }
                    break
                } catch {
                    sourceMissReason = .corrupt
                    try? FileManager.default.removeItem(at: url)
                }
            }

            if artifacts[source.id] == nil {
                misses.append(
                    PerFileAnalysisArtifactCacheMiss(
                        sourceID: source.id,
                        reason: sourceMissReason,
                    ),
                )
            }
        }

        return PerFileAnalysisArtifactLoadResult(
            artifacts: artifacts,
            misses: misses,
        )
    }

    func upsert(
        artifacts: [UUID: SimilarityArtifact],
        sources: [UUID: AIImageSource],
        pipeline: SimilarityArtifactPipelineSignature,
    ) async -> PerFileAnalysisArtifactCommitResult {
        var committedSourceIDs: Set<UUID> = []
        var failures: [PerFileAnalysisArtifactWriteFailure] = []

        do {
            try FileManager.default.createDirectory(
                at: storageDirectory,
                withIntermediateDirectories: true,
            )
        } catch {
            return PerFileAnalysisArtifactCommitResult(
                committedSourceIDs: [],
                failures: artifacts.keys.compactMap { sourceID in
                    guard let source = sources[sourceID] else { return nil }
                    return PerFileAnalysisArtifactWriteFailure(
                        sourceID: sourceID,
                        sourcePath: source.url.path,
                        message: String(describing: error),
                    )
                },
                wasCancelled: Task.isCancelled,
            )
        }

        let orderedArtifacts = artifacts.sorted { lhs, rhs in
            let leftPath = sources[lhs.key]?.url.path ?? lhs.key.uuidString
            let rightPath = sources[rhs.key]?.url.path ?? rhs.key.uuidString
            return leftPath < rightPath
        }
        var knownRecords = recordURLs().compactMap { url -> (URL, StoredRecord)? in
            guard let record = try? decodeRecord(at: url) else { return nil }
            return (url, record)
        }

        for (sourceID, artifact) in orderedArtifacts {
            await writeBarrier?(sourceID, committedSourceIDs)
            guard !Task.isCancelled else {
                return cancelledArtifactCommit(committedSourceIDs, failures)
            }
            guard let source = sources[sourceID] else {
                failures.append(
                    PerFileAnalysisArtifactWriteFailure(
                        sourceID: sourceID,
                        sourcePath: artifact.descriptor.sourceFingerprint.standardizedPath,
                        message: "The source metadata required to persist the artifact is unavailable.",
                    ),
                )
                continue
            }

            do {
                let backend = SimilarityBackendDescriptor(
                    backend: artifact.descriptor.backend,
                    modelFingerprint: artifact.descriptor.modelFingerprint,
                    representation: artifact.descriptor.representation,
                    preprocessingVersion: artifact.descriptor.preprocessingVersion,
                    normalizationVersion: artifact.descriptor.normalizationVersion,
                    configurationVersion: artifact.descriptor.configurationVersion,
                )
                let identity = LookupIdentity(
                    sourceFingerprint: SourceFingerprint(source: source),
                    artifactSchemaVersion: artifact.descriptor.schemaVersion,
                    backend: backend,
                    pipeline: pipeline,
                )
                guard artifact.descriptor.sourceFingerprint == identity.sourceFingerprint,
                      artifact.descriptor.schemaVersion
                      == SimilarityArtifactDescriptor.currentSchemaVersion
                else {
                    throw StoreError.incompatibleArtifact
                }

                let url = recordURL(for: identity)
                let now = Date()
                let existingCreatedAt = (try? decodeRecord(at: url))?.createdAt
                let record = StoredRecord(
                    schemaVersion: Self.recordSchemaVersion,
                    identity: identity,
                    sourceDisplayName: source.displayName,
                    artifact: artifact,
                    createdAt: existingCreatedAt ?? now,
                    lastAccessedAt: now,
                )
                try encode(record).write(to: url, options: .atomic)
                for (knownURL, knownRecord) in knownRecords
                    where knownURL != url
                    && knownRecord.identity.isSuperseded(by: identity) {
                    try? FileManager.default.removeItem(at: knownURL)
                }
                knownRecords.removeAll { knownRecord in
                    knownRecord.0 == url
                        || knownRecord.1.identity.isSuperseded(by: identity)
                }
                knownRecords.append((url, record))
                committedSourceIDs.insert(sourceID)
            } catch {
                failures.append(
                    PerFileAnalysisArtifactWriteFailure(
                        sourceID: sourceID,
                        sourcePath: source.url.path,
                        message: String(describing: error),
                    ),
                )
            }
        }

        return PerFileAnalysisArtifactCommitResult(
            committedSourceIDs: committedSourceIDs,
            failures: failures,
            wasCancelled: false,
        )
    }

    func remove(
        source: AIImageSource,
        backend: SimilarityBackendDescriptor,
        pipeline: SimilarityArtifactPipelineSignature,
    ) async {
        let identity = LookupIdentity(
            sourceFingerprint: SourceFingerprint(source: source),
            artifactSchemaVersion: SimilarityArtifactDescriptor.currentSchemaVersion,
            backend: backend,
            pipeline: pipeline,
        )
        let url = recordURL(for: identity)
        try? FileManager.default.removeItem(at: url)
    }

    func usage() -> PerFileAnalysisArtifactStoreUsage {
        let keys: Set<URLResourceKey> = [
            .isRegularFileKey,
            .totalFileAllocatedSizeKey
        ]
        guard let urls = try? FileManager.default.contentsOfDirectory(
            at: storageDirectory,
            includingPropertiesForKeys: Array(keys),
            options: .skipsHiddenFiles,
        ) else {
            return PerFileAnalysisArtifactStoreUsage(size: 0, entryCount: 0)
        }

        var size = 0
        var entryCount = 0
        for url in urls where url.pathExtension == "json" {
            guard let values = try? url.resourceValues(forKeys: keys),
                  values.isRegularFile == true
            else { continue }
            size += values.totalFileAllocatedSize ?? 0
            entryCount += 1
        }
        return PerFileAnalysisArtifactStoreUsage(
            size: size,
            entryCount: entryCount,
        )
    }

    func clear() {
        guard let urls = try? FileManager.default.contentsOfDirectory(
            at: storageDirectory,
            includingPropertiesForKeys: nil,
            options: .skipsHiddenFiles,
        ) else { return }
        for url in urls {
            try? FileManager.default.removeItem(at: url)
        }
    }

    private func recordURLs() -> [URL] {
        (try? FileManager.default.contentsOfDirectory(
            at: storageDirectory,
            includingPropertiesForKeys: nil,
            options: .skipsHiddenFiles,
        ))?.filter { $0.pathExtension == "json" } ?? []
    }

    private func recordURL(for identity: LookupIdentity) -> URL {
        storageDirectory
            .appendingPathComponent(cacheKey(for: identity), isDirectory: false)
            .appendingPathExtension("json")
    }

    private func cacheKey(for identity: LookupIdentity) -> String {
        let data = (try? encode(identity)) ?? Data()
        return SHA256.hash(data: data).map {
            String(format: "%02x", $0)
        }.joined()
    }

    private func decodeRecord(at url: URL) throws -> StoredRecord {
        try JSONDecoder().decode(
            StoredRecord.self,
            from: Data(contentsOf: url, options: .mappedIfSafe),
        )
    }

    private func encode(_ value: some Encodable) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return try encoder.encode(value)
    }
}

private nonisolated func cancelledArtifactCommit(
    _ committedSourceIDs: Set<UUID>,
    _ failures: [PerFileAnalysisArtifactWriteFailure],
) -> PerFileAnalysisArtifactCommitResult {
    PerFileAnalysisArtifactCommitResult(
        committedSourceIDs: committedSourceIDs,
        failures: failures,
        wasCancelled: true,
    )
}

private nonisolated struct LookupIdentity: Codable, Equatable, Sendable {
    let sourceFingerprint: SourceFingerprint
    let artifactSchemaVersion: Int
    let backend: SimilarityBackendDescriptor
    let pipeline: SimilarityArtifactPipelineSignature

    func isSuperseded(by current: Self) -> Bool {
        sourceFingerprint.standardizedPath == current.sourceFingerprint.standardizedPath
            && artifactSchemaVersion == current.artifactSchemaVersion
            && backend == current.backend
            && pipeline == current.pipeline
            && sourceFingerprint != current.sourceFingerprint
    }
}

private nonisolated struct StoredRecord: Codable, Sendable {
    let schemaVersion: Int
    let identity: LookupIdentity
    let sourceDisplayName: String
    let artifact: SimilarityArtifact
    let createdAt: Date
    var lastAccessedAt: Date
}

private nonisolated enum StoreError: Error, Equatable, Sendable {
    case incompatibleArtifact
}
