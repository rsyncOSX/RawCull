import Foundation
@testable import RawCull
import PhotoAIContracts
import RawCullCore
import Testing

@Suite("RawCull AI integration", .tags(.smoke))
struct RawCullAIIntegrationTests {
    @Test("AI paths retain RawCull's canonical data namespaces")
    func canonicalPaths() {
        let root = isolatedRoot()
        let paths = RawCullAIPaths(
            applicationSupportRoot: root.appendingPathComponent("Application Support"),
            cachesRoot: root.appendingPathComponent("Caches"),
        )

        #expect(paths.applicationSupportDirectory.lastPathComponent == "RawCull")
        #expect(paths.modelsDirectory.path.hasSuffix("RawCull/Models"))
        #expect(paths.sam3ModelDirectory.path.hasSuffix("RawCull/Models/SAM3"))
        #expect(paths.clipModelDirectory.path.hasSuffix("RawCull/Models/CLIP"))
        #expect(paths.subjectMaskDirectory.path.hasSuffix("no.blogspot.RawCull/SAM3Masks"))
        #expect(paths.burstAnalysisDirectory.path.hasSuffix("RawCull/BurstAnalysis"))
    }

    @MainActor
    @Test("Composition root reports the complete Phase 1 capability surface")
    func capabilitySurface() {
        let root = isolatedRoot()
        defer { try? FileManager.default.removeItem(at: root) }

        let paths = isolatedPaths(root: root)
        let integration = RawCullAIIntegration(
            paths: paths,
            bundle: .main,
            allowsBundledModelFallback: false,
            maskWorkerExecutableNames: [],
        )
        let capabilities = integration.capabilities()

        #expect(capabilities.sam3Model == .missing(
            expectedLocations: [paths.sam3ModelDirectory],
        ))
        #expect(capabilities.clipModel == .missing(
            expectedLocations: [paths.clipModelDirectory],
        ))
        #expect(capabilities.visionFeaturePrint == .available(location: nil))
        #expect(capabilities.subjectMaskStorage == .available(
            location: paths.subjectMaskDirectory,
        ))
        #expect(capabilities.maskWorker == .unavailable(
            reason: "The source-controlled SAM 3 mask worker has not been added yet.",
        ))
        #expect(FileManager.default.fileExists(atPath: paths.subjectMaskDirectory.path))
    }

    @Test("Saved burst scan reads existing Vision cache evidence")
    func savedBurstEvidence() throws {
        let root = isolatedRoot()
        defer { try? FileManager.default.removeItem(at: root) }

        let cacheDirectory = root.appendingPathComponent("BurstAnalysis", isDirectory: true)
        try FileManager.default.createDirectory(
            at: cacheDirectory,
            withIntermediateDirectories: true,
        )
        let backend = RawCullVisionSimilarityService().backendDescriptor
        let firstID = UUID()
        let secondID = UUID()
        let thirdID = UUID()
        let sources = [
            AIImageSource(
                id: firstID,
                url: root.appendingPathComponent("first.ARW"),
                displayName: "first.ARW",
            ),
            AIImageSource(
                id: secondID,
                url: root.appendingPathComponent("second.ARW"),
                displayName: "second.ARW",
            ),
        ]
        let validPayload = SavedBurstEvidencePayload(
            schemaVersion: BurstAnalysisCache.schemaVersion,
            similaritySignature: BurstSimilaritySignature(
                groupingConfig: BurstGroupingConfig(),
                backendDescriptor: backend,
                artifactSchemaVersion: SimilarityArtifactDescriptor.currentSchemaVersion,
                embeddingThumbnailMaxPixelSize: SimilarityScoringModel.embeddingThumbnailMaxPixelSize,
                embeddingPipelineVersion: SimilarityScoringModel.embeddingPipelineVersion,
            ),
            embeddings: Dictionary(uniqueKeysWithValues: sources.enumerated().map { offset, source in
                (
                    source.id,
                    SimilarityArtifact(
                        descriptor: SimilarityArtifactDescriptor(
                            backend: backend,
                            dimensions: nil,
                            sourceFingerprint: SourceFingerprint(source: source),
                        ),
                        payload: Data([UInt8(offset + 1)]),
                    )
                )
            }),
            groups: [
                SavedBurstEvidenceGroup(fileIDs: [firstID, secondID]),
                SavedBurstEvidenceGroup(fileIDs: [thirdID]),
            ],
        )
        let validData = try JSONEncoder().encode(validPayload)
        try validData.write(to: cacheDirectory.appendingPathComponent("valid.json"))
        try Data("not-json".utf8).write(
            to: cacheDirectory.appendingPathComponent("invalid.json"),
        )

        let result = RawCullSavedBurstEvidenceScanner(
            cacheDirectory: cacheDirectory,
        ).scan()
        let evidence = try #require(result.evidence)

        #expect(evidence.cacheFileCount == 2)
        #expect(evidence.decodedCatalogCount == 1)
        #expect(evidence.burstGroupCount == 1)
        #expect(evidence.clipEmbeddingCount == 0)
        #expect(evidence.visionEmbeddingCount == 2)
        #expect(evidence.skippedCacheFileCount == 1)
        #expect(evidence.backend == .visionFeaturePrint)
    }

    @MainActor
    @Test("Placeholder controls do not activate CLIP or delete burst data")
    func placeholderControlsAreNoOps() async throws {
        let root = isolatedRoot()
        defer { try? FileManager.default.removeItem(at: root) }

        let paths = isolatedPaths(root: root)
        try FileManager.default.createDirectory(
            at: paths.burstAnalysisDirectory,
            withIntermediateDirectories: true,
        )
        let savedDataURL = paths.burstAnalysisDirectory
            .appendingPathComponent("must-remain.json")
        try Data("saved".utf8).write(to: savedDataURL)

        let integration = RawCullAIIntegration(
            paths: paths,
            bundle: .main,
            allowsBundledModelFallback: false,
            maskWorkerExecutableNames: [],
        )
        let model = RawCullAISettingsModel(integration: integration)

        model.useCLIPForSimilarity = true
        await model.deleteSavedBurstData()

        #expect(model.useCLIPForSimilarity == false)
        #expect(FileManager.default.fileExists(atPath: savedDataURL.path))
    }

    private func isolatedRoot() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("RawCullAIIntegrationTests", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
    }

    private func isolatedPaths(root: URL) -> RawCullAIPaths {
        RawCullAIPaths(
            applicationSupportRoot: root.appendingPathComponent(
                "Application Support",
                isDirectory: true,
            ),
            cachesRoot: root.appendingPathComponent("Caches", isDirectory: true),
        )
    }
}

private nonisolated struct SavedBurstEvidencePayload: Encodable {
    let schemaVersion: Int
    let similaritySignature: BurstSimilaritySignature
    let embeddings: [UUID: SimilarityArtifact]
    let groups: [SavedBurstEvidenceGroup]
}

private nonisolated struct SavedBurstEvidenceGroup: Encodable {
    let fileIDs: [UUID]
}

private extension RawCullSavedBurstEvidenceScanResult {
    var evidence: RawCullSavedBurstEvidence? {
        guard case let .success(evidence) = self else { return nil }
        return evidence
    }
}
