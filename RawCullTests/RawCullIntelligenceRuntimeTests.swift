import Foundation
import PhotoAIContracts
@testable import RawCull
import Testing

@Suite("RawCull intelligence runtime", .tags(.smoke))
struct RawCullIntelligenceRuntimeTests {
    @MainActor
    @Test
    func `Application assembly shares one stable intelligence object graph`() throws {
        let fixture = try makeFixture()
        defer { fixture.cleanUp() }

        let applicationState = RawCullApplicationState.make(
            integration: fixture.integration,
            similarityArtifactStore: fixture.similarityArtifactStore,
            userDefaults: fixture.userDefaults,
            evidenceScan: { .success(.empty) },
            modelDownloadCatalog: RawCullAIModelDownloadCatalog(models: []),
            rawCullVersion: "test",
        )
        let runtime = applicationState.intelligenceRuntime
        let viewModel = applicationState.viewModel

        #expect(runtime.integration === fixture.integration)
        #expect(runtime.similarityModel === viewModel.similarityModel)
        #expect(runtime.deepAIReviewFeature === fixture.integration.deepAIReviewFeature)
        #expect(runtime.deepAIReviewFeature === viewModel.deepAIReviewFeature)
        #expect(runtime.settingsModel === applicationState.intelligenceRuntime.settingsModel)
        #expect(runtime.similarityModel === applicationState.intelligenceRuntime.similarityModel)
    }

    @MainActor
    @Test
    func `Settings callbacks update the view model that shares the runtime models`() throws {
        let fixture = try makeFixture()
        defer { fixture.cleanUp() }
        fixture.userDefaults.set(
            true,
            forKey: RawCullAISettingsModel.useCLIPPreferenceKey,
        )

        let applicationState = RawCullApplicationState.make(
            integration: fixture.integration,
            similarityArtifactStore: fixture.similarityArtifactStore,
            userDefaults: fixture.userDefaults,
            evidenceScan: { .success(.empty) },
            modelDownloadCatalog: RawCullAIModelDownloadCatalog(models: []),
            rawCullVersion: "test",
        )
        let runtime = applicationState.intelligenceRuntime
        let viewModel = applicationState.viewModel
        let displacedCapability = RawCullSemanticSearchCapabilityStatus.failed(
            location: nil,
            reason: "runtime test",
        )

        viewModel.setSimilarityService(RuntimeTestSimilarityService())
        viewModel.setSemanticSearchCapability(displacedCapability, service: nil)
        #expect(viewModel.similarityModel.backendDescriptor == runtimeTestBackend)
        #expect(viewModel.similarityModel.semanticSearchCapability == displacedCapability)

        runtime.settingsModel.useCLIPForSimilarity = false

        #expect(
            viewModel.similarityModel.backendDescriptor
                == runtime.integration.visionSimilarityService.backendDescriptor,
        )
        #expect(
            viewModel.similarityModel.semanticSearchCapability
                == runtime.settingsModel.selectedSemanticSearchStatus,
        )
        #expect(viewModel.similarityModel === runtime.similarityModel)
    }

    @MainActor
    @Test
    func `Settings preserve similarity then semantic callback order`() throws {
        let fixture = try makeFixture()
        defer { fixture.cleanUp() }
        var callbackOrder: [String] = []
        let settingsModel = RawCullAISettingsModel(
            integration: fixture.integration,
            evidenceScan: { .success(.empty) },
            userDefaults: fixture.userDefaults,
            similarityServiceDidChange: { _ in
                callbackOrder.append("similarity")
            },
            semanticSearchCapabilityDidChange: { _, _ in
                callbackOrder.append("semantic")
            },
            modelDownloadCatalog: RawCullAIModelDownloadCatalog(models: []),
            rawCullVersion: "test",
        )

        settingsModel.useCLIPForSimilarity.toggle()

        #expect(callbackOrder == ["similarity", "semantic"])
    }

    @MainActor
    @Test
    func `Applying current services is a no-op for identity and hydration tasks`() throws {
        let fixture = try makeFixture()
        defer { fixture.cleanUp() }

        let applicationState = RawCullApplicationState.make(
            integration: fixture.integration,
            similarityArtifactStore: fixture.similarityArtifactStore,
            userDefaults: fixture.userDefaults,
            evidenceScan: { .success(.empty) },
            modelDownloadCatalog: RawCullAIModelDownloadCatalog(models: []),
            rawCullVersion: "test",
        )
        let runtime = applicationState.intelligenceRuntime
        let viewModel = applicationState.viewModel
        let similarityModel = runtime.similarityModel

        viewModel.setSimilarityService(runtime.integration.visionSimilarityService)
        viewModel.setSemanticSearchCapability(
            similarityModel.semanticSearchCapability,
            service: nil,
        )

        #expect(viewModel.similarityModel === similarityModel)
        #expect(viewModel.similarityHydrationTask == nil)
        #expect(viewModel.semanticSimilarityHydrationTask == nil)
    }

    @MainActor
    @Test
    func `Weak settings callbacks do not retain application state`() throws {
        let fixture = try makeFixture()
        defer { fixture.cleanUp() }

        weak var releasedRuntime: RawCullIntelligenceRuntime?
        weak var releasedViewModel: RawCullViewModel?
        weak var releasedSimilarityModel: SimilarityScoringModel?
        weak var releasedSettingsModel: RawCullAISettingsModel?

        do {
            let applicationState = RawCullApplicationState.make(
                integration: fixture.integration,
                similarityArtifactStore: fixture.similarityArtifactStore,
                userDefaults: fixture.userDefaults,
                evidenceScan: { .success(.empty) },
                modelDownloadCatalog: RawCullAIModelDownloadCatalog(models: []),
                rawCullVersion: "test",
            )
            releasedRuntime = applicationState.intelligenceRuntime
            releasedViewModel = applicationState.viewModel
            releasedSimilarityModel = applicationState.intelligenceRuntime.similarityModel
            releasedSettingsModel = applicationState.intelligenceRuntime.settingsModel
        }

        #expect(releasedRuntime == nil)
        #expect(releasedViewModel == nil)
        #expect(releasedSimilarityModel == nil)
        #expect(releasedSettingsModel == nil)
    }

    @MainActor
    private func makeFixture() throws -> RuntimeTestFixture {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(
                "RawCullIntelligenceRuntimeTests",
                isDirectory: true,
            )
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let defaultsSuite = "RawCullIntelligenceRuntimeTests.\(UUID().uuidString)"
        let userDefaults = try #require(UserDefaults(suiteName: defaultsSuite))
        let paths = RawCullAIPaths(
            applicationSupportRoot: root.appendingPathComponent(
                "Application Support",
                isDirectory: true,
            ),
            cachesRoot: root.appendingPathComponent("Caches", isDirectory: true),
        )
        let integration = RawCullAIIntegration(
            paths: paths,
            bundle: .main,
            allowsBundledModelFallback: false,
        )
        return RuntimeTestFixture(
            root: root,
            defaultsSuite: defaultsSuite,
            userDefaults: userDefaults,
            integration: integration,
            similarityArtifactStore: PerFileAnalysisArtifactStore(
                storageDirectory: root.appendingPathComponent(
                    "SimilarityArtifacts",
                    isDirectory: true,
                ),
            ),
        )
    }
}

@MainActor
private struct RuntimeTestFixture {
    let root: URL
    let defaultsSuite: String
    let userDefaults: UserDefaults
    let integration: RawCullAIIntegration
    let similarityArtifactStore: PerFileAnalysisArtifactStore

    func cleanUp() {
        userDefaults.removePersistentDomain(forName: defaultsSuite)
        try? FileManager.default.removeItem(at: root)
    }
}

private nonisolated let runtimeTestBackend = SimilarityBackendDescriptor(
    backend: "runtime-test",
    modelFingerprint: "runtime-test-model-v1",
    representation: "runtime-test-representation",
    preprocessingVersion: "runtime-test-preprocessing-v1",
    normalizationVersion: "runtime-test-normalization-v1",
    configurationVersion: "runtime-test-configuration-v1",
)

private nonisolated struct RuntimeTestSimilarityService: RawCullSimilarityServicing {
    let backendDescriptor = runtimeTestBackend

    func index(
        sources _: [AIImageSource],
        maxPixelSize _: Int,
        progress _: (@Sendable (RawCullSimilarityIndexingProgress) async -> Void)?,
    ) async throws -> RawCullSimilarityIndexingOutput {
        RawCullSimilarityIndexingOutput(artifacts: [:], failures: [])
    }

    func distance(
        from _: SimilarityArtifact,
        to _: SimilarityArtifact,
    ) throws -> Float? {
        nil
    }
}
