import Foundation
@testable import RawCull
import RawCullCore
import Testing

@MainActor
@Suite(.tags(.smoke))
struct BurstAnalysisCoordinatorTests {
    @Test
    func `compatible cache hit returns remapped snapshot and review state`() async throws {
        let catalog = URL(fileURLWithPath: "/tmp/catalog-\(UUID().uuidString)")
        let files = [makeCoordinatorFile("A.raw"), makeCoordinatorFile("B.raw")]
        let group = BurstGroup(id: 7, fileIDs: files.map(\.id))
        let signature = try #require(BurstGroupSignature(files: files, catalog: catalog))
        let harness = makeCoordinatorHarness(
            catalog: catalog,
            files: files,
        )
        let coordinator = harness.coordinator
        let repository = harness.repository
        let request = harness.request
        repository.snapshot = makeCoordinatorSnapshot(
            request: request,
            groups: [group],
            reviewStates: [BurstReviewStateSnapshot(signature: signature, state: .reviewed)],
        )

        let result = await coordinator.prepareCache(
            for: request,
            importLegacyCandidate: false,
            isCurrent: { true },
        )

        #expect(result?.cacheOutcome == .hit)
        #expect(result?.compatibleSnapshot?.groups == [group])
        #expect(result?.restoredReviewStates == [group.id: .reviewed])
        #expect(repository.loadCount == 1)
        #expect(repository.migrationLoadCount == 0)
    }

    @Test
    func `artifact digest mismatch rejects derived cache`() async {
        let catalog = URL(fileURLWithPath: "/tmp/catalog-\(UUID().uuidString)")
        let files = [makeCoordinatorFile("A.raw")]
        let harness = makeCoordinatorHarness(
            catalog: catalog,
            files: files,
        )
        let coordinator = harness.coordinator
        let repository = harness.repository
        let request = harness.request
        var snapshot = makeCoordinatorSnapshot(request: request)
        snapshot.similarityArtifactSetDigest = "different-artifact-set"
        repository.snapshot = snapshot

        let result = await coordinator.prepareCache(
            for: request,
            importLegacyCandidate: false,
            isCurrent: { true },
        )

        #expect(result?.cacheOutcome == .rejectedArtifactSet)
        #expect(result?.compatibleSnapshot == nil)
    }

    @Test
    func `legacy candidate is remapped before import decision`() async {
        let catalog = URL(fileURLWithPath: "/tmp/catalog-\(UUID().uuidString)")
        let currentFiles = [makeCoordinatorFile("A.raw"), makeCoordinatorFile("B.raw")]
        let oldFiles = currentFiles.map { file in
            FileItem(
                url: file.url,
                name: file.name,
                size: file.size,
                dateModified: file.dateModified,
                captureDate: file.captureDate,
                exifData: nil,
                afFocusNormalized: nil,
            )
        }
        let oldGroup = BurstGroup(id: 3, fileIDs: oldFiles.map(\.id))
        let harness = makeCoordinatorHarness(
            catalog: catalog,
            files: currentFiles,
        )
        let coordinator = harness.coordinator
        let repository = harness.repository
        let request = harness.request
        repository.migrationCandidate = makeCoordinatorSnapshot(
            request: request,
            files: oldFiles,
            groups: [oldGroup],
        )

        let result = await coordinator.prepareCache(
            for: request,
            importLegacyCandidate: true,
            isCurrent: { true },
        )

        #expect(result?.cacheOutcome == .miss)
        #expect(result?.diagnostics == [.legacyMigrationCandidateFound])
        #expect(result?.migrationCandidate?.files.map(\.id) == currentFiles.map(\.id))
        #expect(result?.migrationCandidate?.groups.first?.fileIDs == currentFiles.map(\.id))
        #expect(repository.migrationLoadCount == 1)
    }

    @Test
    func `superseded cache preparation returns no result`() async {
        let catalog = URL(fileURLWithPath: "/tmp/catalog-\(UUID().uuidString)")
        let files = [makeCoordinatorFile("A.raw")]
        let harness = makeCoordinatorHarness(
            catalog: catalog,
            files: files,
        )
        let coordinator = harness.coordinator
        let repository = harness.repository
        let request = harness.request
        repository.snapshot = makeCoordinatorSnapshot(request: request)
        repository.invalidateOnLoad = true

        let result = await coordinator.prepareCache(
            for: request,
            importLegacyCandidate: false,
            isCurrent: { repository.isValid },
        )

        #expect(result == nil)
        #expect(repository.loadCount == 1)
    }

    @Test
    func `review restoration follows membership rather than group id`() throws {
        let catalog = URL(fileURLWithPath: "/tmp/catalog-\(UUID().uuidString)")
        let first = makeCoordinatorFile("A.raw")
        let second = makeCoordinatorFile("B.raw")
        let third = makeCoordinatorFile("C.raw")
        let signature = try #require(
            BurstGroupSignature(files: [first, second], catalog: catalog),
        )

        let restored = BurstAnalysisCoordinator.restoredReviewStates(
            snapshots: [BurstReviewStateSnapshot(signature: signature, state: .deferred)],
            groups: [
                BurstGroup(id: 1, fileIDs: [first.id, third.id]),
                BurstGroup(id: 9, fileIDs: [first.id, second.id])
            ],
            files: [first, second, third],
            catalog: catalog,
        )

        #expect(restored == [9: .deferred])
    }

    @Test
    func `fresh orchestration preserves progress ranks and saves an immutable snapshot`() async {
        let catalog = URL(fileURLWithPath: "/tmp/catalog-\(UUID().uuidString)")
        let file = makeCoordinatorFile("A.raw")
        let harness = makeCoordinatorComputeHarness(catalog: catalog, files: [file])
        harness.sharpnessModel.applyPreloadedScores(
            [file],
            preloadedScores: [file.id: 42],
            preloadedSaliency: [:],
        )
        var migration = makeCoordinatorSnapshot(request: harness.request)
        migration.embeddings = [
            file.id: makeCoordinatorArtifact(
                file: file,
                backend: harness.request.similaritySignature.backendDescriptor,
            )
        ]
        harness.repository.migrationCandidate = migration
        var progressSteps: [BurstAnalysisStep] = []
        var appliedResults: [BurstAnalysisPipelineResult] = []

        let result = await harness.coordinator.run(
            request: harness.request,
            initialReviewStates: [:],
            fullCatalogFileIDs: Set([file.id]),
            callbacks: BurstAnalysisRunCallbacks(
                isCurrent: { true },
                updateProgress: { progressSteps.append($0.step) },
                didScoreSharpness: { _ in
                    Issue.record("preloaded sharpness should be reused")
                },
                applyResult: { result in
                    appliedResults.append(result)
                    return result
                },
            ),
        )

        #expect(
            progressSteps == [
                .loadingCache,
                .indexingSimilarity,
                .grouping,
                .ranking,
                .savingCache
            ],
        )
        #expect(result?.diagnostics == [
            .legacyMigrationCandidateFound,
            .reusedSharpnessScores,
            .indexedMissingSimilarityArtifacts,
            .cacheSaveRequested
        ])
        #expect(appliedResults.count == 1)
        #expect(harness.repository.savedSnapshots.count == 1)
        #expect(harness.repository.savedSnapshots.first?.files.map(\.id) == [file.id])
        #expect(harness.repository.savedSnapshots.first?.sharpnessScores == [file.id: 42])
        #expect(harness.repository.savedSnapshots.first?.results == result?.rankings)
    }

    @Test
    func `stale generation cannot apply or save a computed result`() async {
        let catalog = URL(fileURLWithPath: "/tmp/catalog-\(UUID().uuidString)")
        let harness = makeCoordinatorComputeHarness(catalog: catalog, files: [])
        var isValid = true
        var applied = false

        let result = await harness.coordinator.run(
            request: harness.request,
            initialReviewStates: [:],
            fullCatalogFileIDs: Set<UUID>(),
            callbacks: BurstAnalysisRunCallbacks(
                isCurrent: { isValid },
                updateProgress: { progress in
                    if progress.step == .grouping {
                        isValid = false
                    }
                },
                didScoreSharpness: { _ in },
                applyResult: { result in
                    applied = true
                    return result
                },
            ),
        )

        #expect(result == nil)
        #expect(!applied)
        #expect(harness.repository.savedSnapshots.isEmpty)
    }

    @Test
    func `coordinator owns generation task and progress lifecycle`() async {
        let harness = makeCoordinatorHarness(
            catalog: URL(fileURLWithPath: "/tmp/catalog-\(UUID().uuidString)"),
            files: [],
        )
        let generation = harness.coordinator.beginGeneration()
        let task = Task<Void, Never> {}
        harness.coordinator.register(task, generation: generation)
        harness.coordinator.updateProgress(BurstAnalysisProgress(step: .ranking))

        #expect(generation == 1)
        #expect(harness.coordinator.task != nil)
        #expect(harness.coordinator.progress.step == .ranking)
        #expect(harness.coordinator.isCurrent(generation: generation))

        harness.coordinator.cancel()
        await task.value

        #expect(harness.coordinator.generation == 2)
        #expect(harness.coordinator.task == nil)
        #expect(!harness.coordinator.progress.isRunning)
        #expect(!harness.coordinator.isCurrent(generation: generation))
    }
}
