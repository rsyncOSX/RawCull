import Foundation

/// Stable application-owned lifetime for RawCull's intelligence models.
///
/// Phase 2 deliberately keeps configuration callbacks and worker-task ownership
/// in their existing types. The runtime only guarantees that every caller shares
/// the same model instances.
@MainActor
final class RawCullIntelligenceRuntime {
    let integration: RawCullAIIntegration
    let similarityModel: SimilarityScoringModel
    let deepAIReviewFeature: DeepAIReviewFeature
    let settingsModel: RawCullAISettingsModel

    init(
        integration: RawCullAIIntegration,
        similarityModel: SimilarityScoringModel,
        deepAIReviewFeature: DeepAIReviewFeature,
        settingsModel: RawCullAISettingsModel,
    ) {
        self.integration = integration
        self.similarityModel = similarityModel
        self.deepAIReviewFeature = deepAIReviewFeature
        self.settingsModel = settingsModel
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
        let similarityModel = SimilarityScoringModel(
            similarityService: integration.visionSimilarityService,
            semanticSearchCapability: integration.capabilities()
                .semanticSearchStatus(for: .defaultSelection),
            artifactStore: similarityArtifactStore,
        )
        let deepAIReviewFeature = integration.deepAIReviewFeature
        let viewModel = RawCullViewModel(
            similarityModel: similarityModel,
            deepAIReviewFeature: deepAIReviewFeature,
        )
        let settingsModel = RawCullAISettingsModel(
            integration: integration,
            evidenceScan: evidenceScan,
            userDefaults: userDefaults,
            similarityServiceDidChange: { [weak viewModel] service in
                viewModel?.setSimilarityService(service)
            },
            semanticSearchCapabilityDidChange: {
                [weak viewModel] capability, service in
                viewModel?.setSemanticSearchCapability(
                    capability,
                    service: service,
                )
            },
            modelDownloadCatalog: modelDownloadCatalog,
            modelDownloadCoordinator: modelDownloadCoordinator,
            rawCullVersion: rawCullVersion,
        )
        let intelligenceRuntime = RawCullIntelligenceRuntime(
            integration: integration,
            similarityModel: similarityModel,
            deepAIReviewFeature: deepAIReviewFeature,
            settingsModel: settingsModel,
        )

        assert(viewModel.similarityModel === intelligenceRuntime.similarityModel)
        assert(viewModel.deepAIReviewFeature === intelligenceRuntime.deepAIReviewFeature)

        return RawCullApplicationState(
            intelligenceRuntime: intelligenceRuntime,
            viewModel: viewModel,
        )
    }
}
