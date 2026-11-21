import Foundation
import Observation
import RawCullCore

/// Rating actions: updating ratings (and advancing the selection), clearing
/// culling state, and recovering the culling store. Each one refreshes the
/// catalog projection through `CatalogController`.
@Observable @MainActor
final class CullingController: ImageReviewRatingActing, BurstWorkflowHost {
    @ObservationIgnored let catalogController: CatalogController
    @ObservationIgnored let catalog: CatalogWorkspace
    @ObservationIgnored let selection: SelectionModel
    @ObservationIgnored let ratings: RatingsModel
    @ObservationIgnored let burstWorkflow: BurstWorkflowController
    @ObservationIgnored let sharpnessModel: SharpnessScoringModel
    @ObservationIgnored let similarityFeature: RawCullSimilarityFeature

    init(catalogController: CatalogController) {
        self.catalogController = catalogController
        catalog = catalogController.catalog
        selection = catalogController.selection
        ratings = catalogController.ratings
        burstWorkflow = catalogController.burstWorkflow
        sharpnessModel = catalogController.sharpnessModel
        similarityFeature = catalogController.similarityFeature
    }

    // MARK: BurstWorkflowHost

    var activeCatalogFiles: [FileItem] {
        catalogController.activeCatalogFiles
    }

    var hasActiveSemanticSearchSelection: Bool {
        catalogController.hasActiveSemanticSearchSelection
    }

    func hasRating(in files: [FileItem]) -> Bool {
        catalogController.hasRating(in: files)
    }

    func handleSortOrderChange() async {
        await catalogController.handleSortOrderChange()
    }

    func applyBurstSharpnessScoringSideEffects(_ files: [FileItem]) async {
        await catalogController.applyBurstSharpnessScoringSideEffects(files)
    }
}
