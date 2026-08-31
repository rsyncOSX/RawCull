import Foundation

/// Stable application-owned lifetime for the single Vision similarity feature.
@MainActor
final class RawCullIntelligenceRuntime {
    let similarityFeature: RawCullSimilarityFeature

    init(similarityFeature: RawCullSimilarityFeature) {
        self.similarityFeature = similarityFeature
    }
}

@MainActor
struct RawCullApplicationState {
    let intelligenceRuntime: RawCullIntelligenceRuntime
    let viewModel: RawCullViewModel

    static func live() -> RawCullApplicationState {
        make()
    }

    static func make(
        similarityService: any RawCullSimilarityServicing = RawCullVisionSimilarityService(),
        similarityArtifactStore: any SimilarityArtifactStoring = PerFileAnalysisArtifactStore.shared,
        burstAnalysisCacheRepository: any BurstAnalysisCacheRepository
            = LiveBurstAnalysisCacheRepository(),
    ) -> RawCullApplicationState {
        let similarityModel = SimilarityScoringModel(
            similarityService: similarityService,
            artifactStore: similarityArtifactStore,
        )
        let similarityFeature = RawCullSimilarityFeature(similarityModel: similarityModel)
        let viewModel = RawCullViewModel(
            similarityModel: similarityModel,
            similarityFeature: similarityFeature,
            burstAnalysisCacheRepository: burstAnalysisCacheRepository,
        )
        let runtime = RawCullIntelligenceRuntime(similarityFeature: similarityFeature)

        assert(viewModel.similarityFeature === runtime.similarityFeature)
        return RawCullApplicationState(
            intelligenceRuntime: runtime,
            viewModel: viewModel,
        )
    }
}
