import Foundation
import PhotoAIContracts

nonisolated struct RawCullIntelligenceConfigurationIdentity: Equatable, Sendable {
    let similarityBackend: SimilarityBackendDescriptor
    let similarityArtifactBackends: [SimilarityBackendDescriptor]
    let semanticSearchCapability: RawCullSemanticSearchCapabilityStatus
    let semanticSearchBackend: SimilarityBackendDescriptor?
    let segmentationModel: RawCullSegmentationModel
}

@MainActor
struct RawCullSimilarityConfiguration {
    let service: any RawCullSimilarityServicing
}

@MainActor
struct RawCullSemanticSearchConfiguration {
    let capability: RawCullSemanticSearchCapabilityStatus
    let service: (any RawCullSemanticSearchServicing)?
}

/// One complete, ordered settings decision for RawCull's intelligence runtime.
///
/// Service values stay on the main actor. Only the descriptor-based identity is
/// `Sendable`, which prevents concrete providers from crossing isolation domains.
@MainActor
struct RawCullIntelligenceConfiguration {
    let revision: UInt64
    let similarity: RawCullSimilarityConfiguration
    let semanticSearch: RawCullSemanticSearchConfiguration
    let segmentationModel: RawCullSegmentationModel

    var identity: RawCullIntelligenceConfigurationIdentity {
        RawCullIntelligenceConfigurationIdentity(
            similarityBackend: similarity.service.backendDescriptor,
            similarityArtifactBackends: similarity.service.artifactBackendDescriptors,
            semanticSearchCapability: semanticSearch.capability,
            semanticSearchBackend: semanticSearch.service?.backendDescriptor,
            segmentationModel: segmentationModel,
        )
    }
}

@MainActor
protocol RawCullIntelligenceConfigurationApplying: AnyObject {
    @discardableResult
    func apply(
        configuration: RawCullIntelligenceConfiguration,
    ) -> RawCullAICapabilities
}

/// Stable application-owned lifetime for RawCull's intelligence models.
@MainActor
final class RawCullIntelligenceRuntime: RawCullIntelligenceConfigurationApplying {
    let modelRuntime: RawCullAIModelRuntime
    let similarityFeature: RawCullSimilarityFeature
    let semanticSearchFeature: RawCullSemanticSearchFeature
    let deepAIReviewController: DeepAIReviewController
    let qwenAnalysisFeature: RawCullQwenAnalysisFeature
    let objectAnalysisFeature: RawCullObjectAnalysisFeature
    let settingsModel: RawCullAISettingsModel
    let modelDownloadsModel: RawCullAIModelDownloadsModel
    private(set) var lastAppliedConfigurationIdentity:
        RawCullIntelligenceConfigurationIdentity?
    private(set) var lastAcceptedConfigurationRevision: UInt64?

    init(
        modelRuntime: RawCullAIModelRuntime,
        similarityFeature: RawCullSimilarityFeature,
        semanticSearchFeature: RawCullSemanticSearchFeature,
        deepAIReviewController: DeepAIReviewController,
        qwenAnalysisFeature: RawCullQwenAnalysisFeature,
        objectAnalysisFeature: RawCullObjectAnalysisFeature? = nil,
        settingsModel: RawCullAISettingsModel,
        applicationContext: any RawCullSimilarityApplicationContext,
    ) {
        self.modelRuntime = modelRuntime
        self.similarityFeature = similarityFeature
        self.semanticSearchFeature = semanticSearchFeature
        self.deepAIReviewController = deepAIReviewController
        self.qwenAnalysisFeature = qwenAnalysisFeature
        self.objectAnalysisFeature = objectAnalysisFeature
            ?? RawCullObjectAnalysisFeature(inference: modelRuntime.qwenInference)
        self.settingsModel = settingsModel
        self.modelDownloadsModel = settingsModel.modelDownloadsModel
        similarityFeature.bindApplicationContext(applicationContext)

        assert(
            self.semanticSearchFeature.sharesSimilarityFeatureIdentity(
                with: similarityFeature,
            ),
        )
        assert(
            qwenAnalysisFeature.sharesInferenceIdentity(
                with: modelRuntime.qwenInference,
            ),
        )
        assert(
            self.objectAnalysisFeature.sharesInferenceIdentity(
                with: modelRuntime.qwenInference,
            ),
        )
        assert(
            settingsModel.sharesModelRuntimeIdentity(
                modelRuntime,
                analysisFeature: qwenAnalysisFeature,
            ),
        )
    }

    @discardableResult
    func apply(
        configuration: RawCullIntelligenceConfiguration,
    ) -> RawCullAICapabilities {
        let incomingIdentity = configuration.identity

        if let lastAcceptedConfigurationRevision {
            guard configuration.revision > lastAcceptedConfigurationRevision else {
                assert(
                    configuration.revision < lastAcceptedConfigurationRevision
                        || incomingIdentity == lastAppliedConfigurationIdentity,
                    "One configuration revision described multiple identities.",
                )
                return modelRuntime.capabilities()
            }
        }

        let previousIdentity = lastAppliedConfigurationIdentity
        guard previousIdentity != incomingIdentity else {
            lastAcceptedConfigurationRevision = configuration.revision
            return modelRuntime.capabilities()
        }

        if previousIdentity?.segmentationModel != incomingIdentity.segmentationModel {
            modelRuntime.setSelectedSegmentationModel(configuration.segmentationModel)
        }

        if previousIdentity?.similarityBackend != incomingIdentity.similarityBackend
            || previousIdentity?.similarityArtifactBackends
            != incomingIdentity.similarityArtifactBackends {
            similarityFeature.replaceSimilarityService(configuration.similarity.service)
        }

        if previousIdentity?.semanticSearchCapability
            != incomingIdentity.semanticSearchCapability
            || previousIdentity?.semanticSearchBackend
            != incomingIdentity.semanticSearchBackend {
            similarityFeature.replaceSemanticSearchConfiguration(
                capability: configuration.semanticSearch.capability,
                service: configuration.semanticSearch.service,
            )
        }

        lastAppliedConfigurationIdentity = incomingIdentity
        lastAcceptedConfigurationRevision = configuration.revision
        return modelRuntime.capabilities()
    }
}

/// The two stable roots retained by `RawCullApp`.
///
/// Keeping assembly here makes duplicate intelligence models difficult to create
/// while leaving general application state outside the intelligence runtime.
@MainActor
struct RawCullApplicationState {
    let intelligenceRuntime: RawCullIntelligenceRuntime
    let viewModel: RawCullViewModel

    static func live() -> RawCullApplicationState {
        make(modelRuntime: RawCullAIModelRuntime())
    }

    static func make(
        modelRuntime: RawCullAIModelRuntime,
        similarityArtifactStore: any SimilarityArtifactStoring = PerFileAnalysisArtifactStore.shared,
        userDefaults: UserDefaults = .standard,
        evidenceScan: (@Sendable () async throws -> RawCullSavedBurstEvidenceScanResult)? = nil,
        modelDownloadCatalog: RawCullAIModelDownloadCatalog = .production,
        modelDownloadCoordinator: RawCullAIModelDownloadCoordinator? = nil,
        rawCullVersion: String? = nil,
    ) -> RawCullApplicationState {
        let modelDownloadsModel = RawCullAIModelDownloadsModel(
            paths: modelRuntime.paths,
            catalog: modelDownloadCatalog,
            coordinator: modelDownloadCoordinator,
            rawCullVersion: rawCullVersion,
        )
        let qwenAnalysisFeature = RawCullQwenAnalysisFeature(
            inference: modelRuntime.qwenInference,
        )
        let objectAnalysisFeature = RawCullObjectAnalysisFeature(
            inference: modelRuntime.qwenInference,
            maskStores: [modelRuntime.objectMaskMemoryStore]
                + (modelRuntime.objectMaskDiskStore.map { [$0 as any ObjectMaskStoring] } ?? []),
        )
        let deepAIReviewFeature = DeepAIReviewFeature(
            availability: modelRuntime.capabilities().inProcessMaskGeneration,
        )
        modelRuntime.bindDeepAIReviewFeature(deepAIReviewFeature)
        let settingsModel = RawCullAISettingsModel(
            modelRuntime: modelRuntime,
            evidenceScan: evidenceScan,
            userDefaults: userDefaults,
            modelDownloadsModel: modelDownloadsModel,
            qwenAnalysisFeature: qwenAnalysisFeature,
            objectAnalysisFeature: objectAnalysisFeature,
        )
        let initialConfiguration = settingsModel.configurationSnapshot()
        let similarityModel = SimilarityScoringModel(
            similarityService: initialConfiguration.similarity.service,
            semanticSearchCapability: initialConfiguration.semanticSearch.capability,
            semanticSearchService: initialConfiguration.semanticSearch.service,
            artifactStore: similarityArtifactStore,
        )
        let similarityFeature = RawCullSimilarityFeature(
            similarityModel: similarityModel,
        )
        let semanticSearchFeature = RawCullSemanticSearchFeature(
            similarityModel: similarityModel,
            similarityFeature: similarityFeature,
        )
        let deepAIReviewController = DeepAIReviewController(
            feature: deepAIReviewFeature,
        )
        let viewModel = RawCullViewModel(
            similarityModel: similarityModel,
            similarityFeature: similarityFeature,
            semanticSearchFeature: semanticSearchFeature,
            deepAIReviewController: deepAIReviewController,
        )
        let intelligenceRuntime = RawCullIntelligenceRuntime(
            modelRuntime: modelRuntime,
            similarityFeature: similarityFeature,
            semanticSearchFeature: semanticSearchFeature,
            deepAIReviewController: deepAIReviewController,
            qwenAnalysisFeature: qwenAnalysisFeature,
            objectAnalysisFeature: objectAnalysisFeature,
            settingsModel: settingsModel,
            applicationContext: viewModel,
        )
        semanticSearchFeature.bindApplicationTarget(viewModel)
        settingsModel.bindConfigurationConsumer(intelligenceRuntime)

        assert(viewModel.similarityFeature === intelligenceRuntime.similarityFeature)
        assert(semanticSearchFeature.sharesSimilarityFeatureIdentity(with: similarityFeature))
        assert(viewModel.semanticSearchFeature === intelligenceRuntime.semanticSearchFeature)
        assert(viewModel.deepAIReviewController === intelligenceRuntime.deepAIReviewController)
        assert(qwenAnalysisFeature === intelligenceRuntime.qwenAnalysisFeature)
        assert(objectAnalysisFeature === intelligenceRuntime.objectAnalysisFeature)
        assert(
            intelligenceRuntime.qwenAnalysisFeature.sharesInferenceIdentity(
                with: intelligenceRuntime.modelRuntime.qwenInference,
            ),
        )
        assert(
            intelligenceRuntime.deepAIReviewController.sharesFeatureIdentity(
                with: deepAIReviewFeature,
            ),
        )
        assert(
            settingsModel.modelDownloadsModel
                === intelligenceRuntime.modelDownloadsModel,
        )

        return RawCullApplicationState(
            intelligenceRuntime: intelligenceRuntime,
            viewModel: viewModel,
        )
    }
}
