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
    let integration: RawCullAIIntegration
    let similarityFeature: RawCullSimilarityFeature
    /// Temporary burst/persistence compatibility reference for Phases 7/9.
    let similarityModel: SimilarityScoringModel
    let semanticSearchFeature: RawCullSemanticSearchFeature
    let deepAIReviewFeature: DeepAIReviewFeature
    let settingsModel: RawCullAISettingsModel
    let modelManagementModel: RawCullAIModelManagementModel
    private(set) var lastAppliedConfigurationIdentity:
        RawCullIntelligenceConfigurationIdentity?
    private(set) var lastAcceptedConfigurationRevision: UInt64?

    init(
        integration: RawCullAIIntegration,
        similarityFeature: RawCullSimilarityFeature,
        similarityModel: SimilarityScoringModel,
        semanticSearchFeature: RawCullSemanticSearchFeature,
        deepAIReviewFeature: DeepAIReviewFeature,
        settingsModel: RawCullAISettingsModel,
        applicationContext: any RawCullSimilarityApplicationContext,
    ) {
        self.integration = integration
        self.similarityFeature = similarityFeature
        self.similarityModel = similarityModel
        self.semanticSearchFeature = semanticSearchFeature
        self.deepAIReviewFeature = deepAIReviewFeature
        self.settingsModel = settingsModel
        self.modelManagementModel = settingsModel.modelManagementModel
        similarityFeature.bindApplicationContext(applicationContext)

        assert(similarityFeature.sharesSimilarityModelIdentity(with: similarityModel))
        assert(
            self.semanticSearchFeature.sharesSimilarityModelIdentity(
                with: similarityModel,
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
                return integration.capabilities()
            }
        }

        let previousIdentity = lastAppliedConfigurationIdentity
        guard previousIdentity != incomingIdentity else {
            lastAcceptedConfigurationRevision = configuration.revision
            return integration.capabilities()
        }

        if previousIdentity?.segmentationModel != incomingIdentity.segmentationModel {
            integration.setSelectedSegmentationModel(configuration.segmentationModel)
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
        return integration.capabilities()
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
        make(integration: RawCullAIIntegration())
    }

    static func make(
        integration: RawCullAIIntegration,
        similarityArtifactStore: any SimilarityArtifactStoring = PerFileAnalysisArtifactStore.shared,
        userDefaults: UserDefaults = .standard,
        evidenceScan: (@Sendable () async throws -> RawCullSavedBurstEvidenceScanResult)? = nil,
        modelDownloadCatalog: RawCullAIModelDownloadCatalog = .production,
        modelDownloadCoordinator: RawCullAIModelDownloadCoordinator? = nil,
        rawCullVersion: String? = nil,
    ) -> RawCullApplicationState {
        let modelManagementModel = RawCullAIModelManagementModel(
            paths: integration.paths,
            catalog: modelDownloadCatalog,
            coordinator: modelDownloadCoordinator,
            rawCullVersion: rawCullVersion,
        )
        let settingsModel = RawCullAISettingsModel(
            integration: integration,
            evidenceScan: evidenceScan,
            userDefaults: userDefaults,
            modelManagementModel: modelManagementModel,
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
        let deepAIReviewFeature = integration.deepAIReviewFeature
        let viewModel = RawCullViewModel(
            similarityModel: similarityModel,
            similarityFeature: similarityFeature,
            semanticSearchFeature: semanticSearchFeature,
            deepAIReviewFeature: deepAIReviewFeature,
        )
        let intelligenceRuntime = RawCullIntelligenceRuntime(
            integration: integration,
            similarityFeature: similarityFeature,
            similarityModel: similarityModel,
            semanticSearchFeature: semanticSearchFeature,
            deepAIReviewFeature: deepAIReviewFeature,
            settingsModel: settingsModel,
            applicationContext: viewModel,
        )
        semanticSearchFeature.bindApplicationTarget(viewModel)
        settingsModel.bindConfigurationConsumer(intelligenceRuntime)

        assert(viewModel.similarityModel === intelligenceRuntime.similarityModel)
        assert(viewModel.similarityFeature === intelligenceRuntime.similarityFeature)
        assert(semanticSearchFeature.sharesSimilarityFeatureIdentity(with: similarityFeature))
        assert(viewModel.semanticSearchFeature === intelligenceRuntime.semanticSearchFeature)
        assert(viewModel.deepAIReviewFeature === intelligenceRuntime.deepAIReviewFeature)
        assert(
            settingsModel.modelManagementModel
                === intelligenceRuntime.modelManagementModel,
        )

        return RawCullApplicationState(
            intelligenceRuntime: intelligenceRuntime,
            viewModel: viewModel,
        )
    }
}
