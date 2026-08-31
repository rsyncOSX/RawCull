import Foundation
import PhotoAnalysisKit
@testable import RawCull
import Testing

@Suite("Per-file Vision artifact store", .tags(.smoke))
struct PerFileAnalysisArtifactStoreTests {
    @Test
    func `Vision artifact round trips`() async throws {
        let fixture = try Fixture()
        let source = try fixture.source(named: "image.raw")
        let artifact = fixture.artifact(for: source, payload: Data([1, 2, 3]))

        let commit = await fixture.store.upsert(
            artifacts: [source.id: artifact],
            sources: [source.id: source],
            pipeline: fixture.pipeline,
        )
        let loaded = await fixture.store.load(
            sources: [source],
            allowedBackends: [fixture.backend],
            pipeline: fixture.pipeline,
        )

        #expect(commit.committedSourceIDs == [source.id])
        #expect(commit.failures.isEmpty)
        #expect(loaded.artifacts[source.id] == artifact)
        #expect(loaded.misses.isEmpty)
    }

    @Test
    func `Changed source fingerprint is a cold cache miss`() async throws {
        let fixture = try Fixture()
        let source = try fixture.source(named: "changed.raw", contents: Data([1]))
        let artifact = fixture.artifact(for: source, payload: Data([4]))
        _ = await fixture.store.upsert(
            artifacts: [source.id: artifact],
            sources: [source.id: source],
            pipeline: fixture.pipeline,
        )
        let movedURL = source.url.deletingLastPathComponent()
            .appendingPathComponent("changed-moved.raw")
        try FileManager.default.moveItem(at: source.url, to: movedURL)
        let changed = AIImageSource(id: source.id, url: movedURL, displayName: source.displayName)

        let loaded = await fixture.store.load(
            sources: [changed],
            allowedBackends: [fixture.backend],
            pipeline: fixture.pipeline,
        )

        #expect(loaded.artifacts.isEmpty)
        #expect(loaded.misses == [.init(sourceID: source.id, reason: .notFound)])
    }

    @Test
    func `Remove deletes one Vision artifact`() async throws {
        let fixture = try Fixture()
        let source = try fixture.source(named: "remove.raw")
        let artifact = fixture.artifact(for: source, payload: Data([8]))
        _ = await fixture.store.upsert(
            artifacts: [source.id: artifact],
            sources: [source.id: source],
            pipeline: fixture.pipeline,
        )

        await fixture.store.remove(source: source, backend: fixture.backend, pipeline: fixture.pipeline)
        let loaded = await fixture.store.load(
            sources: [source],
            allowedBackends: [fixture.backend],
            pipeline: fixture.pipeline,
        )

        #expect(loaded.artifacts.isEmpty)
        #expect(loaded.misses == [.init(sourceID: source.id, reason: .notFound)])
    }
}

private struct Fixture {
    let directory: URL
    let store: PerFileAnalysisArtifactStore
    let backend = SimilarityBackendDescriptor.vision(revision: 2)
    let pipeline = SimilarityArtifactPipelineSignature(thumbnailMaxPixelSize: 512, pipelineVersion: 3)

    init() throws {
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("RawCullVisionStoreTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        store = PerFileAnalysisArtifactStore(storageDirectory: directory.appendingPathComponent("cache"))
    }

    func source(named name: String, contents: Data = Data([0])) throws -> AIImageSource {
        let url = directory.appendingPathComponent(name)
        try contents.write(to: url)
        return AIImageSource(id: UUID(), url: url, displayName: name)
    }

    func artifact(for source: AIImageSource, payload: Data) -> SimilarityArtifact {
        SimilarityArtifact(
            descriptor: SimilarityArtifactDescriptor(source: source, backend: backend),
            featurePrint: VisionFeaturePrint(revision: backend.configurationVersion, payload: payload),
        )
    }
}
