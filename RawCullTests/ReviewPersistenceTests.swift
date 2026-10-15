import Foundation
@testable import RawCull
import Testing

@MainActor
struct ReviewPersistenceTests {
    @Test
    func `rating a scored record sets its date and later scoring preserves it`() throws {
        let store = CullingModel(saveHandler: { _ in })
        let catalog = URL(filePath: "/test/catalog")
        let score = CullingScoringResult(fileName: "photo.ARW", score: 0.7, saliencySubject: "bird")
        store.mergeScoringResults([score], in: catalog)
        #expect(store.savedFiles.first?.filerecords?.first?.dateTagged == nil)
        store.updateRating(fileName: "photo.ARW", rating: 3, in: catalog)
        let date = try #require(store.savedFiles.first?.filerecords?.first?.dateTagged)
        #expect(!date.isEmpty)
        store.mergeScoringResults([score], in: catalog)
        #expect(store.savedFiles.first?.filerecords?.first?.dateTagged == date)
        store.applyRatingStates(["photo.ARW": nil], in: catalog)
        #expect(store.savedFiles.first?.filerecords?.first?.dateTagged == nil)
    }

    @Test
    func `rerating an existing record replaces its tagging date`() {
        let catalog = URL(filePath: "/test/catalog")
        let saved = SavedFiles(catalog: catalog, dateStart: nil,
                               filerecord: FileRecord(fileName: "photo.ARW", dateTagged: "old", dateCopied: nil, rating: 2))
        let store = CullingModel(saveHandler: { _ in }, loadHandler: { .loaded([saved]) })
        #expect(store.loadSavedFiles())
        store.updateRating(fileName: "photo.ARW", rating: 5, in: catalog)
        #expect(store.savedFiles.first?.filerecords?.first?.dateTagged != "old")
        #expect(store.savedFiles.first?.filerecords?.first?.dateTagged != nil)
    }
}
