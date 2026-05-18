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

    func latest() -> [SavedFiles]? {
        snapshots.last
    }
}

private func makeCullingTestFile(_ name: String, scoreAperture: Double? = nil) -> FileItem {
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
        size: 1,
        dateModified: Date(timeIntervalSince1970: 0),
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
        model.mergeScoringResults(
            [CullingScoringResult(fileName: "one.ARW", score: 0.75, saliencySubject: "bird")],
            in: catalog,
        )
        _ = await recorder.waitForSnapshotCount(1)

        let record = model.savedFiles.first?.filerecords?.first
        #expect(record?.rating == 4)
        #expect(record?.sharpnessScore == 0.75)
        #expect(record?.saliencySubject == "bird")
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
        #expect(model.savedFiles.first?.filerecords == nil)
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
            star.name: 4,
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
            makeCullingTestFile("unrated.ARW"),
        ]
        viewModel.filteredFiles = files
        viewModel.ratingCache = [
            "two.ARW": 2,
            "four.ARW": 4,
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
    func `applySharpnessThreshold rejects files below normalized threshold`() {
        let viewModel = RawCullViewModel()
        let catalog = ARWSourceCatalog(name: "Catalog", url: URL(fileURLWithPath: "/tmp/catalog-\(UUID().uuidString)"))
        let sharp = makeCullingTestFile("sharp.ARW")
        let soft = makeCullingTestFile("soft.ARW")
        let unscored = makeCullingTestFile("unscored.ARW")
        viewModel.selectedSource = catalog
        viewModel.filteredFiles = [sharp, soft, unscored]
        viewModel.cullingModel = CullingModel(saveDelayNanoseconds: 0, saveHandler: { _ in })
        viewModel.sharpnessModel.scores = [
            sharp.id: 100,
            soft.id: 40,
        ]

        viewModel.applySharpnessThreshold(50)

        #expect(viewModel.getRating(for: sharp) == 0)
        #expect(viewModel.getRating(for: soft) == -1)
        #expect(viewModel.getRating(for: unscored) == 0)
        #expect(viewModel.ratingCache.keys.sorted() == ["sharp.ARW", "soft.ARW"])
    }
}
