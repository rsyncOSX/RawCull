import Foundation
@testable import RawCull
import RawCullCore
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

@MainActor
private final class RecoveryFixtureState {
    var isRepaired = false
}

@MainActor
struct CullingRecoveryPresentationTests {
    private func file(_ name: String) -> FileItem {
        FileItem(url: URL(filePath: "/test/catalog/\(name)"), name: name, size: 12,
                 dateModified: Date(timeIntervalSince1970: 1), exifData: nil, afFocusNormalized: nil)
    }

    @Test
    func `repaired history refreshes ratings filters selection and copy admission`() async {
        let model = makeRawCullViewModel()
        let photo = file("saved.ARW")
        let hidden = file("hidden.ARW")
        let catalog = ARWSourceCatalog(name: "Catalog", url: URL(filePath: "/test/catalog"))
        model.selectedSource = catalog
        model.files = [hidden, photo]
        model.filteredFiles = [hidden, photo]
        model.ratingFilter = .stars(5)
        model.selectedFileID = hidden.id
        model.selectedFileIDs = [hidden.id, photo.id]
        let state = RecoveryFixtureState()
        let history = SavedFiles(catalog: catalog.url, dateStart: nil,
                                 filerecord: FileRecord(fileName: photo.name, dateTagged: "saved", dateCopied: nil, rating: 5))
        model.cullingModel = CullingModel(saveHandler: { _ in }, loadHandler: {
            state.isRepaired ? .loaded([history]) : .failed(.init(url: URL(filePath: "/test/store"), message: "damaged"))
        })
        #expect(await !model.cullingModel.ensureLoaded())
        #expect(await !model.retryCullingPersistence())
        #expect(model.filteredFiles.count == 2)
        state.isRepaired = true
        #expect(await model.retryCullingPersistence())
        #expect(model.ratingCache == [photo.name: 5])
        #expect(model.taggedNamesCache == [photo.name])
        #expect(model.filteredFiles.map(\.id) == [photo.id])
        #expect(model.selectedFileID == photo.id)
        #expect(model.selectedFileIDs == [photo.id])
        #expect(model.extractTaggedfilenames() == [photo.name])
    }

    @Test
    func `archiving damaged history clears stale presentation even if saving the reset fails`() async throws {
        enum SaveFailure: Error { case blocked }
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let url = root.appendingPathComponent("savedfiles.json")
        try Data("damaged".utf8).write(to: url)
        let model = makeRawCullViewModel()
        let photo = file("saved.ARW")
        model.selectedSource = ARWSourceCatalog(name: "Catalog", url: URL(filePath: "/test/catalog"))
        model.files = [photo]
        model.filteredFiles = [photo]
        model.ratingFilter = .stars(5)
        model.ratingCache = [photo.name: 5]
        model.taggedNamesCache = [photo.name]
        model.sharpnessModel.scores = [photo.id: 0.5]
        model.selectedFileID = photo.id
        model.cullingModel = CullingModel(saveHandler: { _ in throw SaveFailure.blocked }, loadHandler: {
            .failed(.init(url: url, message: "damaged"))
        })
        #expect(await !model.cullingModel.ensureLoaded())
        #expect(await !model.archiveCullingStoreAndReset())
        #expect(model.ratingCache.isEmpty)
        #expect(model.taggedNamesCache.isEmpty)
        #expect(model.sharpnessModel.scores.isEmpty)
        #expect(model.filteredFiles.isEmpty)
        #expect(model.selectedFileID == nil)
        #expect(model.cullingModel.persistenceError != nil)
        #expect(!FileManager.default.fileExists(atPath: url.path))
    }

    @Test
    func `restoration publishes scores once and preserves first duplicate and metadata validation`() async {
        let model = makeRawCullViewModel()
        let photos = (0..<100).map { file("photo\($0).ARW") }
        let catalog = ARWSourceCatalog(name: "Catalog", url: URL(filePath: "/test/catalog"))
        model.selectedSource = catalog
        model.files = photos
        let signature = model.sharpnessModel.scoringSignature
        var records = photos.map { photo in
            FileRecord(fileName: photo.name, sharpnessScore: 0.5,
                       sharpnessScoringSignature: signature, sharpnessFileSize: photo.size,
                       sharpnessModificationDate: photo.dateModified)
        }
        records[1].sharpnessFileSize = 999
        var duplicate = records[0]
        duplicate.sharpnessScore = 0.9
        records.append(duplicate)
        var saved = SavedFiles(catalog: catalog.url, dateStart: nil, filerecord: records[0])
        saved.filerecords = records
        model.cullingModel = CullingModel(saveHandler: { _ in }, loadHandler: { .loaded([saved]) })
        #expect(await model.cullingModel.ensureLoaded())
        let revision = model.sharpnessModel.scoreRevision
        model.loadPersistedScoringandSaliency()
        #expect(model.sharpnessModel.scoreRevision == revision + 1)
        #expect(model.sharpnessModel.scores.count == 99)
        #expect(model.sharpnessModel.scores[photos[0].id] == 0.5)
        #expect(model.sharpnessModel.scores[photos[1].id] == nil)
        #expect(model.sharpnessModel.maxScore == 0.5)
    }
}
