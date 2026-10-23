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
        model.files = [third, second, first]
        model.filteredFiles = [third, first]
        model.ratingCache = [first.name: 3, second.name: 3, third.name: -1]
        model.ratingFilter = filter
        for selection in [Set<UUID>(), [first.id, second.id], [UUID()]] {
            model.selectedFileIDs = selection
            #expect(model.sharpnessScoringTargetCount == model.sharpnessScoringTargetFiles.count)
            model.filteredFiles = []
            #expect(model.sharpnessScoringTargetCount == model.sharpnessScoringTargetFiles.count)
            model.filteredFiles = [third, first]
        }
    }

    @Test
    func `target descriptions and availability reflect empty and selected scope`() {
        let model = makeRawCullViewModel()
        #expect(model.sharpnessScoringTargetCount == 0)
        #expect(model.sharpnessScoringTargetDescription == "0 catalog files")
        let file = makeCullingTestFile("A.ARW")
        model.files = [file]
        model.filteredFiles = [file]
        #expect(model.sharpnessScoringTargetDescription == "1 catalog file")
        model.selectedFileIDs = [file.id]
        #expect(model.sharpnessScoringTargetDescription == "1 selected file")
        model.selectedFileIDs = []
        model.ratingFilter = .stars(3)
        #expect(model.sharpnessScoringTargetDescription == "0 3-star files")
        model.ratingCache[file.name] = 3
        #expect(model.sharpnessScoringTargetDescription == "1 3-star file")
    }
}
