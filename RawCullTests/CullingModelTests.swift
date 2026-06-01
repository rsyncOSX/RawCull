import Foundation
@testable import RawCull
import Testing

private actor SavedFilesRecorder {
    private var snapshots: [[SavedFiles]] = []

    func record(_ savedFiles: [SavedFiles]) {
        snapshots.append(savedFiles)
    }

    func waitForSnapshotCount(_ count: Int) async -> [[SavedFiles]] {
        for _ in 0 ..< 200 {
            if snapshots.count >= count { return snapshots }
            try? await Task.sleep(nanoseconds: 1_000_000)
        }
        return snapshots
    }
}

private func makeCullingTestFile(
    _ name: String,
    scoreAperture: Double? = nil,
    size: Int64 = 1,
    dateModified: Date = Date(timeIntervalSince1970: 0),
) -> FileItem {
    let exif = scoreAperture.map {
        ExifMetadata(
            shutterSpeed: nil,
            focalLength: nil,
            aperture: "f/\($0)",
            apertureValue: $0,
            iso: nil,
            isoValue: nil,
            camera: nil,
            lensModel: nil,
            rawFileType: nil,
            rawSizeClass: nil,
            pixelWidth: nil,
            pixelHeight: nil,
        )
    }
    return FileItem(
        url: URL(fileURLWithPath: "/tmp/\(name)"),
        name: name,
        size: size,
        dateModified: dateModified,
        exifData: exif,
        afFocusNormalized: nil,
    )
}

@MainActor
struct CullingModelTests {
    @Test
    func `updateRating creates catalog record and debounced save snapshot`() async {
        let recorder = SavedFilesRecorder()
        let model = CullingModel(saveDelayNanoseconds: 0) { savedFiles in
            await recorder.record(savedFiles)
        }
        let catalog = URL(fileURLWithPath: "/tmp/catalog-\(UUID().uuidString)")

        model.updateRating(fileName: "one.ARW", rating: 3, in: catalog)
        let snapshots = await recorder.waitForSnapshotCount(1)

        #expect(model.countSelectedFiles(in: catalog) == 1)
        #expect(model.savedFiles.first?.catalog == catalog)
        #expect(model.savedFiles.first?.filerecords?.first?.fileName == "one.ARW")
        #expect(model.savedFiles.first?.filerecords?.first?.rating == 3)
        #expect(snapshots.last?.first?.filerecords?.first?.rating == 3)
    }

    @Test
    func `updateRatings and applyRatings upsert existing records`() async {
        let recorder = SavedFilesRecorder()
        let model = CullingModel(saveDelayNanoseconds: 0) { savedFiles in
            await recorder.record(savedFiles)
        }
        let catalog = URL(fileURLWithPath: "/tmp/catalog-\(UUID().uuidString)")

        model.updateRatings(fileNames: ["one.ARW", "two.ARW"], rating: 2, in: catalog)
        model.applyRatings(["two.ARW": -1, "three.ARW": 5], in: catalog)
        _ = await recorder.waitForSnapshotCount(1)

        let records = model.savedFiles.first?.filerecords ?? []
        let ratings = Dictionary(uniqueKeysWithValues: records.compactMap { record -> (String, Int)? in
            guard let fileName = record.fileName, let rating = record.rating else { return nil }
            return (fileName, rating)
        })

        #expect(ratings == ["one.ARW": 2, "two.ARW": -1, "three.ARW": 5])
    }

    @Test
    func `mergeScoringResults preserves ratings and writes scores`() async {
        let recorder = SavedFilesRecorder()
        let model = CullingModel(saveDelayNanoseconds: 0) { savedFiles in
            await recorder.record(savedFiles)
        }
        let catalog = URL(fileURLWithPath: "/tmp/catalog-\(UUID().uuidString)")

        model.updateRating(fileName: "one.ARW", rating: 4, in: catalog)
        let signature = SharpnessScoringSignature(
            photoType: .auto,
            scoringQuality: .fast,
            thumbnailMaxPixelSize: 512,
            config: FocusDetectorConfig(),
        )
        let modificationDate = Date(timeIntervalSince1970: 123)
        model.mergeScoringResults(
            [CullingScoringResult(
                fileName: "one.ARW",
                score: 0.75,
                saliencySubject: "bird",
                scoringSignature: signature,
                fileSize: 42,
                modificationDate: modificationDate,
            )],
            in: catalog,
        )
        _ = await recorder.waitForSnapshotCount(1)

        let record = model.savedFiles.first?.filerecords?.first
        #expect(record?.rating == 4)
        #expect(record?.sharpnessScore == 0.75)
        #expect(record?.saliencySubject == "bird")
        #expect(record?.sharpnessScoringSignature == signature)
        #expect(record?.sharpnessFileSize == 42)
        #expect(record?.sharpnessModificationDate == modificationDate)
    }

    @Test
    func `burst winner overrides upsert match and prune by catalog`() async {
        let recorder = SavedFilesRecorder()
        let model = CullingModel(saveDelayNanoseconds: 0) { savedFiles in
            await recorder.record(savedFiles)
        }
        let catalog = URL(fileURLWithPath: "/tmp/catalog-\(UUID().uuidString)")
        let files = [
            makeCullingTestFile("one.ARW"),
            makeCullingTestFile("two.ARW"),
            makeCullingTestFile("three.ARW")
        ]
        let first = BurstWinnerOverride(
            winnerFileName: "two.ARW",
            memberFileNames: files.map(\.name),
        )
        let replacement = BurstWinnerOverride(
            winnerFileName: "three.ARW",
            memberFileNames: files.map(\.name),
        )

        model.upsertBurstWinnerOverride(first, in: catalog)
        model.upsertBurstWinnerOverride(replacement, in: catalog)
        _ = await recorder.waitForSnapshotCount(1)

        #expect(model.burstWinnerOverrides(in: catalog).map(\.winnerFileName) == ["three.ARW"])
        #expect(model.overrideWinner(for: files, in: catalog)?.winnerFileName == "three.ARW")

        model.pruneStaleBurstOverrides(validFileNames: ["one.ARW", "two.ARW"], in: catalog)
        #expect(model.burstWinnerOverrides(in: catalog).isEmpty)
    }

    @Test
    func `resetSavedFiles clears records for catalog`() async {
        let recorder = SavedFilesRecorder()
        let model = CullingModel(saveDelayNanoseconds: 0) { savedFiles in
            await recorder.record(savedFiles)
        }
        let catalog = URL(fileURLWithPath: "/tmp/catalog-\(UUID().uuidString)")

        model.updateRatings(fileNames: ["one.ARW", "two.ARW"], rating: 2, in: catalog)
        model.resetSavedFiles(in: catalog)
        _ = await recorder.waitForSnapshotCount(1)

        #expect(model.countSelectedFiles(in: catalog) == 0)
        #expect(model.savedFiles.first?.filerecords == [])
    }

    @Test
    func `updateRating recreates records after reset leaves empty catalog`() async {
        let recorder = SavedFilesRecorder()
        let model = CullingModel(saveDelayNanoseconds: 0) { savedFiles in
            await recorder.record(savedFiles)
        }
        let catalog = URL(fileURLWithPath: "/tmp/catalog-\(UUID().uuidString)")

        model.updateRating(fileName: "one.ARW", rating: 3, in: catalog)
        model.resetSavedFiles(in: catalog)
        model.updateRating(fileName: "two.ARW", rating: 5, in: catalog)
        _ = await recorder.waitForSnapshotCount(1)

        let records = model.savedFiles.first?.filerecords ?? []
        #expect(records.count == 1)
        #expect(records.first?.fileName == "two.ARW")
        #expect(records.first?.rating == 5)
    }
}

@MainActor
struct SavedFilesJSONTests {
    @Test
    func `write creates Application Support directory and saved files JSON`() async throws {
        let fileURL = makeIsolatedSavedFilesURL()
        let root = savedFilesTestRoot(for: fileURL)
        defer { try? FileManager.default.removeItem(at: root) }
        let catalog = URL(fileURLWithPath: "/tmp/catalog-\(UUID().uuidString)")
        let savedFiles = [
            SavedFiles(
                catalog: catalog,
                dateStart: "19 May 2026 12:00",
                filerecord: FileRecord(fileName: "one.ARW", dateTagged: nil, dateCopied: nil, rating: 4),
            )
        ]

        await WriteSavedFilesJSON.write(savedFiles, to: fileURL)

        #expect(FileManager.default.fileExists(atPath: fileURL.path))
        let data = try Data(contentsOf: fileURL)
        let decoded = try JSONDecoder().decode([DecodeSavedFiles].self, from: data)
        #expect(decoded.first?.catalog == catalog)
        #expect(decoded.first?.filerecords?.first?.fileName == "one.ARW")
        #expect(decoded.first?.filerecords?.first?.rating == 4)
    }

    @Test
    func `older saved files JSON without burst overrides decodes`() throws {
        let json = """
        [{
          "catalog": "file:///tmp/catalog/",
          "dateStart": "19 May 2026 12:00",
          "filerecords": [{
            "fileName": "one.ARW",
            "rating": 3
          }]
        }]
        """
        let decoded = try JSONDecoder().decode([DecodeSavedFiles].self, from: Data(json.utf8))
        let saved = try #require(decoded.first.map(SavedFiles.init))

        #expect(saved.catalog == URL(string: "file:///tmp/catalog/"))
        #expect(saved.filerecords?.first?.fileName == "one.ARW")
        #expect(saved.burstWinnerOverrides == nil)
    }

    @Test
    func `saved files JSON round trips burst winner overrides`() throws {
        let override = BurstWinnerOverride(
            winnerFileName: "winner.ARW",
            memberFileNames: ["one.ARW", "winner.ARW"],
        )
        var saved = SavedFiles(
            catalog: URL(fileURLWithPath: "/tmp/catalog-\(UUID().uuidString)"),
            dateStart: "19 May 2026 12:00",
            filerecord: FileRecord(fileName: "winner.ARW", dateTagged: nil, dateCopied: nil, rating: 3),
        )
        saved.burstWinnerOverrides = [override]

        let data = try JSONEncoder().encode([saved])
        let decoded = try JSONDecoder().decode([DecodeSavedFiles].self, from: data)
        let restored = try #require(decoded.first.map(SavedFiles.init))

        #expect(restored.burstWinnerOverrides == [override])
    }

    @Test
    func `read loads saved files from Application Support URL`() throws {
        let fileURL = makeIsolatedSavedFilesURL()
        let root = savedFilesTestRoot(for: fileURL)
        defer { try? FileManager.default.removeItem(at: root) }
        let catalog = URL(fileURLWithPath: "/tmp/catalog-\(UUID().uuidString)")
        let savedFiles = [
            SavedFiles(
                catalog: catalog,
                dateStart: "19 May 2026 12:00",
                filerecord: FileRecord(fileName: "two.ARW", dateTagged: nil, dateCopied: nil, rating: 5),
            )
        ]
        try FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true,
        )
        let data = try JSONEncoder().encode(savedFiles)
        try data.write(to: fileURL)

        let decoded = try #require(ReadSavedFilesJSON(savedFilesURL: fileURL).readjsonfilesavedfiles())

        #expect(decoded.first?.catalog == catalog)
        #expect(decoded.first?.filerecords?.first?.fileName == "two.ARW")
        #expect(decoded.first?.filerecords?.first?.rating == 5)
    }

    @Test
    func `read ignores old Documents file when Application Support file exists`() throws {
        let newFileURL = makeIsolatedSavedFilesURL()
        let root = savedFilesTestRoot(for: newFileURL)
        defer { try? FileManager.default.removeItem(at: root) }
        let oldFileURL = root
            .appendingPathComponent("Documents", isDirectory: true)
            .appendingPathComponent("savedfiles.json")
        let newCatalog = URL(fileURLWithPath: "/tmp/new-catalog-\(UUID().uuidString)")
        let oldCatalog = URL(fileURLWithPath: "/tmp/old-catalog-\(UUID().uuidString)")
        let newSavedFiles = [
            SavedFiles(
                catalog: newCatalog,
                dateStart: "19 May 2026 12:00",
                filerecord: FileRecord(fileName: "new.ARW", dateTagged: nil, dateCopied: nil, rating: 5),
            )
        ]
        let oldSavedFiles = [
            SavedFiles(
                catalog: oldCatalog,
                dateStart: "18 May 2026 12:00",
                filerecord: FileRecord(fileName: "old.ARW", dateTagged: nil, dateCopied: nil, rating: 1),
            )
        ]
        try FileManager.default.createDirectory(
            at: newFileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true,
        )
        try FileManager.default.createDirectory(
            at: oldFileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true,
        )
        try JSONEncoder().encode(newSavedFiles).write(to: newFileURL)
        try JSONEncoder().encode(oldSavedFiles).write(to: oldFileURL)

        let decoded = try #require(ReadSavedFilesJSON(savedFilesURL: newFileURL).readjsonfilesavedfiles())

        #expect(decoded.first?.catalog == newCatalog)
        #expect(decoded.first?.filerecords?.first?.fileName == "new.ARW")
        #expect(decoded.first?.filerecords?.first?.rating == 5)
    }

    private func savedFilesTestRoot(for fileURL: URL) -> URL {
        fileURL
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }
}

@MainActor
struct RawCullViewModelCullingTests {
    @Test
    func `rebuildRatingCache populates ratings and tagged filenames for selected catalog`() {
        let viewModel = RawCullViewModel()
        let catalog = ARWSourceCatalog(name: "Catalog", url: URL(fileURLWithPath: "/tmp/catalog-\(UUID().uuidString)"))
        viewModel.selectedSource = catalog
        viewModel.cullingModel = CullingModel(saveDelayNanoseconds: 0, saveHandler: { _ in })
        viewModel.cullingModel.updateRatings(fileNames: ["one.ARW", "two.ARW"], rating: 2, in: catalog.url)

        viewModel.rebuildRatingCache()

        #expect(viewModel.ratingCache == ["one.ARW": 2, "two.ARW": 2])
        #expect(viewModel.taggedNamesCache == ["one.ARW", "two.ARW"])
    }

    @Test
    func `passesRatingFilter distinguishes rejected keepers and star ratings`() {
        let viewModel = RawCullViewModel()
        let rejected = makeCullingTestFile("rejected.ARW")
        let keeper = makeCullingTestFile("keeper.ARW")
        let star = makeCullingTestFile("star.ARW")
        viewModel.ratingCache = [
            rejected.name: -1,
            star.name: 4
        ]

        viewModel.ratingFilter = .rejected
        #expect(viewModel.passesRatingFilter(rejected))
        #expect(!viewModel.passesRatingFilter(keeper))

        viewModel.ratingFilter = .keepers
        #expect(viewModel.passesRatingFilter(keeper))
        #expect(!viewModel.passesRatingFilter(star))

        viewModel.ratingFilter = .stars(4)
        #expect(viewModel.passesRatingFilter(star))
        #expect(!viewModel.passesRatingFilter(rejected))
    }

    @Test
    func `extractRatedfilenames returns files at or above requested rating`() {
        let viewModel = RawCullViewModel()
        let files = [
            makeCullingTestFile("two.ARW"),
            makeCullingTestFile("four.ARW"),
            makeCullingTestFile("unrated.ARW")
        ]
        viewModel.filteredFiles = files
        viewModel.ratingCache = [
            "two.ARW": 2,
            "four.ARW": 4
        ]

        #expect(viewModel.extractRatedfilenames(3) == ["four.ARW"])
    }

    @Test
    func `bulk updateRating updates culling model and cache`() {
        let viewModel = RawCullViewModel()
        let catalog = ARWSourceCatalog(name: "Catalog", url: URL(fileURLWithPath: "/tmp/catalog-\(UUID().uuidString)"))
        let files = [makeCullingTestFile("one.ARW"), makeCullingTestFile("two.ARW")]
        viewModel.selectedSource = catalog
        viewModel.cullingModel = CullingModel(saveDelayNanoseconds: 0, saveHandler: { _ in })

        viewModel.updateRating(for: files, rating: 5)

        #expect(viewModel.ratingCache == ["one.ARW": 5, "two.ARW": 5])
    }


    @Test
    func `persisted sharpness reload requires signature and source metadata`() {
        let viewModel = RawCullViewModel()
        let catalog = ARWSourceCatalog(name: "Catalog", url: URL(fileURLWithPath: "/tmp/catalog-\(UUID().uuidString)"))
        let original = makeCullingTestFile("one.ARW")
        viewModel.selectedSource = catalog
        viewModel.files = [original]
        viewModel.cullingModel = CullingModel(saveDelayNanoseconds: 0, saveHandler: { _ in })
        viewModel.cullingModel.mergeScoringResults(
            [CullingScoringResult(
                fileName: original.name,
                score: 0.75,
                saliencySubject: "bird",
                scoringSignature: viewModel.sharpnessModel.scoringSignature,
                fileSize: original.size,
                modificationDate: original.dateModified,
            )],
            in: catalog.url,
        )

        viewModel.loadPersistedScoringandSaliency()
        #expect(viewModel.sharpnessModel.scores[original.id] == 0.75)

        viewModel.sharpnessModel.scores = [:]
        viewModel.files = [makeCullingTestFile("one.ARW", size: 2)]
        viewModel.loadPersistedScoringandSaliency()
        #expect(viewModel.sharpnessModel.scores.isEmpty)

        viewModel.files = [original]
        viewModel.sharpnessModel.focusMaskModel.config.silhouettePenaltyStrength = 0.1
        viewModel.loadPersistedScoringandSaliency()
        #expect(viewModel.sharpnessModel.scores.isEmpty)
    }

    @Test
    func `legacy unsigned sharpness scores remain readable but reload as stale`() {
        let viewModel = RawCullViewModel()
        let catalog = ARWSourceCatalog(name: "Catalog", url: URL(fileURLWithPath: "/tmp/catalog-\(UUID().uuidString)"))
        let file = makeCullingTestFile("legacy.ARW")
        viewModel.selectedSource = catalog
        viewModel.files = [file]
        viewModel.cullingModel = CullingModel(saveDelayNanoseconds: 0, saveHandler: { _ in })
        viewModel.cullingModel.mergeScoringResults(
            [CullingScoringResult(fileName: file.name, score: 0.5, saliencySubject: "bird")],
            in: catalog.url,
        )

        viewModel.loadPersistedScoringandSaliency()

        #expect(viewModel.sharpnessModel.scores.isEmpty)
        #expect(viewModel.cullingModel.savedFiles.first?.filerecords?.first?.sharpnessScore == 0.5)
    }

    @Test
    func `clearCurrentCatalogCullingState allows rating same catalog again`() {
        let viewModel = RawCullViewModel()
        let catalog = ARWSourceCatalog(name: "Catalog", url: URL(fileURLWithPath: "/tmp/catalog-\(UUID().uuidString)"))
        let first = makeCullingTestFile("one.ARW")
        let second = makeCullingTestFile("two.ARW")
        viewModel.selectedSource = catalog
        viewModel.cullingModel = CullingModel(saveDelayNanoseconds: 0, saveHandler: { _ in })

        viewModel.updateRating(for: first, rating: 3)
        viewModel.clearCurrentCatalogCullingState()
        viewModel.updateRating(for: second, rating: 5)

        let records = viewModel.cullingModel.savedFiles.first?.filerecords ?? []
        #expect(records.count == 1)
        #expect(records.first?.fileName == "two.ARW")
        #expect(records.first?.rating == 5)
        #expect(viewModel.ratingCache == ["two.ARW": 5])
        #expect(viewModel.taggedNamesCache == ["two.ARW"])
    }
}
