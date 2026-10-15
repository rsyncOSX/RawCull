import Foundation
import Observation
@testable import RawCull
import Testing

@MainActor
struct SavedFilesPresentationTests {
    @Test
    func `Legacy missing fields have display fallbacks without inventing ratings`() async throws {
        let record = FileRecord(fileName: nil, dateTagged: nil, dateCopied: nil, rating: nil)
        var catalog = SavedFiles(catalog: URL(filePath: "/tmp/legacy"), dateStart: "", filerecord: record)
        catalog.catalog = nil
        let store = await makeStore([catalog])
        let presentation = SavedFilesPresentation(cullingModel: store)
        let summary = try #require(presentation.catalogs.first)
        #expect(summary.id == catalog.id)
        #expect(summary.name == "Unknown Catalog")
        #expect(summary.dateStarted == nil)
        #expect(summary.fileCount == 1)
        #expect(presentation.recordsTitle(in: catalog.id) == "Files")
        let row = try #require(presentation.records(in: catalog.id).first)
        #expect(row.id == record.id)
        #expect(row.name == "Unnamed File")
        #expect(row.dateTagged == nil)
        #expect(row.rating == nil)
        let detail = try #require(presentation.detail(in: catalog.id, recordID: record.id))
        #expect(detail.name == row.name)
        #expect(detail.dateTagged == "—")
        #expect(detail.dateCopied == "—")
        #expect(detail.rating == nil)
        #expect(detail.sharpness == nil)
        #expect(detail.subject == nil)
    }

    @Test
    func `Stored dates and rejected ratings survive presentation while sharpness is formatted`() async throws {
        var record = FileRecord(fileName: "photo.arw", dateTagged: "16 Feb 2026 11:14", dateCopied: "17 Feb 2026 09:12", rating: -1)
        record.sharpnessScore = 12.345
        record.saliencySubject = "Bird"
        let catalog = SavedFiles(catalog: URL(filePath: "/tmp/birds"), dateStart: "16 Feb 2026 10:59", filerecord: record)
        let presentation = SavedFilesPresentation(cullingModel: await makeStore([catalog]))
        let summary = try #require(presentation.catalogs.first)
        #expect(summary.name == "birds")
        #expect(summary.dateStarted == catalog.dateStart)
        #expect(presentation.recordsTitle(in: catalog.id) == "birds")
        let detail = try #require(presentation.detail(in: catalog.id, recordID: record.id))
        #expect(detail.name == "photo.arw")
        #expect(detail.dateTagged == record.dateTagged)
        #expect(detail.dateCopied == record.dateCopied)
        #expect(detail.rating == -1)
        #expect(detail.sharpness == "12.35")
        #expect(detail.subject == "Bird")
    }

    @Test
    func `Source mutations invalidate presentation reads and preserve selection identity`() async {
        let record = FileRecord(fileName: "photo.arw", dateTagged: nil, dateCopied: nil, rating: 1)
        let catalog = SavedFiles(catalog: URL(filePath: "/tmp/live"), dateStart: nil, filerecord: record)
        let store = await makeStore([catalog])
        let presentation = SavedFilesPresentation(cullingModel: store)
        await confirmation("Saved data invalidates the screen") { changed in
            withObservationTracking {
                _ = presentation.catalogs
                _ = presentation.records(in: catalog.id)
            } onChange: {
                changed()
            }
            store.updateRating(fileName: "photo.arw", rating: 4, in: URL(filePath: "/tmp/live"))
        }
        #expect(presentation.catalogs.first?.id == catalog.id)
        #expect(presentation.records(in: catalog.id).first?.id == record.id)
        #expect(presentation.records(in: catalog.id).first?.rating == 4)
        #expect(presentation.detail(in: catalog.id, recordID: record.id)?.rating == 4)
        store.resetAllSavedFiles()
        #expect(presentation.catalogs.isEmpty)
        #expect(presentation.records(in: catalog.id).isEmpty)
        #expect(presentation.detail(in: catalog.id, recordID: record.id) == nil)
        #expect(await store.flushPersistence())
    }

    @Test
    func `Absent selections and missing record arrays have no rows or detail`() async {
        let record = FileRecord(fileName: "photo.arw", dateTagged: nil, dateCopied: nil, rating: 1)
        var catalog = SavedFiles(catalog: URL(filePath: "/tmp/empty"), dateStart: nil, filerecord: record)
        catalog.filerecords = nil
        let presentation = SavedFilesPresentation(cullingModel: await makeStore([catalog]))
        #expect(presentation.catalogs.first?.fileCount == 0)
        #expect(presentation.records(in: catalog.id).isEmpty)
        #expect(presentation.records(in: nil).isEmpty)
        #expect(presentation.records(in: UUID()).isEmpty)
        #expect(presentation.detail(in: catalog.id, recordID: record.id) == nil)
        #expect(presentation.detail(in: nil, recordID: nil) == nil)
    }

    private func makeStore(_ savedFiles: [SavedFiles]) async -> CullingModel {
        let model = CullingModel(saveHandler: { _ in }, loadHandler: { .loaded(savedFiles) })
        #expect(await model.loadSavedFiles())
        return model
    }
}
