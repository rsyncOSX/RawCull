import CoreGraphics
import Foundation
import PhotoAnalysisKit
@testable import RawCull
import RawCullCore
import Testing

@Suite("Per-file similarity artifact store")
struct PerFileAnalysisArtifactStoreTests {
    @Test
    func `thumbnail representation and schema do not alter similarity fingerprint`() {
        let source = makeArtifactSource(name: "independent.ARW")
        let similarityFingerprint = source.fingerprint
        let grid = ThumbnailRequestKey(
            source: ThumbnailSourceFingerprint(
                url: source.url,
                fileSize: source.fileSize,
                modificationDate: source.modificationDate,
                cacheSchemaVersion: 2,
            ),
            purpose: .grid,
            requestedMaxPixelSize: 200,
        )
        let preview = ThumbnailRequestKey(
            source: ThumbnailSourceFingerprint(
                url: source.url,
                fileSize: source.fileSize,
                modificationDate: source.modificationDate,
                cacheSchemaVersion: 3,
            ),
            purpose: .preview,
            requestedMaxPixelSize: 1_616,
        )

        #expect(grid != preview)
        #expect(source.fingerprint == similarityFingerprint)
        #expect(source.fingerprint.modificationDate == source.modificationDate)
    }

    @Test
    func `valid artifact round trips and incompatible identities miss`() async throws {
        let store = makeIsolatedSimilarityArtifactStore()
        let source = makeArtifactSource(name: "round-trip.ARW")
        let payload = try await makeValidVisionArtifact()
        let signature = makeArtifactSignature()

        let commit = await store.upsert(
            artifacts: [source.id: payload],
            sources: [source.id: source],
            signature: signature,
        )
        let loaded = await store.load(
            sources: [source],
            signature: signature,
        )

        #expect(commit.committedSourceIDs == Set([source.id]))
        #expect(commit.failures.isEmpty)
        #expect(loaded.artifacts[source.id] == payload)

        let changedSource = SimilarityArtifactSource(
            id: UUID(),
            url: source.url,
            displayName: source.displayName,
            fileSize: source.fileSize + 1,
            modificationDate: source.modificationDate,
        )
        let changedPipeline = SimilarityArtifactPipelineSignature(
            featurePrintRevision: signature.featurePrintRevision,
            representationVersion: signature.representationVersion,
            thumbnailMaxPixelSize: signature.thumbnailMaxPixelSize + 1,
            pipelineVersion: signature.pipelineVersion,
        )

        let changedSourceLoad = await store.load(
            sources: [changedSource],
            signature: signature,
        )
        let changedPipelineLoad = await store.load(
            sources: [source],
            signature: changedPipeline,
        )

        #expect(changedSourceLoad.artifacts.isEmpty)
        #expect(changedPipelineLoad.artifacts.isEmpty)
    }

    @Test
    func `one corrupt record is isolated from valid records`() async throws {
        let store = makeIsolatedSimilarityArtifactStore()
        let first = makeArtifactSource(name: "first.ARW")
        let second = makeArtifactSource(name: "second.ARW")
        let payload = try await makeValidVisionArtifact()
        let signature = makeArtifactSignature()

        _ = await store.upsert(
            artifacts: [first.id: payload],
            sources: [first.id: first],
            signature: signature,
        )
        let storedRecords = try FileManager.default.contentsOfDirectory(
            at: store.storageDirectory,
            includingPropertiesForKeys: nil,
        )
        let firstRecord = try #require(storedRecords.first)
        _ = await store.upsert(
            artifacts: [second.id: payload],
            sources: [second.id: second],
            signature: signature,
        )
        try Data("truncated".utf8).write(to: firstRecord, options: .atomic)

        let loaded = await store.load(
            sources: [first, second],
            signature: signature,
        )

        #expect(loaded.artifacts[first.id] == nil)
        #expect(loaded.artifacts[second.id] == payload)
        #expect(
            loaded.misses.contains {
                $0.sourceID == first.id && $0.reason == .corrupt
            },
        )
    }

    @Test
    func `invalid Vision payload is not committed`() async throws {
        let store = makeIsolatedSimilarityArtifactStore()
        let source = makeArtifactSource(name: "invalid.ARW")
        let signature = makeArtifactSignature()
        let invalid = try JSONEncoder().encode(
            VisionFeaturePrint(
                revision: signature.featurePrintRevision,
                payload: Data([0x00, 0x01]),
            ),
        )

        let result = await store.upsert(
            artifacts: [source.id: invalid],
            sources: [source.id: source],
            signature: signature,
        )

        #expect(result.committedSourceIDs.isEmpty)
        #expect(result.failures.count == 1)
        #expect((await store.usage()).entryCount == 0)
    }

    @Test
    func `usage pruning and clear operate on individual records`() async throws {
        let store = makeIsolatedSimilarityArtifactStore()
        let source = makeArtifactSource(name: "prune.ARW")
        let payload = try await makeValidVisionArtifact()
        let signature = makeArtifactSignature()

        _ = await store.upsert(
            artifacts: [source.id: payload],
            sources: [source.id: source],
            signature: signature,
        )

        let populated = await store.usage()
        #expect(populated.entryCount == 1)
        #expect(populated.size > 0)

        let pruned = await store.prune(
            policy: PerFileAnalysisArtifactPruningPolicy(
                maximumUnusedAge: -1,
                maximumEntryCount: 0,
            ),
        )
        #expect(pruned.removedEntryCount == 1)
        #expect((await store.usage()).entryCount == 0)

        _ = await store.upsert(
            artifacts: [source.id: payload],
            sources: [source.id: source],
            signature: signature,
        )
        await store.clear()
        #expect((await store.usage()).entryCount == 0)
    }

    @Test
    func `cancellation before replacement preserves committed artifact`() async throws {
        let store = makeIsolatedSimilarityArtifactStore()
        let source = makeArtifactSource(name: "atomic.ARW")
        let original = try await makeValidVisionArtifact(red: 32)
        let replacement = try await makeValidVisionArtifact(red: 224)
        let signature = makeArtifactSignature()
        let gate = ArtifactStoreCancellationGate()

        _ = await store.upsert(
            artifacts: [source.id: original],
            sources: [source.id: source],
            signature: signature,
        )

        let replacementTask = Task {
            await gate.wait()
            return await store.upsert(
                artifacts: [source.id: replacement],
                sources: [source.id: source],
                signature: signature,
            )
        }
        await gate.waitUntilStarted()
        replacementTask.cancel()
        await gate.release()
        let result = await replacementTask.value
        let loaded = await store.load(
            sources: [source],
            signature: signature,
        )

        #expect(result.wasCancelled)
        #expect(loaded.artifacts[source.id] == original)
    }

    @Test
    func `cancellation after first commit preserves completed record and stops later records`() async throws {
        let gate = ArtifactStorePartialCommitGate()
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("RawCullPartialCommit-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = PerFileAnalysisArtifactStore(
            storageDirectory: root,
            beforeRecordCommit: { _ in await gate.beforeCommit() },
        )
        let sourceDirectory = URL(fileURLWithPath: "/tmp/ordered-\(UUID().uuidString)")
        let first = SimilarityArtifactSource(
            id: UUID(),
            url: sourceDirectory.appendingPathComponent("a-first.ARW"),
            displayName: "a-first.ARW",
            fileSize: 1_024,
            modificationDate: Date(timeIntervalSince1970: 1_000),
        )
        let second = SimilarityArtifactSource(
            id: UUID(),
            url: sourceDirectory.appendingPathComponent("b-second.ARW"),
            displayName: "b-second.ARW",
            fileSize: 1_024,
            modificationDate: Date(timeIntervalSince1970: 1_000),
        )
        let payload = try await makeValidVisionArtifact()
        let sources = [first.id: first, second.id: second]
        let task = Task {
            await store.upsert(
                artifacts: [first.id: payload, second.id: payload],
                sources: sources,
                signature: makeArtifactSignature(),
            )
        }

        await gate.waitUntilSecondCommitIsWaiting()
        task.cancel()
        await gate.releaseSecondCommit()
        let result = await task.value
        let loaded = await store.load(
            sources: [first, second],
            signature: makeArtifactSignature(),
        )

        #expect(result.wasCancelled)
        #expect(result.committedSourceIDs == Set([first.id]))
        #expect(loaded.artifacts[first.id] == payload)
        #expect(loaded.artifacts[second.id] == nil)
    }

    @Test
    func `clearing analysis artifacts leaves ratings and settings files untouched`() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("RawCullArtifactClearIsolation-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let artifactDirectory = root.appendingPathComponent("AnalysisArtifacts/Similarity", isDirectory: true)
        let ratingsURL = root.appendingPathComponent("ratings.json")
        let settingsURL = root.appendingPathComponent("settings.json")
        let ratings = Data("ratings-sentinel".utf8)
        let settings = Data("settings-sentinel".utf8)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try ratings.write(to: ratingsURL)
        try settings.write(to: settingsURL)
        let store = PerFileAnalysisArtifactStore(storageDirectory: artifactDirectory)
        let source = makeArtifactSource(name: "clear.ARW")
        let payload = try await makeValidVisionArtifact()
        _ = await store.upsert(
            artifacts: [source.id: payload],
            sources: [source.id: source],
            signature: makeArtifactSignature(),
        )

        await store.clear()

        #expect((await store.usage()).entryCount == 0)
        #expect(try Data(contentsOf: ratingsURL) == ratings)
        #expect(try Data(contentsOf: settingsURL) == settings)
    }
}

@Suite("Durable similarity indexing")
@MainActor
struct SimilarityArtifactPersistenceTests {
    @Test
    func `indexing survives model recreation and indexes only added or changed files`() async throws {
        let store = makeIsolatedSimilarityArtifactStore()
        let payload = try await makeValidVisionArtifact()
        let recorder = SimilarityProviderRecorder(payload: payload)
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(
                "RawCullSimilarityPersistence-\(UUID().uuidString)",
                isDirectory: true,
            )
        let first = makeArtifactFile(
            directory: directory,
            name: "first.ARW",
            size: 100,
            modified: 100,
        )
        let second = makeArtifactFile(
            directory: directory,
            name: "second.ARW",
            size: 200,
            modified: 200,
        )

        let initialModel = SimilarityScoringModel(
            embeddingProvider: { url, _ in
                await recorder.artifact(for: url)
            },
            artifactStore: store,
        )
        await initialModel.indexFiles([first, second])
        #expect(await recorder.requests() == ["first.ARW", "second.ARW"])

        await recorder.reset()
        let reloadedFirst = makeArtifactFile(
            directory: directory,
            name: "first.ARW",
            size: 100,
            modified: 100,
        )
        let reloadedSecond = makeArtifactFile(
            directory: directory,
            name: "second.ARW",
            size: 200,
            modified: 200,
        )
        let reloadedModel = SimilarityScoringModel(
            embeddingProvider: { url, _ in
                await recorder.artifact(for: url)
            },
            artifactStore: store,
        )
        await reloadedModel.indexFiles([reloadedFirst, reloadedSecond])

        #expect((await recorder.requests()).isEmpty)
        #expect(reloadedModel.embeddings.count == 2)

        let added = makeArtifactFile(
            directory: directory,
            name: "added.ARW",
            size: 300,
            modified: 300,
        )
        await reloadedModel.indexFiles([reloadedFirst, reloadedSecond, added])
        #expect(await recorder.requests() == ["added.ARW"])

        await recorder.reset()
        let modifiedFirst = makeArtifactFile(
            directory: directory,
            name: "first.ARW",
            size: 101,
            modified: 101,
        )
        let finalModel = SimilarityScoringModel(
            embeddingProvider: { url, _ in
                await recorder.artifact(for: url)
            },
            artifactStore: store,
        )
        await finalModel.indexFiles([modifiedFirst, reloadedSecond, added])

        #expect(await recorder.requests() == ["first.ARW"])
        #expect(finalModel.embeddings.count == 3)
    }

    @Test
    func `legacy burst snapshot artifacts migrate into the per-file store`() async throws {
        let store = makeIsolatedSimilarityArtifactStore()
        let cacheDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(
                "RawCullLegacyBurstMigration-\(UUID().uuidString)",
                isDirectory: true,
            )
        let cache = BurstAnalysisCache(cacheDirectory: cacheDirectory)
        let catalog = URL(
            fileURLWithPath: "/tmp/catalog-\(UUID().uuidString)",
        )
        let file = makeArtifactFile(
            directory: catalog,
            name: "legacy.ARW",
            size: 100,
            modified: 100,
        )
        let payload = try await makeValidVisionArtifact()
        let similaritySignature = BurstSimilaritySignature(
            groupingConfig: BurstGroupingConfig(
                visualDistanceThreshold: 0.25,
            ),
            embeddingThumbnailMaxPixelSize:
                SimilarityScoringModel.embeddingThumbnailMaxPixelSize,
            visionFeaturePrintRevision:
                SimilarityScoringModel.featurePrintRevision,
            embeddingPipelineVersion:
                SimilarityScoringModel.embeddingPipelineVersion,
        )
        let snapshot = BurstAnalysisCacheSnapshot(
            schemaVersion:
                BurstAnalysisCache.legacyArtifactMigrationSchemaVersion,
            algorithmVersion: BurstGroupingConfig.algorithmVersion,
            catalogPath: catalog.path,
            thumbnailMaxPixelSize: 512,
            sharpnessSignature: BurstSharpnessSignature(
                thumbnailMaxPixelSize: 512,
                config: FocusDetectorConfig(),
            ),
            similaritySignature: similaritySignature,
            similarityArtifactSetDigest: nil,
            files: [
                BurstAnalysisCacheFile(
                    id: file.id,
                    path: file.url.path,
                    size: file.size,
                    modificationDate: file.dateModified,
                ),
            ],
            embeddings: [file.id: payload],
            sharpnessScores: [:],
            saliencyInfo: [:],
            groups: [],
            boundaryEvidence: [],
            results: [],
            reviewStateSnapshots: [],
        )
        await cache.save(snapshot, catalog: catalog)

        let candidate = try #require(
            await cache.loadMigrationCandidate(catalog: catalog),
        )
        let model = SimilarityScoringModel(
            artifactStore: store,
        )
        let imported = await model.importLegacyArtifacts(
            candidate.embeddings,
            files: [file],
            signature: candidate.similaritySignature,
        )
        let reloadedFile = makeArtifactFile(
            directory: catalog,
            name: "legacy.ARW",
            size: 100,
            modified: 100,
        )
        let reloadedModel = SimilarityScoringModel(
            artifactStore: store,
        )
        await reloadedModel.hydrateArtifacts([reloadedFile])

        #expect(imported == 1)
        #expect(reloadedModel.embeddings[reloadedFile.id] == payload)
    }

    @Test
    func `successful artifacts survive a partially failed indexing run`() async throws {
        let store = makeIsolatedSimilarityArtifactStore()
        let payload = try await makeValidVisionArtifact()
        let directory = URL(
            fileURLWithPath: "/tmp/partial-\(UUID().uuidString)",
        )
        let success = makeArtifactFile(
            directory: directory,
            name: "success.ARW",
            size: 100,
            modified: 100,
        )
        let failure = makeArtifactFile(
            directory: directory,
            name: "failure.ARW",
            size: 200,
            modified: 200,
        )
        let initialModel = SimilarityScoringModel(
            embeddingProvider: { url, _ in
                url.lastPathComponent == "success.ARW" ? payload : nil
            },
            artifactStore: store,
        )

        await initialModel.indexFiles([success, failure])

        #expect(initialModel.embeddings[success.id] == payload)
        #expect(initialModel.embeddings[failure.id] == nil)
        #expect(initialModel.indexingGenerationFailures == [failure.id])
        #expect(!initialModel.isIndexing)
        #expect(initialModel.indexingProgress == 0)
        #expect(initialModel.indexingTotal == 0)
        #expect(initialModel.indexingPhase == .idle)

        let recorder = SimilarityProviderRecorder(payload: payload)
        let reloadedSuccess = makeArtifactFile(
            directory: directory,
            name: "success.ARW",
            size: 100,
            modified: 100,
        )
        let reloadedFailure = makeArtifactFile(
            directory: directory,
            name: "failure.ARW",
            size: 200,
            modified: 200,
        )
        let reloadedModel = SimilarityScoringModel(
            embeddingProvider: { url, _ in
                await recorder.artifact(for: url)
            },
            artifactStore: store,
        )
        await reloadedModel.indexFiles([reloadedSuccess, reloadedFailure])

        #expect(await recorder.requests() == ["failure.ARW"])
        #expect(reloadedModel.embeddings.count == 2)
    }

    @Test
    func `persistence write failure keeps generated result usable and resets progress`() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("RawCullPersistenceFailure-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let blockingFile = root.appendingPathComponent("not-a-directory")
        try Data("block".utf8).write(to: blockingFile)
        let store = PerFileAnalysisArtifactStore(
            storageDirectory: blockingFile.appendingPathComponent("Similarity", isDirectory: true),
        )
        let payload = try await makeValidVisionArtifact()
        let file = makeArtifactFile(
            directory: root,
            name: "usable.ARW",
            size: 100,
            modified: 100,
        )
        let model = SimilarityScoringModel(
            embeddingProvider: { _, _ in payload },
            artifactStore: store,
        )

        await model.indexFiles([file])

        #expect(model.embeddings[file.id] == payload)
        #expect(model.indexingPersistenceFailures.count == 1)
        #expect(!model.isIndexing)
        #expect(model.indexingProgress == 0)
        #expect(model.indexingTotal == 0)
        #expect(model.indexingEstimatedSeconds == 0)
        #expect(model.indexingPhase == .idle)
    }
}

private actor SimilarityProviderRecorder {
    private let payload: Data
    private var requestedNames: [String] = []

    init(payload: Data) {
        self.payload = payload
    }

    func artifact(for url: URL) -> Data {
        requestedNames.append(url.lastPathComponent)
        return payload
    }

    func requests() -> [String] {
        requestedNames.sorted()
    }

    func reset() {
        requestedNames = []
    }
}

private actor ArtifactStoreCancellationGate {
    private var started = false
    private var startWaiters: [CheckedContinuation<Void, Never>] = []
    private var releaseWaiters: [CheckedContinuation<Void, Never>] = []

    func wait() async {
        started = true
        let waiters = startWaiters
        startWaiters = []
        for waiter in waiters {
            waiter.resume()
        }
        await withCheckedContinuation { continuation in
            releaseWaiters.append(continuation)
        }
    }

    func waitUntilStarted() async {
        if started { return }
        await withCheckedContinuation { continuation in
            startWaiters.append(continuation)
        }
    }

    func release() {
        let waiters = releaseWaiters
        releaseWaiters = []
        for waiter in waiters {
            waiter.resume()
        }
    }
}

private actor ArtifactStorePartialCommitGate {
    private var commitCount = 0
    private var secondCommitStarted = false
    private var startWaiters: [CheckedContinuation<Void, Never>] = []
    private var releaseWaiters: [CheckedContinuation<Void, Never>] = []

    func beforeCommit() async {
        commitCount += 1
        guard commitCount == 2 else { return }
        secondCommitStarted = true
        let waiters = startWaiters
        startWaiters = []
        for waiter in waiters { waiter.resume() }
        await withCheckedContinuation { releaseWaiters.append($0) }
    }

    func waitUntilSecondCommitIsWaiting() async {
        if secondCommitStarted { return }
        await withCheckedContinuation { startWaiters.append($0) }
    }

    func releaseSecondCommit() {
        let waiters = releaseWaiters
        releaseWaiters = []
        for waiter in waiters { waiter.resume() }
    }
}

private func makeArtifactSignature() -> SimilarityArtifactPipelineSignature {
    SimilarityScoringModel.artifactPipelineSignature
}

private func makeArtifactSource(name: String) -> SimilarityArtifactSource {
    SimilarityArtifactSource(
        id: UUID(),
        url: URL(fileURLWithPath: "/tmp/\(UUID().uuidString)/\(name)"),
        displayName: name,
        fileSize: 1_024,
        modificationDate: Date(timeIntervalSince1970: 1_000),
    )
}

private func makeArtifactFile(
    directory: URL,
    name: String,
    size: Int64,
    modified: TimeInterval,
) -> FileItem {
    FileItem(
        url: directory.appendingPathComponent(name),
        name: name,
        size: size,
        dateModified: Date(timeIntervalSince1970: modified),
        captureDate: nil,
        exifData: nil,
        afFocusNormalized: nil,
    )
}

private func makeValidVisionArtifact(red: UInt8 = 128) async throws -> Data {
    let colorSpace = try #require(
        CGColorSpace(name: CGColorSpace.sRGB),
    )
    let context = try #require(
        CGContext(
            data: nil,
            width: 16,
            height: 16,
            bitsPerComponent: 8,
            bytesPerRow: 16 * 4,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue,
        ),
    )
    context.setFillColor(
        red: CGFloat(red) / 255,
        green: 0.25,
        blue: 0.75,
        alpha: 1,
    )
    context.fill(CGRect(x: 0, y: 0, width: 16, height: 16))
    let image = try #require(context.makeImage())
    let featurePrint = try await VisionFeaturePrintBackend(
        revision: SimilarityScoringModel.featurePrintRevision,
    ).featurePrint(for: image)
    return try JSONEncoder().encode(featurePrint)
}
