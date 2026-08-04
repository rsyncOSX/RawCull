import Foundation
import PhotoAIContracts
import PhotoAIStorage
@testable import RawCull
import Testing

@Suite("AI cache boundaries", .tags(.smoke))
struct AICacheBoundaryTests {
    @Test
    func `independent cache clears preserve ratings settings decisions models and licences`() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("AICacheBoundaryTests", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let settingsURL = root.appendingPathComponent("Application Support/RawCull/settings.json")
        let savedRecordsURL = root.appendingPathComponent("Application Support/RawCull/savedfiles.json")
        let burstDecisionURL = root.appendingPathComponent("Caches/RawCull/BurstAnalysis/decision.json")
        let licenceURL = root.appendingPathComponent("Application Support/RawCull/ModelLicenceAcceptances.json")
        let modelDirectory = root.appendingPathComponent("Application Support/RawCull/Models/CLIP-DataComp")
        let modelURL = modelDirectory.appendingPathComponent("model.bin")
        for url in [settingsURL, savedRecordsURL, burstDecisionURL, licenceURL, modelURL] {
            try FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(),
                withIntermediateDirectories: true,
            )
            try Data(url.lastPathComponent.utf8).write(to: url)
        }

        let thumbnailRoot = root.appendingPathComponent("Caches/RawCull/Thumbnails")
        let thumbnailCache = DiskCacheManager(cacheDirectory: thumbnailRoot)
        let thumbnailURL = thumbnailRoot
            .appendingPathComponent(ThumbnailCacheKey.schemaVersion, isDirectory: true)
            .appendingPathComponent("thumbnail.jpg")
        try Data([1]).write(to: thumbnailURL)
        try FileManager.default.setAttributes(
            [.modificationDate: Date.distantPast],
            ofItemAtPath: thumbnailURL.path,
        )

        let sourceURL = root.appendingPathComponent("catalog/image.raw")
        try FileManager.default.createDirectory(
            at: sourceURL.deletingLastPathComponent(),
            withIntermediateDirectories: true,
        )
        try Data([1]).write(to: sourceURL)
        let source = AIImageSource(id: UUID(), url: sourceURL, displayName: "image.raw")
        let similarityStore = PerFileAnalysisArtifactStore(
            storageDirectory: root.appendingPathComponent("Caches/RawCull/Similarity"),
        )
        _ = await similarityStore.upsert(
            artifacts: [source.id: boundaryArtifact(source: source)],
            sources: [source.id: source],
            pipeline: SimilarityScoringModel.artifactPipelineSignature,
        )

        let maskDirectory = root.appendingPathComponent("Caches/RawCull/SAM3Masks")
        let maskStore = try SubjectMaskDiskStore(cacheDirectory: maskDirectory)
        let maskURL = maskDirectory.appendingPathComponent("mask.json")
        try Data([1]).write(to: maskURL)

        try await verifyIndependentClears(BoundaryClearFixture(
            thumbnailCache: thumbnailCache,
            thumbnailURL: thumbnailURL,
            similarityStore: similarityStore,
            maskStore: maskStore,
            maskURL: maskURL,
            modelDirectory: modelDirectory,
            modelURL: modelURL,
            settingsURL: settingsURL,
            savedRecordsURL: savedRecordsURL,
            burstDecisionURL: burstDecisionURL,
            licenceURL: licenceURL,
        ))
    }

    private func verifyIndependentClears(_ fixture: BoundaryClearFixture) async throws {
        await fixture.thumbnailCache.pruneCache(maxAgeInDays: 0)
        #expect(!FileManager.default.fileExists(atPath: fixture.thumbnailURL.path))
        #expect(await fixture.similarityStore.usage().entryCount == 1)
        #expect(FileManager.default.fileExists(atPath: fixture.maskURL.path))
        #expect(FileManager.default.fileExists(atPath: fixture.modelURL.path))
        assertPersistentStateExists(
            settingsURL: fixture.settingsURL,
            savedRecordsURL: fixture.savedRecordsURL,
            burstDecisionURL: fixture.burstDecisionURL,
            licenceURL: fixture.licenceURL,
        )

        await fixture.similarityStore.clear()
        #expect(await fixture.similarityStore.usage().entryCount == 0)
        #expect(FileManager.default.fileExists(atPath: fixture.maskURL.path))
        #expect(FileManager.default.fileExists(atPath: fixture.modelURL.path))
        assertPersistentStateExists(
            settingsURL: fixture.settingsURL,
            savedRecordsURL: fixture.savedRecordsURL,
            burstDecisionURL: fixture.burstDecisionURL,
            licenceURL: fixture.licenceURL,
        )

        await fixture.maskStore.removeAll()
        #expect(!FileManager.default.fileExists(atPath: fixture.maskURL.path))
        #expect(FileManager.default.fileExists(atPath: fixture.modelURL.path))
        assertPersistentStateExists(
            settingsURL: fixture.settingsURL,
            savedRecordsURL: fixture.savedRecordsURL,
            burstDecisionURL: fixture.burstDecisionURL,
            licenceURL: fixture.licenceURL,
        )

        let removalService = BoundaryModelRemovalService(
            modelDirectory: fixture.modelDirectory,
        )
        let coordinator = RawCullAIModelDownloadCoordinator(
            service: removalService,
            acceptanceStore: BoundaryLicenceAcceptanceStore(),
        )
        try await coordinator.remove(.clipDataComp)
        #expect(!FileManager.default.fileExists(atPath: fixture.modelURL.path))
        assertPersistentStateExists(
            settingsURL: fixture.settingsURL,
            savedRecordsURL: fixture.savedRecordsURL,
            burstDecisionURL: fixture.burstDecisionURL,
            licenceURL: fixture.licenceURL,
        )
    }

    private func assertPersistentStateExists(
        settingsURL: URL,
        savedRecordsURL: URL,
        burstDecisionURL: URL,
        licenceURL: URL,
    ) {
        #expect(FileManager.default.fileExists(atPath: settingsURL.path))
        #expect(FileManager.default.fileExists(atPath: savedRecordsURL.path))
        #expect(FileManager.default.fileExists(atPath: burstDecisionURL.path))
        #expect(FileManager.default.fileExists(atPath: licenceURL.path))
    }
}

private struct BoundaryClearFixture: Sendable {
    let thumbnailCache: DiskCacheManager
    let thumbnailURL: URL
    let similarityStore: PerFileAnalysisArtifactStore
    let maskStore: SubjectMaskDiskStore
    let maskURL: URL
    let modelDirectory: URL
    let modelURL: URL
    let settingsURL: URL
    let savedRecordsURL: URL
    let burstDecisionURL: URL
    let licenceURL: URL
}

private nonisolated let boundaryBackend = SimilarityBackendDescriptor(
    backend: "clip",
    modelFingerprint: "boundary-test",
    representation: "boundary-vector-v1",
    preprocessingVersion: "boundary-v1",
    normalizationVersion: "l2-v1",
    configurationVersion: "boundary-v1",
)

private nonisolated func boundaryArtifact(source: AIImageSource) -> SimilarityArtifact {
    SimilarityArtifact(
        descriptor: SimilarityArtifactDescriptor(
            backend: boundaryBackend,
            dimensions: 1,
            sourceFingerprint: SourceFingerprint(source: source),
        ),
        payload: Data([1]),
    )
}

private actor BoundaryModelRemovalService: RawCullAIModelDownloadServicing {
    private let modelDirectory: URL

    init(modelDirectory: URL) {
        self.modelDirectory = modelDirectory
    }

    func state(for _: RawCullAIModelDownloadDescriptor) async -> RawCullAIModelDownloadState {
        .installed(location: modelDirectory)
    }

    func download(
        _: RawCullAIModelDownloadDescriptor,
        progress _: @escaping @MainActor @Sendable (Double) -> Void,
    ) async throws -> URL {
        modelDirectory
    }

    func remove(_: RawCullAIModelDownloadDescriptor) async throws {
        try FileManager.default.removeItem(at: modelDirectory)
    }
}

private actor BoundaryLicenceAcceptanceStore: RawCullAIModelLicenceAcceptanceStoring {
    func acceptance(
        for _: RawCullAIModelDownloadDescriptor,
    ) async throws -> RawCullAIModelLicenceAcceptance? {
        nil
    }

    func recordAcceptance(
        for _: RawCullAIModelDownloadDescriptor,
        rawCullVersion _: String,
    ) async throws {}
}
