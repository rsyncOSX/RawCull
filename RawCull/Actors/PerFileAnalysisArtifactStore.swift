import CryptoKit
import Foundation
import PhotoAnalysisKit

nonisolated struct SimilarityArtifactSource: Hashable, Sendable {
    let id: UUID
    let url: URL
    let displayName: String
    let fileSize: Int64
    let modificationDate: Date

    var fingerprint: SimilarityArtifactSourceFingerprint {
        SimilarityArtifactSourceFingerprint(
            standardizedPath: url.standardizedFileURL.path,
            fileSize: fileSize,
            modificationDate: modificationDate,
        )
    }
}

nonisolated struct SimilarityArtifactSourceFingerprint:
    Codable,
    Equatable,
    Hashable,
    Sendable
{
    let standardizedPath: String
    let fileSize: Int64
    let modificationDate: Date
}

/// Complete identity of the Vision feature-print pipeline used by RawCull.
///
/// The PhotoAnalysisKit payload remains opaque. RawCull records only the
/// compatibility information it owns and needs in order to reject stale work.
nonisolated struct SimilarityArtifactPipelineSignature:
    Codable,
    Equatable,
    Hashable,
    Sendable
{
    static let backendIdentifier = "photoanalysiskit.vision-feature-print"
    static let currentArtifactSchemaVersion = 1

    let backendIdentifier: String
    let featurePrintRevision: Int
    let representationVersion: Int
    let thumbnailMaxPixelSize: Int
    let pipelineVersion: Int
    let artifactSchemaVersion: Int

    init(
        featurePrintRevision: Int,
        representationVersion: Int,
        thumbnailMaxPixelSize: Int,
        pipelineVersion: Int,
        backendIdentifier: String = Self.backendIdentifier,
        artifactSchemaVersion: Int = Self.currentArtifactSchemaVersion,
    ) {
        self.backendIdentifier = backendIdentifier
        self.featurePrintRevision = featurePrintRevision
        self.representationVersion = representationVersion
        self.thumbnailMaxPixelSize = thumbnailMaxPixelSize
        self.pipelineVersion = pipelineVersion
        self.artifactSchemaVersion = artifactSchemaVersion
    }
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
    let artifacts: [UUID: Data]
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

nonisolated struct PerFileAnalysisArtifactPruningPolicy: Equatable, Sendable {
    var maximumUnusedAge: TimeInterval
    var maximumEntryCount: Int

    /// Retain recently used records for 90 days and cap the cache at 50,000
    /// entries. A replacement removes older fingerprints for the same
    /// path/pipeline identity as soon as the new record is committed.
    static let `default` = Self(
        maximumUnusedAge: 90 * 24 * 60 * 60,
        maximumEntryCount: 50_000,
    )
}

nonisolated struct PerFileAnalysisArtifactPruneResult: Equatable, Sendable {
    let removedEntryCount: Int
    let remainingEntryCount: Int
}

/// RawCull-owned, per-source persistence for opaque PhotoAnalysisKit Vision
/// feature prints.
///
/// Each mutation is actor-isolated and each record is atomically replaced.
/// Cancellation can stop later commits without damaging records already
/// written. Moving or renaming a source is intentionally a cache miss.
actor PerFileAnalysisArtifactStore {
    static let shared = PerFileAnalysisArtifactStore()
    nonisolated static let recordSchemaVersion = 1

    nonisolated let storageDirectory: URL
    private let beforeRecordCommit: (@Sendable (UUID) async -> Void)?

    init(
        storageDirectory: URL? = nil,
        beforeRecordCommit: (@Sendable (UUID) async -> Void)? = nil,
    ) {
        self.beforeRecordCommit = beforeRecordCommit
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
        sources: [SimilarityArtifactSource],
        signature: SimilarityArtifactPipelineSignature,
    ) -> PerFileAnalysisArtifactLoadResult {
        var artifacts: [UUID: Data] = [:]
        var misses: [PerFileAnalysisArtifactCacheMiss] = []
        artifacts.reserveCapacity(sources.count)
        misses.reserveCapacity(sources.count)

        for source in sources {
            guard !Task.isCancelled else { break }

            let identity = LookupIdentity(
                sourceFingerprint: source.fingerprint,
                pipeline: signature,
            )
            let url = recordURL(for: identity)
            guard FileManager.default.fileExists(atPath: url.path) else {
                misses.append(
                    PerFileAnalysisArtifactCacheMiss(
                        sourceID: source.id,
                        reason: .notFound,
                    ),
                )
                continue
            }

            do {
                var record = try decodeRecord(at: url)
                guard record.schemaVersion == Self.recordSchemaVersion,
                      record.identity == identity,
                      RawCullSimilarityArtifactValidation.isCurrent(
                          record.payload,
                          signature: signature,
                      )
                else {
                    try? FileManager.default.removeItem(at: url)
                    misses.append(
                        PerFileAnalysisArtifactCacheMiss(
                            sourceID: source.id,
                            reason: .incompatible,
                        ),
                    )
                    continue
                }

                artifacts[source.id] = record.payload
                if Date().timeIntervalSince(record.lastAccessedAt) >= 86_400 {
                    record.lastAccessedAt = Date()
                    try? encode(record).write(to: url, options: .atomic)
                }
            } catch {
                try? FileManager.default.removeItem(at: url)
                misses.append(
                    PerFileAnalysisArtifactCacheMiss(
                        sourceID: source.id,
                        reason: .corrupt,
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
        artifacts: [UUID: Data],
        sources: [UUID: SimilarityArtifactSource],
        signature: SimilarityArtifactPipelineSignature,
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
        let knownRecords = recordURLs().compactMap { url -> (URL, StoredRecord)? in
            guard let record = try? decodeRecord(at: url) else { return nil }
            return (url, record)
        }
        var knownRecordsBySource = Dictionary(
            grouping: knownRecords,
            by: { $0.1.identity.supersessionIdentity },
        )

        for (sourceID, payload) in orderedArtifacts {
            if let beforeRecordCommit {
                await beforeRecordCommit(sourceID)
            }
            guard !Task.isCancelled else {
                return PerFileAnalysisArtifactCommitResult(
                    committedSourceIDs: committedSourceIDs,
                    failures: failures,
                    wasCancelled: true,
                )
            }
            guard let source = sources[sourceID] else {
                failures.append(
                    PerFileAnalysisArtifactWriteFailure(
                        sourceID: sourceID,
                        sourcePath: "",
                        message: "The source metadata required to persist the artifact is unavailable.",
                    ),
                )
                continue
            }

            do {
                guard RawCullSimilarityArtifactValidation.isCurrent(
                    payload,
                    signature: signature,
                ) else {
                    throw StoreError.incompatibleArtifact
                }

                let identity = LookupIdentity(
                    sourceFingerprint: source.fingerprint,
                    pipeline: signature,
                )
                let url = recordURL(for: identity)
                let now = Date()
                let existingCreatedAt = (try? decodeRecord(at: url))?.createdAt
                let record = StoredRecord(
                    schemaVersion: Self.recordSchemaVersion,
                    identity: identity,
                    sourceDisplayName: source.displayName,
                    payload: payload,
                    createdAt: existingCreatedAt ?? now,
                    lastAccessedAt: now,
                )
                try encode(record).write(to: url, options: .atomic)

                let supersessionIdentity = identity.supersessionIdentity
                for (knownURL, _) in
                    knownRecordsBySource[supersessionIdentity] ?? []
                    where knownURL != url
                {
                    try? FileManager.default.removeItem(at: knownURL)
                }
                knownRecordsBySource[supersessionIdentity] = [(url, record)]
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

        _ = prune()
        return PerFileAnalysisArtifactCommitResult(
            committedSourceIDs: committedSourceIDs,
            failures: failures,
            wasCancelled: false,
        )
    }

    func remove(
        source: SimilarityArtifactSource,
        signature: SimilarityArtifactPipelineSignature,
    ) {
        let identity = LookupIdentity(
            sourceFingerprint: source.fingerprint,
            pipeline: signature,
        )
        try? FileManager.default.removeItem(at: recordURL(for: identity))
    }

    func usage() -> PerFileAnalysisArtifactStoreUsage {
        let keys: Set<URLResourceKey> = [
            .isRegularFileKey,
            .totalFileAllocatedSizeKey,
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
        for url in recordURLs() {
            try? FileManager.default.removeItem(at: url)
        }
    }

    func prune(
        policy: PerFileAnalysisArtifactPruningPolicy = .default,
        now: Date = Date(),
    ) -> PerFileAnalysisArtifactPruneResult {
        let urls = recordURLs()
        var retained: [(url: URL, lastAccessedAt: Date)] = []
        var removedEntryCount = 0

        for url in urls {
            guard let record = try? decodeRecord(at: url),
                  record.schemaVersion == Self.recordSchemaVersion
            else {
                try? FileManager.default.removeItem(at: url)
                removedEntryCount += 1
                continue
            }

            if now.timeIntervalSince(record.lastAccessedAt)
                > policy.maximumUnusedAge
            {
                try? FileManager.default.removeItem(at: url)
                removedEntryCount += 1
            } else {
                retained.append((url, record.lastAccessedAt))
            }
        }

        if retained.count > policy.maximumEntryCount {
            let overflow = retained.count - policy.maximumEntryCount
            for entry in retained.sorted(by: {
                $0.lastAccessedAt < $1.lastAccessedAt
            }).prefix(overflow) {
                try? FileManager.default.removeItem(at: entry.url)
                removedEntryCount += 1
            }
        }

        return PerFileAnalysisArtifactPruneResult(
            removedEntryCount: removedEntryCount,
            remainingEntryCount: max(0, urls.count - removedEntryCount),
        )
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

    private func encode<T: Encodable>(_ value: T) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return try encoder.encode(value)
    }
}

nonisolated enum RawCullSimilarityArtifactValidation {
    static func isCurrent(
        _ payload: Data,
        signature: SimilarityArtifactPipelineSignature,
    ) -> Bool {
        guard signature.backendIdentifier
            == SimilarityArtifactPipelineSignature.backendIdentifier,
            signature.artifactSchemaVersion
            == SimilarityArtifactPipelineSignature.currentArtifactSchemaVersion,
            let featurePrint = try? JSONDecoder().decode(
                VisionFeaturePrint.self,
                from: payload,
            )
        else { return false }

        guard featurePrint.revision == signature.featurePrintRevision,
              featurePrint.representationVersion
              == signature.representationVersion,
              !featurePrint.payload.isEmpty
        else { return false }

        let backend = VisionFeaturePrintBackend(
            revision: signature.featurePrintRevision,
        )
        return (try? backend.distance(
            from: featurePrint,
            to: featurePrint,
        )) != nil
    }
}

private nonisolated struct LookupIdentity: Codable, Equatable, Sendable {
    let sourceFingerprint: SimilarityArtifactSourceFingerprint
    let pipeline: SimilarityArtifactPipelineSignature

    var supersessionIdentity: SupersessionIdentity {
        SupersessionIdentity(
            standardizedPath: sourceFingerprint.standardizedPath,
            pipeline: pipeline,
        )
    }
}

private nonisolated struct SupersessionIdentity: Hashable, Sendable {
    let standardizedPath: String
    let pipeline: SimilarityArtifactPipelineSignature
}

private nonisolated struct StoredRecord: Codable, Sendable {
    let schemaVersion: Int
    let identity: LookupIdentity
    let sourceDisplayName: String
    let payload: Data
    let createdAt: Date
    var lastAccessedAt: Date
}

private nonisolated enum StoreError: Error, Equatable, Sendable {
    case incompatibleArtifact
}
