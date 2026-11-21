import CryptoKit
import Foundation
import OSLog
import PhotoAIContracts
import PhotoAIStorage

nonisolated struct SimilarityArtifactPipelineSignature: Codable, Equatable, Hashable, Sendable {
    let thumbnailMaxPixelSize: Int
    let pipelineVersion: Int
}

nonisolated enum PerFileAnalysisArtifactCacheMissReason: Equatable, Sendable {
    case notFound
    case corrupt
    case incompatible
    /// The record exists but could not be read (volume, permission or I/O
    /// failure). `load` never deletes it, because the failure may be temporary.
    /// The caller still has no embedding, so indexing regenerates one and
    /// `upsert` replaces the record's contents with that equivalent version.
    /// The atomic write keeps the file's existing permissions, so a record that
    /// was unreadable for permission reasons stays unreadable until they change.
    case unreadable
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

/// RawCull-owned, per-source persistence for opaque PhotoAIKit similarity artifacts.
///
/// Records are deliberately stored one per file/backend/pipeline identity. Each
/// mutation is actor-isolated and uses atomic replacement, so cancellation can
/// stop later commits without invalidating records already written.
/// Source paths follow `SourceFingerprint` semantics: moving or renaming a file
/// is a cache miss; this store does not add implicit content hashing.
actor PerFileAnalysisArtifactStore: SimilarityArtifactStoring {
    static let shared = PerFileAnalysisArtifactStore()
    nonisolated static let recordSchemaVersion = 1

    nonisolated let storageDirectory: URL
    private let writeBarrier: PerFileAnalysisArtifactWriteBarrier?
    /// Record files grouped by everything in their identity except the source
    /// fingerprint, so an upsert finds the records it supersedes without
    /// decoding the whole store. Built once, from identities only, on first use.
    private var supersessionIndex: [SupersessionKey: Set<URL>]?
    /// Test seam: number of record files decoded (full or identity-only).
    private(set) var decodedRecordCount = 0

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
                .appendingPathComponent("Similarity", isDirectory: true)
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
                let url: URL
                do {
                    url = try recordURL(for: identity)
                } catch {
                    Logger.process.warning(
                        "PerFileAnalysisArtifactStore: could not derive a record key: \(error.localizedDescription, privacy: .public)",
                    )
                    continue
                }
                guard FileManager.default.fileExists(atPath: url.path) else {
                    continue
                }

                let data: Data
                do {
                    data = try Data(contentsOf: url, options: .mappedIfSafe)
                } catch {
                    // Never delete on a read failure: an unmounted volume, a
                    // sandbox hiccup or a racing writer would otherwise wipe a
                    // valid artifact. If the caller re-indexes this source, the
                    // atomic write in `upsert` replaces the record's contents
                    // with an equivalent artifact (keeping file permissions).
                    sourceMissReason = .unreadable
                    Logger.process.warning(
                        "PerFileAnalysisArtifactStore: could not read \(url.lastPathComponent, privacy: .public): \(error.localizedDescription, privacy: .public)",
                    )
                    continue
                }

                do {
                    var record = try decodeRecord(from: data)
                    guard record.schemaVersion == Self.recordSchemaVersion,
                          record.identity == identity
                    else {
                        sourceMissReason = .incompatible
                        try? FileManager.default.removeItem(at: url)
                        continue
                    }
                    let artifact = try SimilarityArtifactCodec.decode(record.artifactData)
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
                        do {
                            try encode(record).write(to: url, options: .atomic)
                        } catch {
                            Logger.process.warning(
                                "PerFileAnalysisArtifactStore: could not refresh last access for \(url.lastPathComponent, privacy: .public): \(error.localizedDescription, privacy: .public)",
                            )
                        }
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
        // Mutated in place (not copied): upsert suspends at the write barrier,
        // and a concurrent upsert must not lose its index updates.
        loadSupersessionIndexIfNeeded()

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

                let url = try recordURL(for: identity)
                let now = Date()
                let existingCreatedAt = (try? decodeRecord(at: url))?.createdAt
                let record = try StoredRecord(
                    schemaVersion: Self.recordSchemaVersion,
                    identity: identity,
                    sourceDisplayName: source.displayName,
                    artifactData: SimilarityArtifactCodec.encode(artifact),
                    createdAt: existingCreatedAt ?? now,
                    lastAccessedAt: now,
                )
                try encode(record).write(to: url, options: .atomic)
                // Same path/schema/backend/pipeline with another fingerprint is
                // an older version of this source's record.
                let key = SupersessionKey(identity)
                for knownURL in supersessionIndex?[key] ?? [] where knownURL != url {
                    try? FileManager.default.removeItem(at: knownURL)
                }
                supersessionIndex?[key] = [url]
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
        let url: URL
        do {
            url = try recordURL(for: identity)
        } catch {
            Logger.process.warning(
                "PerFileAnalysisArtifactStore: could not derive a record key to remove: \(error.localizedDescription, privacy: .public)",
            )
            return
        }
        try? FileManager.default.removeItem(at: url)
        supersessionIndex?[SupersessionKey(identity)]?.remove(url)
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
        supersessionIndex = [:]
    }

    private func loadSupersessionIndexIfNeeded() {
        guard supersessionIndex == nil else { return }
        var index: [SupersessionKey: Set<URL>] = [:]
        for url in recordURLs() {
            guard let identity = try? decodeIdentity(at: url) else { continue }
            index[SupersessionKey(identity), default: []].insert(url)
        }
        supersessionIndex = index
    }

    private func recordURLs() -> [URL] {
        (try? FileManager.default.contentsOfDirectory(
            at: storageDirectory,
            includingPropertiesForKeys: nil,
            options: .skipsHiddenFiles,
        ))?.filter { $0.pathExtension == "json" } ?? []
    }

    private func recordURL(for identity: LookupIdentity) throws -> URL {
        try storageDirectory
            .appendingPathComponent(Self.cacheKey(for: identity), isDirectory: false)
            .appendingPathExtension("json")
    }

    /// The on-disk key for a record identity. Throws when the identity cannot
    /// be encoded (for example a NaN modification date). It must never fall
    /// back to a constant key, or every such identity would share one file and
    /// a cached artifact could be served for the wrong photo.
    nonisolated static func cacheKey(for identity: some Encodable) throws -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let data = try encoder.encode(identity)
        return SHA256.hash(data: data).map {
            String(format: "%02x", $0)
        }.joined()
    }

    private func decodeIdentity(at url: URL) throws -> LookupIdentity {
        decodedRecordCount += 1
        return try JSONDecoder().decode(
            StoredRecordIdentity.self,
            from: Data(contentsOf: url, options: .mappedIfSafe),
        ).identity
    }

    private func decodeRecord(at url: URL) throws -> StoredRecord {
        try decodeRecord(from: Data(contentsOf: url, options: .mappedIfSafe))
    }

    private func decodeRecord(from data: Data) throws -> StoredRecord {
        decodedRecordCount += 1
        return try JSONDecoder().decode(StoredRecord.self, from: data)
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

}

/// Identity without the size/modification-date fingerprint: two records with
/// the same key describe different versions of one source file.
private nonisolated struct SupersessionKey: Hashable, Sendable {
    let standardizedPath: String
    let artifactSchemaVersion: Int
    let backend: SimilarityBackendDescriptor
    let pipeline: SimilarityArtifactPipelineSignature

    init(_ identity: LookupIdentity) {
        standardizedPath = identity.sourceFingerprint.standardizedPath
        artifactSchemaVersion = identity.artifactSchemaVersion
        backend = identity.backend
        pipeline = identity.pipeline
    }
}

/// Decodes only the identity of a stored record.
private nonisolated struct StoredRecordIdentity: Decodable {
    let identity: LookupIdentity
}

private nonisolated struct StoredRecord: Codable, Sendable {
    let schemaVersion: Int
    let identity: LookupIdentity
    let sourceDisplayName: String
    let artifactData: Data
    let createdAt: Date
    var lastAccessedAt: Date
}

private nonisolated enum StoreError: Error, Equatable, Sendable {
    case incompatibleArtifact
}
