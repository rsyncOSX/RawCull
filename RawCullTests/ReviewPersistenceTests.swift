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
    func `rerating an existing record replaces its tagging date`() async {
        let catalog = URL(filePath: "/test/catalog")
        let saved = SavedFiles(catalog: catalog, dateStart: nil,
                               filerecord: FileRecord(fileName: "photo.ARW", dateTagged: "old", dateCopied: nil, rating: 2))
        let store = CullingModel(saveHandler: { _ in }, loadHandler: { .loaded([saved]) })
        #expect(await store.loadSavedFiles())
        store.updateRating(fileName: "photo.ARW", rating: 5, in: catalog)
        #expect(store.savedFiles.first?.filerecords?.first?.dateTagged != "old")
        #expect(store.savedFiles.first?.filerecords?.first?.dateTagged != nil)
    }
}

@MainActor
struct CullingInitializationTests {
    @Test
    func `unread store rejects edits and a flush loads rather than overwrites history`() async {
        var reads = 0
        let catalog = URL(filePath: "/test/previous-catalog")
        let existing = SavedFiles(catalog: catalog, dateStart: nil,
                                  filerecord: FileRecord(fileName: "saved.ARW", dateTagged: nil, dateCopied: nil, rating: 5))
        let store = CullingModel(saveHandler: { _ in Issue.record("Unread history must not be overwritten") }, loadHandler: {
            reads += 1
            return .loaded([existing])
        })
        #expect(store.loadState == .unloaded)
        store.updateRating(fileName: "new.ARW", rating: 2, in: catalog)
        store.resetAllSavedFiles()
        #expect(store.savedFiles.isEmpty)
        #expect(!store.hasUnsavedChanges)
        #expect(await store.flushPersistence())
        #expect(reads == 1)
        #expect(store.rating(for: "saved.ARW", in: catalog) == 5)
        #expect(await store.ensureLoaded())
        #expect(reads == 1)
    }

    @Test
    func `concurrent initialization shares one read and blocks edits while loading`() async {
        var reads = 0
        var finish: CheckedContinuation<SavedFilesReadResult, Never>?
        let (started, signal) = AsyncStream<Void>.makeStream()
        let store = CullingModel(saveHandler: { _ in }, loadHandler: {
            reads += 1
            signal.yield(())
            return await withCheckedContinuation { finish = $0 }
        })
        let first = Task { await store.ensureLoaded() }
        for await _ in started { break }
        signal.finish()
        #expect(store.loadState == .loading)
        store.updateRating(fileName: "photo.ARW", rating: 3, in: URL(filePath: "/test/catalog"))
        #expect(!store.hasUnsavedChanges)
        let second = Task { await store.ensureLoaded() }
        finish?.resume(returning: .loaded([]))
        #expect(await first.value)
        #expect(await second.value)
        #expect(reads == 1)
        #expect(store.loadState == .ready)
    }

    @Test
    func `corrupt initialization preserves the file and remains blocked until explicit retry`() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let url = root.appendingPathComponent("savedfiles.json")
        let damaged = Data("damaged JSON".utf8)
        try damaged.write(to: url)
        let store = CullingModel(saveHandler: { _ in Issue.record("Damaged store must be preserved") }, loadHandler: {
            await ReadSavedFilesJSON(savedFilesURL: url).readInBackground()
        })
        #expect(await !store.ensureLoaded())
        #expect(store.loadState == .failed)
        store.resetAllSavedFiles()
        #expect(await !store.flushPersistence())
        #expect((try? Data(contentsOf: url)) == damaged)
        try Data("[]".utf8).write(to: url)
        #expect(await !store.ensureLoaded())
        #expect(await store.retryPersistence())
        #expect(store.loadState == .ready)
    }
}
