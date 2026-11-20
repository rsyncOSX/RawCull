import Foundation
@testable import RawCull
import RawCullCore
import Testing

@MainActor
struct SharpnessTargetPresentationTests {
    @Test(arguments: [RatingFilter.all, .keepers, .rejected, .stars(3)])
    func `count matches execution targets across filters and selections`(filter: RatingFilter) {
        let model = makeRawCullViewModel()
        let first = makeCullingTestFile("A.ARW")
        let second = makeCullingTestFile("B.ARW")
        let third = makeCullingTestFile("C.ARW")
        model.catalog.files = [third, second, first]
        model.catalog.filteredFiles = [third, first]
        model.ratings.ratingCache = [first.name: 3, second.name: 3, third.name: -1]
        model.ratings.ratingFilter = filter
        for selection in [Set<UUID>(), [first.id, second.id], [UUID()]] {
            model.selection.selectedFileIDs = selection
            #expect(model.catalogController.sharpnessScoringTargetCount == model.catalogController.sharpnessScoringTargetFiles.count)
            model.catalog.filteredFiles = []
            #expect(model.catalogController.sharpnessScoringTargetCount == model.catalogController.sharpnessScoringTargetFiles.count)
            model.catalog.filteredFiles = [third, first]
        }
    }

    @Test
    func `target descriptions and availability reflect empty and selected scope`() {
        let model = makeRawCullViewModel()
        #expect(model.catalogController.sharpnessScoringTargetCount == 0)
        #expect(model.catalogController.sharpnessScoringTargetDescription == "0 catalog files")
        let file = makeCullingTestFile("A.ARW")
        model.catalog.files = [file]
        model.catalog.filteredFiles = [file]
        #expect(model.catalogController.sharpnessScoringTargetDescription == "1 catalog file")
        model.selection.selectedFileIDs = [file.id]
        #expect(model.catalogController.sharpnessScoringTargetDescription == "1 selected file")
        model.selection.selectedFileIDs = []
        model.ratings.ratingFilter = .stars(3)
        #expect(model.catalogController.sharpnessScoringTargetDescription == "0 3-star files")
        model.ratings.ratingCache[file.name] = 3
        #expect(model.catalogController.sharpnessScoringTargetDescription == "1 3-star file")
    }
}
