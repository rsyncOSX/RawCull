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

/// Temporary Phase 3 bridge to application-owned catalog and burst state.
/// Phase 6 moves the hydration workers behind the intelligence feature boundary.
@MainActor
protocol RawCullIntelligenceApplicationTarget: AnyObject {
    func setSimilarityService(_ service: any RawCullSimilarityServicing)

    func setSemanticSearchCapability(
        _ capability: RawCullSemanticSearchCapabilityStatus,
        service: (any RawCullSemanticSearchServicing)?,
    )
}

extension RawCullViewModel: RawCullIntelligenceApplicationTarget {}

/// Stable application-owned lifetime for RawCull's intelligence models.
///
/// Phase 3 owns the single settings-configuration ingress while deliberately
/// leaving hydration worker-task ownership in `RawCullViewModel` until Phase 6.
@MainActor
final class RawCullIntelligenceRuntime: RawCullIntelligenceConfigurationApplying {
    let integration: RawCullAIIntegration
    let similarityModel: SimilarityScoringModel
    let semanticSearchFeature: RawCullSemanticSearchFeature
    let deepAIReviewFeature: DeepAIReviewFeature
    let settingsModel: RawCullAISettingsModel
    let modelManagementModel: RawCullAIModelManagementModel
    private(set) var lastAppliedConfigurationIdentity:
        RawCullIntelligenceConfigurationIdentity?
    private(set) var lastAcceptedConfigurationRevision: UInt64?

    private weak var applicationTarget:
        (any RawCullIntelligenceApplicationTarget)?

    init(
        integration: RawCullAIIntegration,
        similarityModel: SimilarityScoringModel,
        semanticSearchFeature: RawCullSemanticSearchFeature,
        deepAIReviewFeature: DeepAIReviewFeature,
        settingsModel: RawCullAISettingsModel,
        applicationTarget: any RawCullIntelligenceApplicationTarget,
    ) {
        self.integration = integration
        self.similarityModel = similarityModel
        self.semanticSearchFeature = semanticSearchFeature
        self.deepAIReviewFeature = deepAIReviewFeature
        self.settingsModel = settingsModel
        self.modelManagementModel = settingsModel.modelManagementModel
        self.applicationTarget = applicationTarget

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
            != incomingIdentity.similarityArtifactBackends
        {
            applicationTarget?.setSimilarityService(configuration.similarity.service)
        }

        if previousIdentity?.semanticSearchCapability
            != incomingIdentity.semanticSearchCapability
            || previousIdentity?.semanticSearchBackend
            != incomingIdentity.semanticSearchBackend
        {
            applicationTarget?.setSemanticSearchCapability(
                configuration.semanticSearch.capability,
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
        let semanticSearchFeature = RawCullSemanticSearchFeature(
            similarityModel: similarityModel,
        )
        let deepAIReviewFeature = integration.deepAIReviewFeature
        let viewModel = RawCullViewModel(
            similarityModel: similarityModel,
            semanticSearchFeature: semanticSearchFeature,
            deepAIReviewFeature: deepAIReviewFeature,
        )
        let intelligenceRuntime = RawCullIntelligenceRuntime(
            integration: integration,
            similarityModel: similarityModel,
            semanticSearchFeature: semanticSearchFeature,
            deepAIReviewFeature: deepAIReviewFeature,
            settingsModel: settingsModel,
            applicationTarget: viewModel,
        )
        semanticSearchFeature.bindApplicationTarget(viewModel)
        settingsModel.bindConfigurationConsumer(intelligenceRuntime)

        assert(viewModel.similarityModel === intelligenceRuntime.similarityModel)
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
