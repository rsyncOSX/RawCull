import Foundation
import PhotoAIContracts
@testable import RawCull
import RawCullCore
import Testing

@Suite("RawCull AI integration", .tags(.smoke))
struct RawCullAIIntegrationTests {
    @Test
    func `AI paths retain RawCull's canonical data namespaces`() {
        let root = isolatedRoot()
        let paths = RawCullAIPaths(
            applicationSupportRoot: root.appendingPathComponent("Application Support"),
            cachesRoot: root.appendingPathComponent("Caches"),
        )

        #expect(paths.applicationSupportDirectory.lastPathComponent == "RawCull")
        #expect(paths.modelsDirectory.path.hasSuffix("RawCull/Models"))
        #expect(paths.sam3ModelDirectory.path.hasSuffix("RawCull/Models/SAM3"))
        #expect(paths.clipDataCompModelDirectory.path.hasSuffix(
            "RawCull/Models/CLIP-DataComp",
        ))
        #expect(paths.clipOpenAIModelDirectory.path.hasSuffix(
            "RawCull/Models/CLIP-OpenAI",
        ))
        #expect(paths.modelLicenceAcceptancesURL.path.hasSuffix(
            "RawCull/ModelLicenceAcceptances.json",
        ))
        #expect(
            paths.clipModelDirectory(for: .dataComp)
                == paths.clipDataCompModelDirectory,
        )
        #expect(
            paths.clipModelDirectory(for: .openAI)
                == paths.clipOpenAIModelDirectory,
        )
        #expect(paths.subjectMaskDirectory.path.hasSuffix("no.blogspot.RawCull/SAM3Masks"))
        #expect(paths.burstAnalysisDirectory.path.hasSuffix("RawCull/BurstAnalysis"))
    }

    @MainActor
    @Test
    func `Composition root reports the complete Phase 1 capability surface`() async throws {
        let root = isolatedRoot()
        defer { try? FileManager.default.removeItem(at: root) }

        let paths = isolatedPaths(root: root)
        let integration = RawCullAIIntegration(
            paths: paths,
            bundle: .main,
            allowsBundledModelFallback: false,
        )
        let initialCapabilities = integration.capabilities()

        #expect(initialCapabilities.sam3Model == .checking(
            expectedLocations: [paths.sam3ModelDirectory],
        ))
        #expect(initialCapabilities.clipModelStatus(for: .dataComp) == .checking(
            expectedLocations: [paths.clipDataCompModelDirectory],
        ))
        #expect(initialCapabilities.clipModelStatus(for: .openAI) == .checking(
            expectedLocations: [paths.clipOpenAIModelDirectory],
        ))
        #expect(initialCapabilities.semanticSearchStatus(for: .dataComp) == .checking(
            expectedLocations: [paths.clipDataCompModelDirectory],
        ))
        #expect(initialCapabilities.semanticSearchStatus(for: .openAI) == .checking(
            expectedLocations: [paths.clipOpenAIModelDirectory],
        ))
        #expect(integration.deepAIReviewFeature.availability == .checking(
            expectedLocations: [paths.sam3ModelDirectory],
        ))

        let capabilities = try await integration.refreshCapabilities()

        #expect(capabilities.sam3Model == .missing(
            expectedLocations: [paths.sam3ModelDirectory],
        ))
        #expect(capabilities.clipModelStatus(for: .dataComp) == .missing(
            expectedLocations: [paths.clipDataCompModelDirectory],
        ))
        #expect(capabilities.clipModelStatus(for: .openAI) == .missing(
            expectedLocations: [paths.clipOpenAIModelDirectory],
        ))
        #expect(capabilities.semanticSearchStatus(for: .dataComp) == .unavailable(
            reason: "Semantic search requires a valid CLIP model.",
            expectedLocations: [paths.clipDataCompModelDirectory],
        ))
        #expect(capabilities.semanticSearchStatus(for: .openAI) == .unavailable(
            reason: "Semantic search requires a valid CLIP model.",
            expectedLocations: [paths.clipOpenAIModelDirectory],
        ))
        #expect(integration.semanticSearchService(clipModel: .dataComp) == nil)
        #expect(integration.semanticSearchService(clipModel: .openAI) == nil)
        #expect(integration.similarityService(
            prefersCLIP: false,
            clipModel: .dataComp,
        ).backendDescriptor.backend == "vision-feature-print")
        #expect(integration.similarityService(
            prefersCLIP: true,
            clipModel: .openAI,
        ).backendDescriptor.backend == "vision-feature-print")
        #expect(capabilities.visionFeaturePrint == .available(location: nil))
        #expect(capabilities.subjectMaskStorage == .available(
            location: paths.subjectMaskDirectory,
        ))
        #expect(capabilities.inProcessMaskGeneration == .missing(
            expectedLocations: [paths.sam3ModelDirectory],
        ))
        #expect(integration.deepAIReviewFeature.availability == .missing(
            expectedLocations: [paths.sam3ModelDirectory],
        ))
        #expect(FileManager.default.fileExists(atPath: paths.subjectMaskDirectory.path))
    }

    @Test
    func `Saved burst scan reads existing Vision cache evidence`() async throws {
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
            )
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
                    ),
                )
            }),
            groups: [
                SavedBurstEvidenceGroup(fileIDs: [firstID, secondID]),
                SavedBurstEvidenceGroup(fileIDs: [thirdID])
            ],
        )
        let validData = try JSONEncoder().encode(validPayload)
        try validData.write(to: cacheDirectory.appendingPathComponent("valid.json"))
        try Data("not-json".utf8).write(
            to: cacheDirectory.appendingPathComponent("invalid.json"),
        )

        let result = try await RawCullSavedBurstEvidenceScanner(
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

    @Test
    func `Model validation is reused until candidate metadata changes`() async throws {
        let root = isolatedRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(
            at: root,
            withIntermediateDirectories: true,
        )

        let assetURL = root.appendingPathComponent("model.aimodel")
        try Data([1]).write(to: assetURL)
        let metadata = ModelBundleMetadata(
            name: "Test Model",
            family: "test",
            assets: ["main": assetURL.lastPathComponent],
        )
        try JSONEncoder().encode(metadata).write(
            to: root.appendingPathComponent("metadata.json"),
        )

        let descriptor = ModelResourceDescriptor(
            kind: "test",
            bundleDescriptor: ModelBundleDescriptor(
                family: "test",
                fallbackName: "Test Model",
                requiredRelativePaths: [],
                acceptedAssetExtensions: ["aimodel"],
            ),
            preprocessingVersion: "test-v1",
            configurationVersion: "test-v1",
        )
        let manager = RawCullAIModelResourceManager(
            candidateURLs: [root],
            factory: ModelProviderFactory(descriptor: descriptor) { _ in
                CachedTestModelProvider()
            },
        )

        let first = try await manager.load()
        let second = try await manager.load()
        let firstProvider = try #require(first.provider)
        let secondProvider = try #require(second.provider)
        #expect(firstProvider === secondProvider)

        try Data([1, 2]).write(to: assetURL)
        let changed = try await manager.load()
        let changedProvider = try #require(changed.provider)
        #expect(changedProvider !== firstProvider)
    }

    @Test
    func `Missing and corrupt model resources recover after restoration`() async throws {
        let root = isolatedRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)

        let assetURL = root.appendingPathComponent("model.aimodel")
        try Data([1]).write(to: assetURL)
        try JSONEncoder().encode(ModelBundleMetadata(
            name: "Recoverable Model",
            family: "test",
            assets: ["main": assetURL.lastPathComponent],
        )).write(to: root.appendingPathComponent("metadata.json"))
        let descriptor = ModelResourceDescriptor(
            kind: "test",
            bundleDescriptor: ModelBundleDescriptor(
                family: "test",
                fallbackName: "Recoverable Model",
                requiredRelativePaths: [],
                acceptedAssetExtensions: ["aimodel"],
            ),
            preprocessingVersion: "test-v1",
            configurationVersion: "test-v1",
        )
        let manager = RawCullAIModelResourceManager(
            candidateURLs: [root],
            factory: ModelProviderFactory(descriptor: descriptor) { _ in
                guard try Data(contentsOf: assetURL).first == 1 else {
                    throw RecoverableModelError.corrupt
                }
                return CachedTestModelProvider()
            },
        )

        #expect(try await manager.load().provider != nil)

        try Data([9, 9]).write(to: assetURL)
        let corrupt = try await manager.load()
        #expect(corrupt.provider == nil)
        #expect(corrupt.providerInitializationFailure != nil)

        try FileManager.default.removeItem(at: assetURL)
        let missing = try await manager.load()
        #expect(missing.provider == nil)
        #expect(missing.capability.resource == nil)

        try Data([1, 2, 3]).write(to: assetURL)
        let restored = try await manager.load()
        #expect(restored.provider != nil)
        #expect(restored.providerInitializationFailure == nil)
    }

    @MainActor
    @Test
    func `Cancelling Settings refresh cancels its evidence scan`() async {
        let root = isolatedRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let paths = isolatedPaths(root: root)
        let integration = RawCullAIIntegration(
            paths: paths,
            bundle: .main,
            allowsBundledModelFallback: false,
        )
        let probe = SavedEvidenceCancellationProbe()
        let model = RawCullAISettingsModel(
            integration: integration,
            evidenceScan: {
                try await probe.scan()
            },
        )

        let refresh = Task {
            await model.refresh()
        }
        await probe.waitUntilStarted()
        refresh.cancel()
        await refresh.value

        #expect(await probe.didObserveCancellation())
        #expect(model.isScanningSavedBurstData == false)
        #expect(model.savedBurstEvidence == nil)
    }

    @MainActor
    @Test
    func `CLIP enablement and exclusive model selection persist`() async throws {
        let root = isolatedRoot()
        defer { try? FileManager.default.removeItem(at: root) }

        let defaultsSuite = "RawCullAIIntegrationTests.\(UUID().uuidString)"
        let userDefaults = try #require(UserDefaults(suiteName: defaultsSuite))
        defer { userDefaults.removePersistentDomain(forName: defaultsSuite) }
        userDefaults.set(
            RawCullCLIPModel.dataComp.rawValue,
            forKey: RawCullAISettingsModel.selectedCLIPModelPreferenceKey,
        )

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
        )
        var selectedBackends: [String] = []
        let model = RawCullAISettingsModel(
            integration: integration,
            userDefaults: userDefaults,
            similarityServiceDidChange: { service in
                selectedBackends.append(service.backendDescriptor.backend)
            },
        )

        #expect(model.useCLIPForSimilarity)
        #expect(model.selectedCLIPModel == .dataComp)
        await model.refresh()
        model.useCLIPForSimilarity = false
        #expect(!model.useCLIPForSimilarity)
        #expect(userDefaults.bool(forKey: RawCullAISettingsModel.useCLIPPreferenceKey) == false)

        model.useCLIPForSimilarity = true
        model.selectedCLIPModel = .dataComp
        await model.deleteSavedBurstData()

        #expect(model.useCLIPForSimilarity)
        #expect(model.selectedCLIPModel == .dataComp)
        #expect(userDefaults.bool(forKey: RawCullAISettingsModel.useCLIPPreferenceKey))
        #expect(
            userDefaults.string(
                forKey: RawCullAISettingsModel.selectedCLIPModelPreferenceKey,
            ) == RawCullCLIPModel.dataComp.rawValue,
        )
        #expect(selectedBackends == [
            "vision-feature-print",
            "vision-feature-print",
            "vision-feature-print"
        ])
        #expect(FileManager.default.fileExists(atPath: savedDataURL.path))

        let relaunchedModel = RawCullAISettingsModel(
            integration: integration,
            userDefaults: userDefaults,
        )
        #expect(relaunchedModel.useCLIPForSimilarity)
        #expect(relaunchedModel.selectedCLIPModel == .dataComp)
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

private final class CachedTestModelProvider: Sendable {}

private enum RecoverableModelError: Error {
    case corrupt
}

private actor SavedEvidenceCancellationProbe {
    private var started = false
    private var observedCancellation = false

    func scan() async throws -> RawCullSavedBurstEvidenceScanResult {
        started = true
        do {
            try await Task.sleep(for: .seconds(30))
            return .success(.empty)
        } catch is CancellationError {
            observedCancellation = true
            throw CancellationError()
        }
    }

    func waitUntilStarted() async {
        while !started {
            await Task.yield()
        }
    }

    func didObserveCancellation() -> Bool {
        observedCancellation
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
