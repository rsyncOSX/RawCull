import Foundation
import PhotoAnalysisKit
@testable import RawCull
import Testing

@Suite("Cache boundaries", .tags(.smoke))
struct AICacheBoundaryTests {
    @Test
    func `independent cache clears preserve user data`() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("CacheBoundaryTests", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let settingsURL = root.appendingPathComponent("Application Support/RawCull/settings.json")
        let savedRecordsURL = root.appendingPathComponent("Application Support/RawCull/savedfiles.json")
        for url in [settingsURL, savedRecordsURL] {
            try FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(),
                withIntermediateDirectories: true,
            )
            try Data(url.lastPathComponent.utf8).write(to: url)
        }

        let sourceURL = root.appendingPathComponent("catalog/image.raw")
        try FileManager.default.createDirectory(
            at: sourceURL.deletingLastPathComponent(),
            withIntermediateDirectories: true,
        )
        try Data([1]).write(to: sourceURL)
        let source = AIImageSource(id: UUID(), url: sourceURL, displayName: "image.raw")
        let store = PerFileAnalysisArtifactStore(
            storageDirectory: root.appendingPathComponent("Caches/RawCull/VisionSimilarity"),
        )
        let backend = SimilarityBackendDescriptor.vision(revision: 2)
        let artifact = SimilarityArtifact(
            descriptor: SimilarityArtifactDescriptor(source: source, backend: backend),
            featurePrint: VisionFeaturePrint(revision: 2, payload: Data([1])),
        )
        _ = await store.upsert(
            artifacts: [source.id: artifact],
            sources: [source.id: source],
            pipeline: SimilarityScoringModel.artifactPipelineSignature,
        )

        #expect(await store.usage().entryCount == 1)
        await store.clear()
        #expect(await store.usage().entryCount == 0)
        #expect(FileManager.default.fileExists(atPath: settingsURL.path))
        #expect(FileManager.default.fileExists(atPath: savedRecordsURL.path))
    }
}
