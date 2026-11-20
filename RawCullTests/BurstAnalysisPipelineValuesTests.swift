import Foundation
@testable import RawCull
import RawCullCore
import Testing

@MainActor
@Suite(.tags(.smoke))
struct BurstAnalysisPipelineValuesTests {
    @Test
    func `pipeline request equals the legacy input snapshot`() {
        let viewModel = makeRawCullViewModel()
        let catalog = URL(fileURLWithPath: "/tmp/catalog-\(UUID().uuidString)")
        let first = makePipelineFile("A.ARW", captureSeconds: 1)
        let second = makePipelineFile("B.ARW", captureSeconds: 2)
        let orderedFiles = [first, second]
        let generation = 17

        let legacySharpnessSignature = viewModel.sharpnessModel.scoringSignature
        let legacySimilaritySignature = viewModel.currentBurstSimilaritySignature
        let legacyConfiguration = BurstAnalysisPipelineConfiguration(
            thumbnailMaxPixelSize: viewModel.sharpnessModel.effectiveThumbnailMaxPixelSize,
            grouping: legacySimilaritySignature.groupingConfig,
            cacheSchemaVersion: BurstAnalysisCache.schemaVersion,
            groupingAlgorithmVersion: BurstGroupingConfig.algorithmVersion,
        )
        let expected = BurstAnalysisPipelineRequest(
            catalogIdentity: catalog,
            orderedFiles: orderedFiles,
            sharpnessSignature: legacySharpnessSignature,
            similaritySignature: legacySimilaritySignature,
            generation: generation,
            configuration: legacyConfiguration,
        )

        let request = viewModel.makeBurstAnalysisPipelineRequest(
            catalog: catalog,
            files: orderedFiles,
            generation: generation,
        )

        #expect(request == expected)
        #expect(request.catalogIdentity == catalog)
        #expect(request.orderedFiles.map(\.id) == orderedFiles.map(\.id))
        #expect(request.configuration.grouping == request.similaritySignature.groupingConfig)
    }

    @Test
    func `pipeline request remains an immutable configuration snapshot`() {
        let viewModel = makeRawCullViewModel()
        let catalog = URL(fileURLWithPath: "/tmp/catalog-\(UUID().uuidString)")
        let files = [makePipelineFile("A.ARW", captureSeconds: 1)]
        let original = viewModel.makeBurstAnalysisPipelineRequest(
            catalog: catalog,
            files: files,
            generation: 3,
        )

        viewModel.similarityModel.burstSensitivity = 0.11
        let replacement = viewModel.makeBurstAnalysisPipelineRequest(
            catalog: catalog,
            files: files,
            generation: 4,
        )

        #expect(original.generation == 3)
        #expect(original.configuration.grouping.visualDistanceThreshold != 0.11)
        #expect(replacement.configuration.grouping.visualDistanceThreshold == 0.11)
        #expect(original != replacement)
    }

    @Test
    func `pipeline result equality covers cache diagnostics and restored state`() {
        let file = makePipelineFile("A.ARW", captureSeconds: 1)
        let group = BurstGroup(id: 4, fileIDs: [file.id])
        let result = BurstAnalysisPipelineResult(
            groups: [group],
            rankings: [],
            restoredReviewStates: [group.id: .deferred],
            cacheOutcome: .miss,
            diagnostics: [.reusedSharpnessScores, .indexedMissingSimilarityArtifacts],
        )
        let equalResult = BurstAnalysisPipelineResult(
            groups: [group],
            rankings: [],
            restoredReviewStates: [group.id: .deferred],
            cacheOutcome: .miss,
            diagnostics: [.reusedSharpnessScores, .indexedMissingSimilarityArtifacts],
        )
        let cacheHit = BurstAnalysisPipelineResult(
            groups: [group],
            rankings: [],
            restoredReviewStates: [group.id: .deferred],
            cacheOutcome: .hit,
            diagnostics: [.reusedSharpnessScores, .indexedMissingSimilarityArtifacts],
        )

        #expect(result == equalResult)
        #expect(result != cacheHit)
        requireSendable(BurstAnalysisPipelineRequest.self)
        requireSendable(BurstAnalysisPipelineResult.self)
    }

    @Test
    func `malformed cache with repeated file or group keys is rejected without trapping`() async {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("RawCullMalformedCacheTests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let cache = BurstAnalysisCache(cacheDirectory: directory)
        let catalog = URL(fileURLWithPath: "/tmp/catalog-\(UUID().uuidString)")
        let first = makePipelineFile("A.ARW", captureSeconds: 1)
        let second = makePipelineFile("B.ARW", captureSeconds: 2)
        var snapshot = makeBurstSnapshot(
            catalog: catalog,
            files: [first, second],
            groups: [],
            results: [],
            reviewStateSnapshots: [],
        )
        // Two entries share A's path, and one id is repeated.
        snapshot.files = [
            snapshot.files[0],
            BurstAnalysisCacheFile(
                id: UUID(),
                path: snapshot.files[0].path,
                size: snapshot.files[0].size,
                modificationDate: snapshot.files[0].modificationDate,
            ),
            snapshot.files[0]
        ]
        snapshot.sharpnessScores = Dictionary(uniqueKeysWithValues: snapshot.files.dropLast().map { ($0.id, 0.5) })

        let remapped = BurstAnalysisCoordinator.remap(snapshot, to: [first, second])
        #expect(remapped.files.map(\.id) == [first.id, second.id])
        #expect(!BurstAnalysisCache.hasUniqueRestoreKeys(snapshot))

        await cache.save(snapshot, catalog: catalog)
        let loaded = await cache.load(
            catalog: catalog,
            files: [first, second, first],
            thumbnailMaxPixelSize: snapshot.thumbnailMaxPixelSize,
            sharpnessSignature: snapshot.sharpnessSignature,
            similaritySignature: snapshot.similaritySignature,
        )
        #expect(loaded == nil)
        #expect(await cache.loadMigrationCandidate(catalog: catalog) == nil)

        snapshot.files = remapped.files
        snapshot.groups = [BurstGroup(id: 1, fileIDs: [first.id]), BurstGroup(id: 2, fileIDs: [first.id, second.id])]
        #expect(!BurstAnalysisCache.hasUniqueRestoreKeys(snapshot))
        await cache.save(snapshot, catalog: catalog)
        #expect(await cache.loadMigrationCandidate(catalog: catalog) == nil)
    }

    @Test
    func `completed context resolves files by ID then path and fails when one is gone`() {
        let catalog = URL(fileURLWithPath: "/tmp/catalog-\(UUID().uuidString)")
        let first = makePipelineFile("A.ARW", captureSeconds: 1)
        let second = makePipelineFile("B.ARW", captureSeconds: 2)
        let context = BurstAnalysisSnapshotFactory.completedContext(
            catalog: catalog,
            files: [first, second],
            generation: 5,
            similaritySignature: makeRawCullViewModel().currentBurstSimilaritySignature,
        )

        let reordered = BurstAnalysisSnapshotFactory.files(for: context, in: [second, first])
        #expect(reordered?.map(\.id) == [first.id, second.id])

        // A rescan gives the same path a new ID; the path fallback still matches it.
        let rescannedSecond = makePipelineFile("B.ARW", captureSeconds: 2)
        let rescanned = BurstAnalysisSnapshotFactory.files(for: context, in: [first, rescannedSecond])
        #expect(rescanned?.map(\.id) == [first.id, rescannedSecond.id])

        #expect(BurstAnalysisSnapshotFactory.files(for: context, in: [first]) == nil)
    }

    @Test
    func `scoped keeps only values for the given files`() {
        let first = makePipelineFile("A.ARW", captureSeconds: 1)
        let second = makePipelineFile("B.ARW", captureSeconds: 2)
        let scores: [UUID: Float] = [first.id: 0.4, second.id: 0.9, UUID(): 0.1]

        let scoped = BurstAnalysisSnapshotFactory.scoped(scores, to: [second])

        #expect(scoped == [second.id: 0.9])
    }
}

private nonisolated func makePipelineFile(
    _ name: String,
    captureSeconds: TimeInterval,
) -> FileItem {
    FileItem(
        url: URL(fileURLWithPath: "/tmp/\(name)"),
        name: name,
        size: 1,
        dateModified: Date(timeIntervalSince1970: captureSeconds),
        captureDate: Date(timeIntervalSince1970: captureSeconds),
        exifData: nil,
        afFocusNormalized: nil,
    )
}

private nonisolated func requireSendable(_: (some Sendable).Type) {}
