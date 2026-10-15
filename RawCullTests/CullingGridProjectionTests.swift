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
    func `selection and score-value changes reuse the projection while membership changes rebuild`() {
        let model = makeRawCullViewModel()
        let first = file("first.ARW"), second = file("second.ARW"), replacement = file("replacement.ARW")
        model.filteredFiles = [first, second]
        _ = model.cullingGridProjection(ratingFilter: .all)
        let initial = model.gridProjectionBuildCount
        model.selectedFileID = first.id
        model.selectedFileIDs = [first.id]
        #expect(model.cullingGridProjection(ratingFilter: .all).fileIDs == [first.id, second.id])
        #expect(model.gridProjectionBuildCount == initial)
        model.sharpnessModel.scores = [first.id: 0.5]
        _ = model.cullingGridProjection(ratingFilter: .all)
        let scored = model.gridProjectionBuildCount
        model.sharpnessModel.scores[first.id] = 0.9
        _ = model.cullingGridProjection(ratingFilter: .all)
        #expect(model.gridProjectionBuildCount == scored)
        model.filteredFiles = [first, replacement]
        #expect(model.cullingGridProjection(ratingFilter: .all).fileIDs == [first.id, replacement.id])
        #expect(model.gridProjectionBuildCount == scored + 1)
    }

    @Test
    func `rating review-group and saliency mutations invalidate cached projections`() {
        let model = makeRawCullViewModel()
        let first = file("first.ARW"), second = file("second.ARW")
        model.selectedSource = ARWSourceCatalog(name: "Catalog", url: URL(filePath: "/test"))
        model.filteredFiles = [first, second]
        #expect(model.cullingGridProjection(ratingFilter: .unrated).files.count == 2)
        model.ratingCache[first.name] = 0
        #expect(model.cullingGridProjection(ratingFilter: .unrated).fileIDs == [second.id])
        model.mainViewMode = .similarityGrid
        model.similarityModel.burstModeActive = true
        model.similarityModel.burstGroups = [BurstGroup(id: 1, fileIDs: [first.id, second.id])]
        #expect(model.cullingGridProjection(ratingFilter: .all).selectionIDs == [first.id, second.id])
        model.similarityModel.burstGroups = [BurstGroup(id: 1, fileIDs: [second.id, first.id])]
        #expect(model.cullingGridProjection(ratingFilter: .all).selectionIDs == [second.id, first.id])
        let count = model.gridProjectionBuildCount
        model.sharpnessModel.saliencyInfo[first.id] = SaliencyInfo(subjectLabel: "bird")
        _ = model.cullingGridProjection(ratingFilter: .all)
        #expect(model.gridProjectionBuildCount == count + 1)
        model.burstReviewQueueFilter = .singleImages
        #expect(model.cullingGridProjection(ratingFilter: .all).groups.isEmpty)
    }
}
