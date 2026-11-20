import Foundation
@testable import RawCull
import RawCullCore
import Testing

@MainActor
struct CullingGridProjectionTests {
    private func file(_ name: String) -> FileItem {
        FileItem(url: URL(filePath: "/test/\(name)"), name: name, size: 1,
                 dateModified: Date(timeIntervalSince1970: 1), exifData: nil, afFocusNormalized: nil)
    }

    @Test
    func `rating changes rebuild the grid and zoom projections exactly once`() {
        let model = makeRawCullViewModel()
        let first = file("first.ARW"), second = file("second.ARW")
        model.catalog.selectedSource = ARWSourceCatalog(name: "Catalog", url: URL(filePath: "/test"))
        model.catalog.filteredFiles = [first, second]
        _ = model.catalogController.cullingGridProjection(ratingFilter: .rating(3))
        _ = model.catalogController.zoomNavigationProjection()
        let gridBuilds = model.catalogController.gridProjectionBuildCount
        let zoomBuilds = model.catalogController.zoomNavigationBuildCount
        let revision = model.ratings.revision

        model.ratings.ratingCache[first.name] = 3

        #expect(model.ratings.revision == revision + 1)
        #expect(model.catalogController.cullingGridProjection(ratingFilter: .rating(3)).fileIDs == [first.id])
        #expect(model.catalogController.gridProjectionBuildCount == gridBuilds + 1)
        _ = model.catalogController.cullingGridProjection(ratingFilter: .rating(3))
        #expect(model.catalogController.gridProjectionBuildCount == gridBuilds + 1)
        _ = model.catalogController.zoomNavigationProjection()
        #expect(model.catalogController.zoomNavigationBuildCount == zoomBuilds + 1)
    }

    @Test
    func `selection and score-value changes reuse the projection while membership changes rebuild`() {
        let model = makeRawCullViewModel()
        let first = file("first.ARW"), second = file("second.ARW"), replacement = file("replacement.ARW")
        model.catalog.filteredFiles = [first, second]
        _ = model.catalogController.cullingGridProjection(ratingFilter: .all)
        let initial = model.catalogController.gridProjectionBuildCount
        model.selection.selectedFileID = first.id
        model.selection.selectedFileIDs = [first.id]
        #expect(model.catalogController.cullingGridProjection(ratingFilter: .all).fileIDs == [first.id, second.id])
        #expect(model.catalogController.gridProjectionBuildCount == initial)
        model.sharpnessModel.scores = [first.id: 0.5]
        _ = model.catalogController.cullingGridProjection(ratingFilter: .all)
        let scored = model.catalogController.gridProjectionBuildCount
        model.sharpnessModel.scores[first.id] = 0.9
        _ = model.catalogController.cullingGridProjection(ratingFilter: .all)
        #expect(model.catalogController.gridProjectionBuildCount == scored)
        model.catalog.filteredFiles = [first, replacement]
        #expect(model.catalogController.cullingGridProjection(ratingFilter: .all).fileIDs == [first.id, replacement.id])
        #expect(model.catalogController.gridProjectionBuildCount == scored + 1)
    }

    @Test
    func `rating review-group and saliency mutations invalidate cached projections`() {
        let model = makeRawCullViewModel()
        let first = file("first.ARW"), second = file("second.ARW")
        model.catalog.selectedSource = ARWSourceCatalog(name: "Catalog", url: URL(filePath: "/test"))
        model.catalog.filteredFiles = [first, second]
        #expect(model.catalogController.cullingGridProjection(ratingFilter: .unrated).files.count == 2)
        model.ratings.ratingCache[first.name] = 0
        #expect(model.catalogController.cullingGridProjection(ratingFilter: .unrated).fileIDs == [second.id])
        model.navigation.mainViewMode = .similarityGrid
        model.similarityModel.burstModeActive = true
        model.similarityModel.burstGroups = [BurstGroup(id: 1, fileIDs: [first.id, second.id])]
        #expect(model.catalogController.cullingGridProjection(ratingFilter: .all).selectionIDs == [first.id, second.id])
        model.similarityModel.burstGroups = [BurstGroup(id: 1, fileIDs: [second.id, first.id])]
        #expect(model.catalogController.cullingGridProjection(ratingFilter: .all).selectionIDs == [second.id, first.id])
        let count = model.catalogController.gridProjectionBuildCount
        model.sharpnessModel.saliencyInfo[first.id] = SaliencyInfo(subjectLabel: "bird")
        _ = model.catalogController.cullingGridProjection(ratingFilter: .all)
        #expect(model.catalogController.gridProjectionBuildCount == count + 1)
        model.burstWorkflow.burstReviewQueueFilter = .singleImages
        #expect(model.catalogController.cullingGridProjection(ratingFilter: .all).groups.isEmpty)
    }
}
