import Foundation
import PhotoAIContracts
@testable import RawCull
import RawCullCore
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
        #expect(runtime.similarityFeature === viewModel.similarityFeature)
        #expect(runtime.similarityModel === viewModel.similarityModel)
        #expect(runtime.semanticSearchFeature === viewModel.semanticSearchFeature)
        #expect(
            runtime.semanticSearchFeature.sharesSimilarityModelIdentity(
                with: runtime.similarityModel,
            ),
        )
        #expect(
            runtime.semanticSearchFeature.sharesSimilarityFeatureIdentity(
                with: runtime.similarityFeature,
            ),
        )
        #expect(runtime.deepAIReviewFeature === fixture.integration.deepAIReviewFeature)
        #expect(runtime.deepAIReviewFeature === viewModel.deepAIReviewFeature)
        #expect(runtime.settingsModel === applicationState.intelligenceRuntime.settingsModel)
        #expect(
            runtime.modelManagementModel
                === runtime.settingsModel.modelManagementModel,
        )
        #expect(runtime.similarityModel === applicationState.intelligenceRuntime.similarityModel)
    }

    @MainActor
    @Test
    func `Settings configuration updates the view model that shares runtime models`() throws {
        let fixture = try makeFixture()
        defer { fixture.cleanUp() }
        fixture.userDefaults.set(
            RawCullCLIPModel.dataComp.rawValue,
            forKey: RawCullAISettingsModel.selectedCLIPModelPreferenceKey,
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
        let originalCapability = viewModel.similarityModel.semanticSearchCapability

        runtime.settingsModel.selectedCLIPModel = .openAI

        #expect(
            viewModel.similarityModel.backendDescriptor
                == runtime.integration.visionSimilarityService.backendDescriptor,
        )
        #expect(
            viewModel.similarityModel.semanticSearchCapability
                == runtime.settingsModel.selectedSemanticSearchStatus,
        )
        #expect(viewModel.similarityModel.semanticSearchCapability != originalCapability)
        #expect(viewModel.similarityModel === runtime.similarityModel)
    }

    @MainActor
    @Test
    func `Runtime shares one feature across similarity and semantic configuration`() throws {
        let fixture = try makeFixture()
        defer { fixture.cleanUp() }
        let target = RuntimeApplicationTargetSpy()
        let settingsModel = RawCullAISettingsModel(
            integration: fixture.integration,
            evidenceScan: { .success(.empty) },
            userDefaults: fixture.userDefaults,
            modelDownloadCatalog: RawCullAIModelDownloadCatalog(models: []),
            rawCullVersion: "test",
        )
        let configuration = settingsModel.configurationSnapshot(revision: 1)
        let similarityModel = SimilarityScoringModel(
            similarityService: configuration.similarity.service,
            semanticSearchCapability: configuration.semanticSearch.capability,
            semanticSearchService: configuration.semanticSearch.service,
            artifactStore: fixture.similarityArtifactStore,
        )
        let similarityFeature = RawCullSimilarityFeature(
            similarityModel: similarityModel,
        )
        let runtime = RawCullIntelligenceRuntime(
            integration: fixture.integration,
            similarityFeature: similarityFeature,
            similarityModel: similarityModel,
            semanticSearchFeature: RawCullSemanticSearchFeature(
                similarityModel: similarityModel,
                similarityFeature: similarityFeature,
            ),
            deepAIReviewFeature: fixture.integration.deepAIReviewFeature,
            settingsModel: settingsModel,
            applicationContext: target,
        )

        runtime.apply(configuration: configuration)

        #expect(runtime.similarityFeature === similarityFeature)
        #expect(runtime.similarityModel === similarityModel)
        #expect(target.burstResetCount == 0)
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

        let nextRevision = try #require(runtime.lastAcceptedConfigurationRevision) + 1
        runtime.apply(
            configuration: runtime.settingsModel.configurationSnapshot(
                revision: nextRevision,
            ),
        )

        #expect(viewModel.similarityModel === similarityModel)
        #expect(runtime.similarityFeature.imageHydrationTask == nil)
        #expect(runtime.similarityFeature.semanticHydrationTask == nil)
        #expect(runtime.lastAcceptedConfigurationRevision == nextRevision)
    }

    @MainActor
    @Test
    func `Older configuration cannot replace a newer runtime identity`() throws {
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
        let staleConfiguration = runtime.settingsModel.configurationSnapshot(
            revision: 2,
        )
        let newerCapability = RawCullSemanticSearchCapabilityStatus.failed(
            location: nil,
            reason: "newer runtime configuration",
        )
        let newerConfiguration = RawCullIntelligenceConfiguration(
            revision: 3,
            similarity: RawCullSimilarityConfiguration(
                service: RuntimeTestSimilarityService(),
            ),
            semanticSearch: RawCullSemanticSearchConfiguration(
                capability: newerCapability,
                service: nil,
            ),
            segmentationModel: staleConfiguration.segmentationModel,
        )

        runtime.apply(configuration: newerConfiguration)
        runtime.apply(configuration: staleConfiguration)

        #expect(runtime.similarityModel.backendDescriptor == runtimeTestBackend)
        #expect(runtime.similarityModel.semanticSearchCapability == newerCapability)
        #expect(runtime.lastAcceptedConfigurationRevision == 3)
        #expect(runtime.lastAppliedConfigurationIdentity == newerConfiguration.identity)
    }

    @MainActor
    @Test
    func `Segmentation-only configuration preserves similarity work`() throws {
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
        let current = runtime.settingsModel.configurationSnapshot(revision: 2)
        let segmentationOnly = RawCullIntelligenceConfiguration(
            revision: current.revision,
            similarity: current.similarity,
            semanticSearch: current.semanticSearch,
            segmentationModel: .efficientSAM,
        )

        let capabilities = runtime.apply(configuration: segmentationOnly)

        #expect(runtime.lastAppliedConfigurationIdentity?.segmentationModel == .efficientSAM)
        #expect(
            capabilities.inProcessMaskGeneration
                == capabilities.segmentationModelStatus(for: .efficientSAM),
        )
        #expect(runtime.similarityFeature.imageHydrationTask == nil)
        #expect(runtime.similarityFeature.semanticHydrationTask == nil)
        #expect(runtime.similarityModel.backendDescriptor == current.identity.similarityBackend)
        #expect(
            runtime.similarityModel.semanticSearchCapability
                == current.semanticSearch.capability,
        )
    }

    @MainActor
    @Test
    func `Configuration switch supersedes in-flight similarity hydration`() async throws {
        let fixture = try makeFixture()
        defer { fixture.cleanUp() }
        let hydrationStore = RuntimeHydrationStore(
            suspendedBackend: runtimeTestBackend,
        )
        let applicationState = RawCullApplicationState.make(
            integration: fixture.integration,
            similarityArtifactStore: hydrationStore,
            userDefaults: fixture.userDefaults,
            evidenceScan: { .success(.empty) },
            modelDownloadCatalog: RawCullAIModelDownloadCatalog(models: []),
            rawCullVersion: "test",
        )
        let runtime = applicationState.intelligenceRuntime
        let viewModel = applicationState.viewModel
        viewModel.files = [
            FileItem(
                id: UUID(),
                url: fixture.root.appendingPathComponent("hydration.raw"),
                name: "hydration.raw",
                size: 1,
                dateModified: .now,
                exifData: nil,
                afFocusNormalized: nil,
            )
        ]
        let current = runtime.settingsModel.configurationSnapshot(revision: 2)
        let first = RawCullIntelligenceConfiguration(
            revision: 2,
            similarity: RawCullSimilarityConfiguration(
                service: RuntimeTestSimilarityService(),
            ),
            semanticSearch: current.semanticSearch,
            segmentationModel: current.segmentationModel,
        )
        runtime.apply(configuration: first)
        let oldHydration = try #require(runtime.similarityFeature.imageHydrationTask)
        await hydrationStore.waitUntilSuspended()

        let replacement = RawCullIntelligenceConfiguration(
            revision: 3,
            similarity: RawCullSimilarityConfiguration(
                service: RuntimeReplacementSimilarityService(),
            ),
            semanticSearch: current.semanticSearch,
            segmentationModel: current.segmentationModel,
        )
        runtime.apply(configuration: replacement)
        let replacementHydration = try #require(runtime.similarityFeature.imageHydrationTask)
        await replacementHydration.value
        await hydrationStore.release()
        await oldHydration.value

        #expect(runtime.similarityModel.backendDescriptor == runtimeReplacementBackend)
        #expect(runtime.lastAppliedConfigurationIdentity == replacement.identity)
        #expect(runtime.similarityFeature.imageHydrationTask == nil)
    }

    @MainActor
    @Test
    func `Weak typed configuration edges do not retain application state`() throws {
        let fixture = try makeFixture()
        defer { fixture.cleanUp() }

        weak var releasedRuntime: RawCullIntelligenceRuntime?
        weak var releasedViewModel: RawCullViewModel?
        weak var releasedSimilarityModel: SimilarityScoringModel?
        weak var releasedSimilarityFeature: RawCullSimilarityFeature?
        weak var releasedSemanticSearchFeature: RawCullSemanticSearchFeature?
        weak var releasedSettingsModel: RawCullAISettingsModel?
        weak var releasedModelManagementModel: RawCullAIModelManagementModel?

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
            releasedSimilarityFeature = applicationState.intelligenceRuntime.similarityFeature
            releasedSemanticSearchFeature = applicationState.intelligenceRuntime
                .semanticSearchFeature
            releasedSettingsModel = applicationState.intelligenceRuntime.settingsModel
            releasedModelManagementModel = applicationState.intelligenceRuntime
                .modelManagementModel
        }

        #expect(releasedRuntime == nil)
        #expect(releasedViewModel == nil)
        #expect(releasedSimilarityModel == nil)
        #expect(releasedSimilarityFeature == nil)
        #expect(releasedSemanticSearchFeature == nil)
        #expect(releasedSettingsModel == nil)
        #expect(releasedModelManagementModel == nil)
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

private nonisolated let runtimeReplacementBackend = SimilarityBackendDescriptor(
    backend: "runtime-replacement",
    modelFingerprint: "runtime-replacement-model-v1",
    representation: "runtime-replacement-representation",
    preprocessingVersion: "runtime-replacement-preprocessing-v1",
    normalizationVersion: "runtime-replacement-normalization-v1",
    configurationVersion: "runtime-replacement-configuration-v1",
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

private nonisolated struct RuntimeReplacementSimilarityService:
    RawCullSimilarityServicing {
    let backendDescriptor = runtimeReplacementBackend

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

private actor RuntimeHydrationStore: SimilarityArtifactStoring {
    private let suspendedBackend: SimilarityBackendDescriptor
    private var isSuspended = false
    private var continuation: CheckedContinuation<Void, Never>?

    init(suspendedBackend: SimilarityBackendDescriptor) {
        self.suspendedBackend = suspendedBackend
    }

    func load(
        sources _: [AIImageSource],
        allowedBackends: [SimilarityBackendDescriptor],
        pipeline _: SimilarityArtifactPipelineSignature,
    ) async -> PerFileAnalysisArtifactLoadResult {
        if allowedBackends.first == suspendedBackend {
            isSuspended = true
            await withCheckedContinuation { continuation in
                self.continuation = continuation
            }
        }
        return PerFileAnalysisArtifactLoadResult(artifacts: [:], misses: [])
    }

    func upsert(
        artifacts _: [UUID: SimilarityArtifact],
        sources _: [UUID: AIImageSource],
        pipeline _: SimilarityArtifactPipelineSignature,
    ) async -> PerFileAnalysisArtifactCommitResult {
        PerFileAnalysisArtifactCommitResult(
            committedSourceIDs: [],
            failures: [],
            wasCancelled: false,
        )
    }

    func remove(
        source _: AIImageSource,
        backend _: SimilarityBackendDescriptor,
        pipeline _: SimilarityArtifactPipelineSignature,
    ) async {}

    func waitUntilSuspended() async {
        while !isSuspended {
            await Task.yield()
        }
    }

    func release() {
        continuation?.resume()
        continuation = nil
    }
}

@MainActor
private final class RuntimeApplicationTargetSpy: RawCullSimilarityApplicationContext {
    private(set) var burstResetCount = 0
    var currentSimilarityCatalogSnapshot = RawCullSimilarityCatalogSnapshot(
        files: [],
        identity: RawCullSimilarityCatalogIdentity(
            catalogURL: nil,
            generation: 0,
        ),
    )

    func cancelAndResetBurstAnalysisForSimilarityBackendChange() {
        burstResetCount += 1
    }
}
