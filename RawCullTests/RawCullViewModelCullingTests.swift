import CoreGraphics
import Foundation
import PhotoAIContracts
import PhotoAnalysisKit
@testable import RawCull
import RawCullCore
import Synchronization
import Testing

@MainActor
struct RawCullViewModelCullingTests {
    @Test
    func `AF scores persist separately and legacy records remain unmeasured`() throws {
        let model = CullingModel(saveDelayNanoseconds: 0, saveHandler: { _ in })
        let catalog = URL(fileURLWithPath: "/tmp/af-persistence-\(UUID().uuidString)")
        model.mergeScoringResults([
            CullingScoringResult(fileName: "photo.ARW", score: 0.9, saliencySubject: nil, afPointScore: 0.2)
        ], in: catalog)
        let data = try JSONEncoder().encode(model.savedFiles)
        let decoded = try JSONDecoder().decode([DecodeSavedFiles].self, from: data).map { SavedFiles($0) }
        #expect(decoded.first?.filerecords?.first?.sharpnessScore == 0.9)
        #expect(decoded.first?.filerecords?.first?.afPointSharpnessScore == 0.2)

        // A fresh run with no AF evidence must remove any earlier AF measurement.
        model.mergeScoringResults([
            CullingScoringResult(fileName: "photo.ARW", score: 0.8, saliencySubject: nil)
        ], in: catalog)
        #expect(model.savedFiles.first?.filerecords?.first?.afPointSharpnessScore == nil)
        let legacy = try JSONDecoder().decode(
            DecodeFileRecord.self, from: Data(#"{"fileName":"old.ARW","sharpnessScore":0.9}"#.utf8),
        )
        #expect(legacy.afPointSharpnessScore == nil)
    }

    @Test
    func `rebuildRatingCache populates ratings and tagged filenames for selected catalog`() {
        let viewModel = makeRawCullViewModel()
        let catalog = ARWSourceCatalog(name: "Catalog", url: URL(fileURLWithPath: "/tmp/catalog-\(UUID().uuidString)"))
        viewModel.selectedSource = catalog
        viewModel.cullingModel = CullingModel(saveDelayNanoseconds: 0, saveHandler: { _ in })
        viewModel.cullingModel.updateRatings(fileNames: ["one.ARW", "two.ARW"], rating: 2, in: catalog.url)
        viewModel.cullingModel.mergeScoringResults(
            [CullingScoringResult(fileName: "scored.ARW", score: 0.7, saliencySubject: nil)],
            in: catalog.url,
        )

        viewModel.rebuildRatingCache()

        #expect(viewModel.ratingCache == ["one.ARW": 2, "two.ARW": 2])
        #expect(viewModel.taggedNamesCache == ["one.ARW", "two.ARW"])
    }

    @Test
    func `passesRatingFilter distinguishes rejected keepers and star ratings`() {
        let viewModel = makeRawCullViewModel()
        let rejected = makeCullingTestFile("rejected.ARW")
        let keeper = makeCullingTestFile("keeper.ARW")
        let unrated = makeCullingTestFile("unrated.ARW")
        let star = makeCullingTestFile("star.ARW")
        viewModel.ratingCache = [
            rejected.name: -1,
            keeper.name: 0,
            star.name: 4
        ]

        viewModel.ratingFilter = .rejected
        #expect(viewModel.passesRatingFilter(rejected))
        #expect(!viewModel.passesRatingFilter(keeper))

        viewModel.ratingFilter = .keepers
        #expect(viewModel.passesRatingFilter(keeper))
        #expect(!viewModel.passesRatingFilter(unrated))
        #expect(!viewModel.passesRatingFilter(star))

        viewModel.ratingFilter = .stars(4)
        #expect(viewModel.passesRatingFilter(star))
        #expect(!viewModel.passesRatingFilter(rejected))
    }

    @Test
    func `preselectFirstVisibleFileByName selects alphabetically first visible file`() {
        let viewModel = makeRawCullViewModel()
        let c = makeCullingTestFile("C.ARW")
        let a = makeCullingTestFile("A.ARW")
        let b = makeCullingTestFile("B.ARW")
        viewModel.files = [c, a, b]
        viewModel.filteredFiles = [c, a, b]

        viewModel.preselectFirstVisibleFileByName()

        #expect(viewModel.selectedFileID == a.id)
    }

    @Test
    func `preselectFirstVisibleFileByName replaces previous selection`() {
        let viewModel = makeRawCullViewModel()
        let previous = makeCullingTestFile("previous.ARW")
        let c = makeCullingTestFile("C.ARW")
        let a = makeCullingTestFile("A.ARW")
        let b = makeCullingTestFile("B.ARW")
        viewModel.files = [previous, c, a, b]
        viewModel.filteredFiles = [c, a, b]
        viewModel.selectedFileID = previous.id

        viewModel.preselectFirstVisibleFileByName()

        #expect(viewModel.selectedFileID == a.id)
    }

    @Test
    func `preselectFirstVisibleFileByName clears selection when no files are visible`() {
        let viewModel = makeRawCullViewModel()
        let previous = makeCullingTestFile("previous.ARW")
        viewModel.files = [previous]
        viewModel.filteredFiles = []
        viewModel.selectedFileID = previous.id

        viewModel.preselectFirstVisibleFileByName()

        #expect(viewModel.selectedFileID == nil)
    }

    @Test
    func `enabling AF sharpness sorting selects strongest AF detail despite combined scores`() async {
        let viewModel = makeRawCullViewModel()
        let softest = makeCullingTestFile("A-softest.ARW")
        let sharpest = makeCullingTestFile("B-sharpest.ARW")
        let middle = makeCullingTestFile("C-middle.ARW")
        viewModel.files = [softest, sharpest, middle]
        viewModel.selectedFileID = softest.id
        // Deliberately reverse the combined scores: catalog order must follow AF detail.
        viewModel.sharpnessModel.scores = [softest.id: 0.9, sharpest.id: 0.1, middle.id: 0.5]
        viewModel.sharpnessModel.afPointScores = [softest.id: 0.1, sharpest.id: 0.9, middle.id: 0.5]
        viewModel.sharpnessModel.sortBySharpness = true

        await viewModel.handleSharpnessSortingChange(isEnabled: true)

        #expect(viewModel.filteredFiles.map(\.id) == [sharpest.id, middle.id, softest.id])
        #expect(viewModel.selectedFileID == sharpest.id)
    }

    @Test
    func `disabling sharpness sorting preserves current selection`() async {
        let viewModel = makeRawCullViewModel()
        let first = makeCullingTestFile("A.ARW")
        let selected = makeCullingTestFile("B.ARW")
        viewModel.files = [selected, first]
        viewModel.selectedFileID = selected.id
        viewModel.sharpnessModel.sortBySharpness = false

        await viewModel.handleSharpnessSortingChange(isEnabled: false)

        #expect(viewModel.selectedFileID == selected.id)
    }

    @Test
    func `burst analysis targets selected thumbnails before rating filter`() {
        let viewModel = makeRawCullViewModel()
        let twoStar = makeCullingTestFile("B-two-star.ARW")
        let selectedLater = makeCullingTestFile("C-selected.ARW")
        let selectedEarlier = makeCullingTestFile("A-selected.ARW")
        viewModel.files = [twoStar, selectedLater, selectedEarlier]
        viewModel.ratingCache = [twoStar.name: 2]
        viewModel.ratingFilter = .stars(2)
        viewModel.selectedFileIDs = [selectedLater.id, selectedEarlier.id]

        #expect(viewModel.burstAnalysisTargetFiles.map(\.name) == ["A-selected.ARW", "C-selected.ARW"])
    }

    @Test
    func `burst analysis targets exact active star rating`() {
        let viewModel = makeRawCullViewModel()
        let twoStar = makeCullingTestFile("B-two-star.ARW")
        let fourStar = makeCullingTestFile("A-four-star.ARW")
        let unrated = makeCullingTestFile("C-unrated.ARW")
        viewModel.files = [twoStar, fourStar, unrated]
        viewModel.ratingCache = [
            twoStar.name: 2,
            fourStar.name: 4
        ]
        viewModel.ratingFilter = .stars(2)

        #expect(viewModel.burstAnalysisTargetFiles.map(\.name) == ["B-two-star.ARW"])
    }

    @Test
    func `burst analysis keeps full catalog for unscoped filters`() {
        let viewModel = makeRawCullViewModel()
        let rejected = makeCullingTestFile("C-rejected.ARW")
        let keeper = makeCullingTestFile("A-keeper.ARW")
        let rated = makeCullingTestFile("B-rated.ARW")
        viewModel.files = [rejected, keeper, rated]
        viewModel.ratingCache = [
            rejected.name: -1,
            rated.name: 3
        ]

        let expectedNames = ["A-keeper.ARW", "B-rated.ARW", "C-rejected.ARW"]

        viewModel.ratingFilter = .all
        #expect(viewModel.burstAnalysisTargetFiles.map(\.name) == expectedNames)

        viewModel.ratingFilter = .keepers
        #expect(viewModel.burstAnalysisTargetFiles.map(\.name) == expectedNames)

        viewModel.ratingFilter = .rejected
        #expect(viewModel.burstAnalysisTargetFiles.map(\.name) == expectedNames)
    }

    @Test
    func `burst analysis orders shots by capture date with file-date fallback`() {
        let viewModel = makeRawCullViewModel()
        let latest = makeCullingTestFile("A-latest.ARW", captureSeconds: 30)
        let earliest = makeCullingTestFile("Z-earliest.ARW", captureSeconds: 10)
        let fallback = makeCullingTestFile("M-fallback.ARW", modificationSeconds: 20)
        viewModel.files = [latest, fallback, earliest]

        #expect(viewModel.burstAnalysisTargetFiles.map(\.name) == [
            "Z-earliest.ARW",
            "M-fallback.ARW",
            "A-latest.ARW"
        ])
    }

    @Test
    func `sharpness scoring targets selected thumbnails before rating filter`() {
        let viewModel = makeRawCullViewModel()
        let twoStar = makeCullingTestFile("B-two-star.ARW")
        let selectedLater = makeCullingTestFile("C-selected.ARW")
        let selectedEarlier = makeCullingTestFile("A-selected.ARW")
        viewModel.files = [twoStar, selectedLater, selectedEarlier]
        viewModel.filteredFiles = [twoStar, selectedLater, selectedEarlier]
        viewModel.ratingCache = [twoStar.name: 2]
        viewModel.ratingFilter = .stars(2)
        viewModel.selectedFileIDs = [selectedLater.id, selectedEarlier.id]

        #expect(viewModel.sharpnessScoringTargetFiles.map(\.name) == ["C-selected.ARW", "A-selected.ARW"])
    }

    @Test
    func `sharpness scoring targets active star rating in visible order`() {
        let viewModel = makeRawCullViewModel()
        let firstVisible = makeCullingTestFile("D-two-star.ARW")
        let secondVisible = makeCullingTestFile("B-two-star.ARW")
        let fourStar = makeCullingTestFile("A-four-star.ARW")
        viewModel.files = [secondVisible, fourStar, firstVisible]
        viewModel.filteredFiles = [firstVisible, secondVisible, fourStar]
        viewModel.ratingCache = [
            firstVisible.name: 2,
            secondVisible.name: 2,
            fourStar.name: 4
        ]
        viewModel.ratingFilter = .stars(2)

        #expect(viewModel.sharpnessScoringTargetFiles.map(\.name) == ["D-two-star.ARW", "B-two-star.ARW"])
    }

    @Test
    func `sharpness scoring falls back to filename sorted catalog for non-star filters`() {
        let viewModel = makeRawCullViewModel()
        let rejected = makeCullingTestFile("C-rejected.ARW")
        let keeper = makeCullingTestFile("A-keeper.ARW")
        let rated = makeCullingTestFile("B-rated.ARW")
        viewModel.files = [rejected, keeper, rated]
        viewModel.filteredFiles = [rated]
        viewModel.ratingCache = [
            rejected.name: -1,
            rated.name: 3
        ]

        let expectedNames = ["A-keeper.ARW", "B-rated.ARW", "C-rejected.ARW"]

        viewModel.ratingFilter = .all
        #expect(viewModel.sharpnessScoringTargetFiles.map(\.name) == expectedNames)

        viewModel.ratingFilter = .keepers
        #expect(viewModel.sharpnessScoringTargetFiles.map(\.name) == expectedNames)

        viewModel.ratingFilter = .rejected
        #expect(viewModel.sharpnessScoringTargetFiles.map(\.name) == expectedNames)
    }

    @Test
    func `sharpness scoring appends hidden selected files after visible selected files`() {
        let viewModel = makeRawCullViewModel()
        let visibleSelected = makeCullingTestFile("C-visible-selected.ARW")
        let visibleUnselected = makeCullingTestFile("B-visible-unselected.ARW")
        let hiddenSelected = makeCullingTestFile("A-hidden-selected.ARW")
        viewModel.files = [visibleSelected, visibleUnselected, hiddenSelected]
        viewModel.filteredFiles = [visibleSelected, visibleUnselected]
        viewModel.selectedFileIDs = [visibleSelected.id, hiddenSelected.id]

        #expect(viewModel.sharpnessScoringTargetFiles.map(\.name) == [
            "C-visible-selected.ARW",
            "A-hidden-selected.ARW"
        ])
    }

    @Test
    func `calibrateAndScoreCurrentCatalog scores and persists only target files`() async throws {
        let viewModel = makeRawCullViewModel()
        let catalog = ARWSourceCatalog(name: "Catalog", url: URL(fileURLWithPath: "/tmp/catalog-\(UUID().uuidString)"))
        let selectedVisible = makeCullingTestFile("B-selected-visible.ARW")
        let selectedHidden = makeCullingTestFile("A-selected-hidden.ARW")
        let unselected = makeCullingTestFile("C-unselected.ARW")
        let recorder = SharpnessScoreURLRecorder()

        viewModel.selectedSource = catalog
        viewModel.files = [unselected, selectedHidden, selectedVisible]
        viewModel.filteredFiles = [selectedVisible, unselected]
        viewModel.selectedFileIDs = [selectedVisible.id, selectedHidden.id]
        viewModel.cullingModel = CullingModel(saveDelayNanoseconds: 0, saveHandler: { _ in })
        let image = try #require(makeCullingSharpnessImage())
        let adapter = RawCullPhotoAnalysisAdapter(
            inputLoaderOverride: { file, _, _ in
                await recorder.record(file.url.lastPathComponent)
                return PhotoAnalysisInput(
                    image: image,
                    iso: file.iso,
                    aperture: file.aperture,
                    normalizedAFPoint: file.normalizedAFPoint,
                )
            },
        )
        viewModel.sharpnessModel = SharpnessScoringModel(
            analysisAdapterOverride: adapter,
        )

        await viewModel.calibrateAndScoreCurrentCatalog()

        let scoredFileNames = await recorder.recordedFileNames()
        #expect(Set(scoredFileNames) == ["A-selected-hidden.ARW", "B-selected-visible.ARW"])
        #expect(Set(viewModel.sharpnessModel.scores.keys) == [selectedHidden.id, selectedVisible.id])

        let records = viewModel.cullingModel.savedFiles.first?.filerecords ?? []
        #expect(Set(records.compactMap(\.fileName)) == ["A-selected-hidden.ARW", "B-selected-visible.ARW"])
        #expect(!records.contains { $0.fileName == unselected.name })
    }

    @Test
    func `extractRatedfilenames returns files at or above requested rating`() {
        let viewModel = makeRawCullViewModel()
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
        let viewModel = makeRawCullViewModel()
        let catalog = ARWSourceCatalog(name: "Catalog", url: URL(fileURLWithPath: "/tmp/catalog-\(UUID().uuidString)"))
        let files = [makeCullingTestFile("one.ARW"), makeCullingTestFile("two.ARW")]
        viewModel.selectedSource = catalog
        viewModel.cullingModel = CullingModel(saveDelayNanoseconds: 0, saveHandler: { _ in })

        viewModel.updateRating(for: files, rating: 5)

        #expect(viewModel.ratingCache == ["one.ARW": 5, "two.ARW": 5])
    }

    @Test
    func `rating mutations refresh the active rating-filter count`() {
        let viewModel = makeRawCullViewModel()
        let catalog = ARWSourceCatalog(
            name: "Catalog",
            url: URL(fileURLWithPath: "/tmp/catalog-\(UUID().uuidString)"),
        )
        let first = makeCullingTestFile("one.ARW")
        let second = makeCullingTestFile("two.ARW")
        viewModel.selectedSource = catalog
        viewModel.files = [first, second]
        viewModel.catalogDisplayCandidates = [first, second]
        viewModel.filteredFiles = [first, second]
        viewModel.ratingFilter = .stars(3)
        viewModel.cullingModel = CullingModel(saveDelayNanoseconds: 0, saveHandler: { _ in })

        viewModel.updateRating(for: first, rating: 3)
        #expect(viewModel.filteredFiles.map(\.name) == ["one.ARW"])

        viewModel.updateRating(for: second, rating: 3)
        #expect(viewModel.filteredFiles.map(\.name) == ["one.ARW", "two.ARW"])

        viewModel.updateRating(for: first, rating: 2)
        #expect(viewModel.filteredFiles.map(\.name) == ["two.ARW"])
    }

    @Test
    func `clear all culling state synchronizes caches filters and persisted data`() async {
        let recorder = SavedFilesRecorder()
        let viewModel = makeRawCullViewModel()
        let catalog = ARWSourceCatalog(
            name: "Catalog",
            url: URL(fileURLWithPath: "/tmp/catalog-\(UUID().uuidString)"),
        )
        let file = makeCullingTestFile("one.ARW")
        viewModel.selectedSource = catalog
        viewModel.files = [file]
        viewModel.catalogDisplayCandidates = [file]
        viewModel.filteredFiles = [file]
        viewModel.ratingFilter = .stars(3)
        viewModel.cullingModel = CullingModel(
            saveDelayNanoseconds: 30_000_000_000,
            saveHandler: { snapshot in await recorder.record(snapshot) },
        )
        viewModel.updateRating(for: file, rating: 3)

        viewModel.clearAllCullingState()
        let didSave = await viewModel.cullingModel.flushPersistence()
        let snapshots = await recorder.waitForSnapshotCount(1)

        #expect(didSave)
        #expect(viewModel.cullingModel.savedFiles.isEmpty)
        #expect(viewModel.ratingCache.isEmpty)
        #expect(viewModel.taggedNamesCache.isEmpty)
        #expect(viewModel.filteredFiles.isEmpty)
        #expect(snapshots.last?.isEmpty == true)
    }

    @Test
    func `applying Deep Review winner rates it three stars and marks group reviewed`() throws {
        let viewModel = makeRawCullViewModel()
        let catalog = ARWSourceCatalog(
            name: "Catalog",
            url: URL(fileURLWithPath: "/tmp/catalog-\(UUID().uuidString)"),
        )
        let files = [makeCullingTestFile("one.ARW"), makeCullingTestFile("two.ARW")]
        let winner = files[1]
        let groupID = 7
        let signature = try #require(BurstGroupSignature(files: files, catalog: catalog.url))
        let result = DeepAIReviewResult(
            groupID: groupID,
            groupSignature: signature,
            preset: .auto,
            candidates: [],
            recommendedFileID: winner.id,
            confidence: .high,
            reasons: [.strongestSubjectDetail],
            cautions: [],
            timestamp: Date(timeIntervalSince1970: 0),
        )
        viewModel.selectedSource = catalog
        viewModel.files = files
        viewModel.cullingModel = CullingModel(saveDelayNanoseconds: 0, saveHandler: { _ in })
        viewModel.similarityModel.burstGroups = [BurstGroup(id: groupID, fileIDs: files.map(\.id))]
        viewModel.similarityModel.burstGroupLookup = Dictionary(
            uniqueKeysWithValues: files.map { ($0.id, groupID) },
        )
        viewModel.burstReviewSession.replaceRankings([groupID: makeCullingBurstResult(groupID: groupID, files: files)])
        viewModel.updateRating(for: files[0], rating: 2)

        viewModel.applyDeepAIReviewRecommendation(result, to: files)

        #expect(viewModel.ratingCache == [files[0].name: 2, winner.name: 3])
        #expect(viewModel.burstReviewStates[groupID] == .reviewed)
        #expect(viewModel.burstAnalysisResults[groupID]?.reviewState == .reviewed)
        #expect(viewModel.cullingModel.overrideWinner(for: files, in: catalog.url)?.winnerFileName == winner.name)
    }

    @Test
    func `updateRatingAndAdvance rates current file and selects next visible file`() {
        let viewModel = makeRawCullViewModel()
        let catalog = ARWSourceCatalog(name: "Catalog", url: URL(fileURLWithPath: "/tmp/catalog-\(UUID().uuidString)"))
        let files = [makeCullingTestFile("one.ARW"), makeCullingTestFile("two.ARW")]
        viewModel.selectedSource = catalog
        viewModel.files = files
        viewModel.selectedFileID = files[0].id
        viewModel.cullingModel = CullingModel(saveDelayNanoseconds: 0, saveHandler: { _ in })

        viewModel.updateRatingAndAdvance(for: files[0], rating: 3, in: files)

        #expect(viewModel.selectedFileID == files[1].id)
        #expect(viewModel.ratingCache == ["one.ARW": 3])
        #expect(viewModel.cullingModel.savedFiles.first?.filerecords?.first?.fileName == "one.ARW")
        #expect(viewModel.cullingModel.savedFiles.first?.filerecords?.first?.rating == 3)
    }

    @Test(arguments: [-1, 0, 2, 3, 4, 5])
    func `updateRatingAndAdvance marks active burst reviewed`(_ rating: Int) {
        let viewModel = makeRawCullViewModel()
        let catalog = ARWSourceCatalog(name: "Catalog", url: URL(fileURLWithPath: "/tmp/catalog-\(UUID().uuidString)"))
        let files = [makeCullingTestFile("one.ARW"), makeCullingTestFile("two.ARW")]
        let groupID = 7
        viewModel.selectedSource = catalog
        viewModel.files = files
        viewModel.selectedFileID = files[0].id
        viewModel.activeBurstComparisonGroupID = groupID
        viewModel.burstReviewSession.replaceRankings([groupID: makeCullingBurstResult(groupID: groupID, files: files)])
        viewModel.cullingModel = CullingModel(saveDelayNanoseconds: 0, saveHandler: { _ in })

        viewModel.updateRatingAndAdvance(for: files[0], rating: rating, in: files)

        #expect(viewModel.ratingCache == [files[0].name: rating])
        #expect(viewModel.burstReviewStates[groupID] == .reviewed)
        #expect(viewModel.burstAnalysisResults[groupID]?.reviewState == .reviewed)
    }

    @Test
    func `updateRatingAndAdvance leaves last visible file selected`() {
        let viewModel = makeRawCullViewModel()
        let catalog = ARWSourceCatalog(name: "Catalog", url: URL(fileURLWithPath: "/tmp/catalog-\(UUID().uuidString)"))
        let files = [makeCullingTestFile("one.ARW"), makeCullingTestFile("two.ARW")]
        viewModel.selectedSource = catalog
        viewModel.files = files
        viewModel.selectedFileID = files[1].id
        viewModel.cullingModel = CullingModel(saveDelayNanoseconds: 0, saveHandler: { _ in })

        viewModel.updateRatingAndAdvance(for: files[1], rating: 5, in: files)

        #expect(viewModel.selectedFileID == files[1].id)
        #expect(viewModel.ratingCache == ["two.ARW": 5])
    }

    @Test
    func `updateRatingAndAdvance without catalog leaves rating and selection unchanged`() {
        let viewModel = makeRawCullViewModel()
        let files = [makeCullingTestFile("one.ARW"), makeCullingTestFile("two.ARW")]
        viewModel.files = files
        viewModel.selectedFileID = files[0].id
        viewModel.cullingModel = CullingModel(saveDelayNanoseconds: 0, saveHandler: { _ in })

        viewModel.updateRatingAndAdvance(for: files[0], rating: 4, in: files)

        #expect(viewModel.selectedFileID == files[0].id)
        #expect(viewModel.ratingCache.isEmpty)
        #expect(viewModel.cullingModel.savedFiles.isEmpty)
    }

    @Test
    func `updateRatingAndAdvance with file outside visible order does not change selection`() {
        let viewModel = makeRawCullViewModel()
        let catalog = ARWSourceCatalog(name: "Catalog", url: URL(fileURLWithPath: "/tmp/catalog-\(UUID().uuidString)"))
        let visible = [makeCullingTestFile("one.ARW"), makeCullingTestFile("two.ARW")]
        let hidden = makeCullingTestFile("hidden.ARW")
        viewModel.selectedSource = catalog
        viewModel.files = visible + [hidden]
        viewModel.selectedFileID = visible[0].id
        viewModel.cullingModel = CullingModel(saveDelayNanoseconds: 0, saveHandler: { _ in })

        viewModel.updateRatingAndAdvance(for: hidden, rating: 2, in: visible)

        #expect(viewModel.selectedFileID == visible[0].id)
        #expect(viewModel.ratingCache == ["hidden.ARW": 2])
    }

    @Test
    func `clearCurrentCatalogCullingState allows rating same catalog again`() {
        let viewModel = makeRawCullViewModel()
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

    @Test
    func `burst signatures are order independent and catalog relative`() throws {
        let catalog = URL(fileURLWithPath: "/tmp/catalog-\(UUID().uuidString)")
        let first = FileItem(
            url: catalog.appendingPathComponent("day1/duplicate.ARW"),
            name: "duplicate.ARW",
            size: 1,
            dateModified: Date(timeIntervalSince1970: 0),
            exifData: nil,
            afFocusNormalized: nil,
        )
        let second = FileItem(
            url: catalog.appendingPathComponent("day2/duplicate.ARW"),
            name: "duplicate.ARW",
            size: 1,
            dateModified: Date(timeIntervalSince1970: 0),
            exifData: nil,
            afFocusNormalized: nil,
        )

        let lhs = try #require(BurstGroupSignature(files: [first, second], catalog: catalog))
        let rhs = try #require(BurstGroupSignature(files: [second, first], catalog: catalog))

        #expect(lhs == rhs)
        #expect(lhs.memberKeys == ["day1/duplicate.ARW", "day2/duplicate.ARW"])
    }

    @Test
    func `cached review state restores by signature after file id remap`() throws {
        let viewModel = makeRawCullViewModel()
        let catalog = ARWSourceCatalog(name: "Catalog", url: URL(fileURLWithPath: "/tmp/catalog-\(UUID().uuidString)"))
        let oldA = makeCullingTestFile("A.ARW")
        let oldB = makeCullingTestFile("B.ARW")
        let currentA = makeCullingTestFile("A.ARW")
        let currentB = makeCullingTestFile("B.ARW")
        let signature = try #require(BurstGroupSignature(files: [oldA, oldB], catalog: catalog.url))

        viewModel.selectedSource = catalog
        viewModel.files = [currentA, currentB]
        viewModel.similarityModel.burstGroups = [BurstGroup(id: 9, fileIDs: [currentA.id, currentB.id])]

        let snapshot = makeBurstSnapshot(
            catalog: catalog.url,
            files: [oldA, oldB],
            groups: [BurstGroup(id: 1, fileIDs: [oldA.id, oldB.id])],
            results: [],
            reviewStateSnapshots: [BurstReviewStateSnapshot(signature: signature, state: .decisionApplied)],
        )

        let states = viewModel.cachedReviewStates(from: snapshot)

        #expect(states == [9: .decisionApplied])
    }

    @Test
    func `cached review state ignores matching group id with changed membership`() throws {
        let viewModel = makeRawCullViewModel()
        let catalog = ARWSourceCatalog(name: "Catalog", url: URL(fileURLWithPath: "/tmp/catalog-\(UUID().uuidString)"))
        let oldA = makeCullingTestFile("A.ARW")
        let oldB = makeCullingTestFile("B.ARW")
        let currentA = makeCullingTestFile("A.ARW")
        let currentC = makeCullingTestFile("C.ARW")
        let signature = try #require(BurstGroupSignature(files: [oldA, oldB], catalog: catalog.url))

        viewModel.selectedSource = catalog
        viewModel.files = [currentA, currentC]
        viewModel.similarityModel.burstGroups = [BurstGroup(id: 1, fileIDs: [currentA.id, currentC.id])]

        let snapshot = makeBurstSnapshot(
            catalog: catalog.url,
            files: [oldA, oldB],
            groups: [BurstGroup(id: 1, fileIDs: [oldA.id, oldB.id])],
            results: [],
            reviewStateSnapshots: [BurstReviewStateSnapshot(signature: signature, state: .decisionApplied)],
        )

        let states = viewModel.cachedReviewStates(from: snapshot)

        #expect(states.isEmpty)
    }

    @Test
    func `cancelled burst analysis cannot apply a late cache result`() async {
        let gate = BurstCacheLoadGate()
        let cacheRepository = TestBurstAnalysisCacheRepository(
            load: { _, _, _, _, _ in await gate.load() },
        )
        let viewModel = makeRawCullViewModel(
            similarityService: CancellationDistanceSimilarityService(
                probe: SimilarityDistanceCancellationProbe(),
            ),
            similarityArtifactStore: makeIsolatedSimilarityArtifactStore(),
            burstAnalysisCacheRepository: cacheRepository,
        )
        let catalog = ARWSourceCatalog(
            name: "Catalog",
            url: URL(fileURLWithPath: "/tmp/catalog-\(UUID().uuidString)"),
        )
        let first = makeCullingTestFile("A.ARW")
        let second = makeCullingTestFile("B.ARW")
        let snapshot = makeBurstSnapshot(
            catalog: catalog.url,
            files: [first, second],
            groups: [BurstGroup(id: 0, fileIDs: [first.id, second.id])],
            results: [],
            reviewStateSnapshots: [],
        )

        viewModel.selectedSource = catalog
        viewModel.files = [first, second]
        viewModel.filteredFiles = [first, second]
        let analysis = Task {
            await viewModel.restoreExistingFullCatalogBurstAnalysis()
        }
        await gate.waitUntilStarted()

        viewModel.cancelAndResetBurstAnalysis()
        await gate.resume(returning: snapshot)
        _ = await analysis.value

        #expect(viewModel.burstAnalysisCoordinator.task == nil)
        #expect(!viewModel.burstAnalysisProgress.isRunning)
        #expect(viewModel.similarityModel.burstGroups.isEmpty)
        #expect(viewModel.burstAnalysisResults.isEmpty)
        #expect(viewModel.burstReviewStates.isEmpty)
    }

    @Test
    func `catalog cancellation resets all burst analysis state`() {
        let viewModel = makeRawCullViewModel()
        let file = makeCullingTestFile("A.ARW")
        viewModel.burstAnalysisCoordinator.updateProgress(
            BurstAnalysisProgress(step: .ranking),
        )
        viewModel.burstReviewSession.replaceRankings([1: makeCullingBurstResult(groupID: 1, files: [file])])
        viewModel.burstReviewSession.restoreReviewStates([1: .deferred])
        viewModel.burstReviewQueueFilter = .deferred
        viewModel.activeBurstComparisonGroupID = 1
        viewModel.lastBurstUndoEntry = BurstUndoEntry(groupID: 1, previousRatingsByFileName: [file.name: 0])
        viewModel.comparisonFileIDs = [file.id]

        viewModel.cancelCatalogLoad()

        #expect(!viewModel.burstAnalysisProgress.isRunning)
        #expect(viewModel.burstAnalysisResults.isEmpty)
        #expect(viewModel.burstReviewStates.isEmpty)
        #expect(viewModel.burstReviewQueueFilter == .all)
        #expect(viewModel.activeBurstComparisonGroupID == nil)
        #expect(viewModel.lastBurstUndoEntry == nil)
        #expect(viewModel.comparisonFileIDs.isEmpty)
    }

    @Test
    func `burst cache rejects a different similarity signature`() async {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("RawCullTests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let cache = BurstAnalysisCache(cacheDirectory: directory)
        let catalog = URL(fileURLWithPath: "/tmp/catalog-\(UUID().uuidString)")
        let files = [makeCullingTestFile("A.ARW"), makeCullingTestFile("B.ARW")]
        let originalSignature = makeBurstSimilaritySignature(sensitivity: 0.25)
        let snapshot = makeBurstSnapshot(
            catalog: catalog,
            files: files,
            groups: [],
            results: [],
            reviewStateSnapshots: [],
            similaritySignature: originalSignature,
        )

        await cache.save(snapshot, catalog: catalog)

        let matching = await cache.load(
            catalog: catalog,
            files: files,
            thumbnailMaxPixelSize: 512,
            sharpnessSignature: snapshot.sharpnessSignature,
            similaritySignature: originalSignature,
        )
        let mismatching = await cache.load(
            catalog: catalog,
            files: files,
            thumbnailMaxPixelSize: 512,
            sharpnessSignature: snapshot.sharpnessSignature,
            similaritySignature: makeBurstSimilaritySignature(sensitivity: 0.10),
        )

        #expect(matching != nil)
        #expect(mismatching == nil)
    }

    @Test
    func `restoring an existing full burst index never starts scoring or indexing`() async {
        let catalog = ARWSourceCatalog(
            name: "Catalog",
            url: URL(fileURLWithPath: "/tmp/catalog-\(UUID().uuidString)"),
        )
        let first = makeCullingTestFile("A.ARW")
        let second = makeCullingTestFile("B.ARW")
        let group = BurstGroup(id: 0, fileIDs: [first.id, second.id])
        var snapshot = makeBurstSnapshot(
            catalog: catalog.url,
            files: [first, second],
            groups: [group],
            results: [makeCullingBurstResult(groupID: group.id, files: [first, second])],
            reviewStateSnapshots: [],
        )
        snapshot.embeddings = [:]
        snapshot.similarityArtifactSetDigest = BurstAnalysisCache.artifactSetDigest(
            files: [first, second],
            artifacts: [:],
        )
        let viewModel = makeRawCullViewModel(
            similarityArtifactStore: makeIsolatedSimilarityArtifactStore(),
            burstAnalysisCacheRepository: TestBurstAnalysisCacheRepository(
                load: { _, _, _, _, _ in snapshot },
            ),
        )

        viewModel.selectedSource = catalog
        viewModel.files = [first, second]
        viewModel.filteredFiles = [first, second]

        let restored = await viewModel.restoreExistingFullCatalogBurstAnalysis()

        #expect(restored)
        #expect(viewModel.hasExistingFullCatalogBurstGroupIndex)
        #expect(viewModel.similarityModel.burstGroups == [group])
        #expect(!viewModel.sharpnessModel.isScoring)
        #expect(!viewModel.similarityModel.isIndexing)
        #expect(!viewModel.burstAnalysisProgress.isRunning)
    }

    @Test
    func `burst cache rejects groups produced by the previous timestamp algorithm`() async {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("RawCullAlgorithmCacheTests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let cache = BurstAnalysisCache(cacheDirectory: directory)
        let catalog = URL(fileURLWithPath: "/tmp/catalog-\(UUID().uuidString)")
        let files = [makeCullingTestFile("A.ARW"), makeCullingTestFile("B.ARW")]
        var snapshot = makeBurstSnapshot(
            catalog: catalog,
            files: files,
            groups: [],
            results: [],
            reviewStateSnapshots: [],
        )
        snapshot.algorithmVersion = BurstGroupingConfig.algorithmVersion - 1

        await cache.save(snapshot, catalog: catalog)

        let loaded = await cache.load(
            catalog: catalog,
            files: files,
            thumbnailMaxPixelSize: 512,
            sharpnessSignature: snapshot.sharpnessSignature,
            similaritySignature: snapshot.similaritySignature,
        )

        #expect(loaded == nil)
    }

    @Test
    func `burst cache reports usage and clears every catalog snapshot`() async {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("RawCullUsageCacheTests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let cache = BurstAnalysisCache(cacheDirectory: directory)
        for index in 0 ..< 2 {
            let catalog = URL(fileURLWithPath: "/tmp/catalog-\(index)-\(UUID().uuidString)")
            let files = [makeCullingTestFile("\(index)-A.ARW"), makeCullingTestFile("\(index)-B.ARW")]
            let snapshot = makeBurstSnapshot(
                catalog: catalog,
                files: files,
                groups: [],
                results: [],
                reviewStateSnapshots: [],
            )
            await cache.save(snapshot, catalog: catalog)
        }

        let populatedUsage = await cache.getDiskCacheUsage()
        #expect(populatedUsage.fileCount == 2)
        #expect(populatedUsage.size > 0)

        await cache.clear()

        let clearedUsage = await cache.getDiskCacheUsage()
        #expect(clearedUsage.fileCount == 0)
        #expect(clearedUsage.size == 0)
    }

    @Test
    func `burst cache round trips a large snapshot off the main actor`() async {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("RawCullLargeCacheTests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let cache = BurstAnalysisCache(cacheDirectory: directory)
        let catalog = URL(fileURLWithPath: "/tmp/catalog-\(UUID().uuidString)")
        let files = (0 ..< 500).map { index in
            makeCullingTestFile("cache-\(index).ARW")
        }
        let groups = stride(from: 0, to: files.count, by: 5).enumerated().map { groupID, start in
            BurstGroup(id: groupID, fileIDs: files[start ..< min(start + 5, files.count)].map(\.id))
        }
        var snapshot = makeBurstSnapshot(
            catalog: catalog,
            files: files,
            groups: groups,
            results: groups.map { group in
                makeCullingBurstResult(
                    groupID: group.id,
                    files: group.fileIDs.compactMap { id in files.first { $0.id == id } },
                )
            },
            reviewStateSnapshots: [],
        )
        snapshot.embeddings = Dictionary(uniqueKeysWithValues: files.map { file in
            (
                file.id,
                makeSimilarityTestArtifact(
                    source: SimilarityScoringModel.source(for: file),
                    payload: Data(
                        repeating: UInt8(file.name.count % 255),
                        count: 256,
                    ),
                ),
            )
        })
        snapshot.similarityArtifactSetDigest = BurstAnalysisCache.artifactSetDigest(
            files: files,
            artifacts: snapshot.embeddings,
        )
        snapshot.sharpnessScores = Dictionary(uniqueKeysWithValues: files.enumerated().map { index, file in
            (file.id, Float(index) / Float(files.count))
        })

        await cache.save(snapshot, catalog: catalog)
        let loaded = await cache.load(
            catalog: catalog,
            files: files,
            thumbnailMaxPixelSize: snapshot.thumbnailMaxPixelSize,
            sharpnessSignature: snapshot.sharpnessSignature,
            similaritySignature: snapshot.similaritySignature,
        )

        #expect(loaded == snapshot)
    }

    @Test
    func `review state persistence keeps completed analysis scope`() async throws {
        let catalog = ARWSourceCatalog(
            name: "Catalog",
            url: URL(fileURLWithPath: "/tmp/catalog-\(UUID().uuidString)"),
        )
        let first = makeCullingTestFile("A.ARW")
        let second = makeCullingTestFile("B.ARW")
        let group = BurstGroup(id: 0, fileIDs: [first.id, second.id])
        let result = makeCullingBurstResult(groupID: 0, files: [first, second])
        var snapshot = makeBurstSnapshot(
            catalog: catalog.url,
            files: [first, second],
            groups: [group],
            results: [result],
            reviewStateSnapshots: [],
        )
        snapshot.embeddings = [:]
        snapshot.similarityArtifactSetDigest = BurstAnalysisCache.artifactSetDigest(
            files: [first, second],
            artifacts: [:],
        )
        let recorder = BurstCacheSaveRecorder()
        let viewModel = makeRawCullViewModel(
            similarityService: SuspendingSimilarityService(
                probe: SimilarityEmbeddingSuspensionProbe(),
            ),
            similarityArtifactStore: makeIsolatedSimilarityArtifactStore(),
            burstAnalysisCacheRepository: TestBurstAnalysisCacheRepository(
                load: { _, _, _, _, _ in snapshot },
                save: { savedSnapshot, _ in
                    await recorder.record(savedSnapshot)
                },
            ),
        )

        viewModel.selectedSource = catalog
        viewModel.files = [first, second]
        viewModel.filteredFiles = [first, second]

        #expect(await viewModel.restoreExistingFullCatalogBurstAnalysis())
        viewModel.selectedFileIDs = [first.id]
        viewModel.filteredFiles = [first]
        viewModel.markBurstGroupReviewed(groupID: 0)

        let saved = try #require(await recorder.waitForSnapshot())
        #expect(saved.files.map(\.path) == [first.url.path, second.url.path])
        #expect(saved.groups == [group])
        #expect(saved.results.first?.fileIDs == [first.id, second.id])
    }

    @Test
    func `live regroup review state follows membership instead of group id`() throws {
        let viewModel = makeRawCullViewModel()
        let catalog = URL(fileURLWithPath: "/tmp/catalog-\(UUID().uuidString)")
        let first = makeCullingTestFile("A.ARW")
        let second = makeCullingTestFile("B.ARW")
        let third = makeCullingTestFile("C.ARW")
        let originalSignature = try #require(
            BurstGroupSignature(files: [first, second], catalog: catalog),
        )
        let saved: [BurstGroupSignature: BurstReviewState] = [
            originalSignature: .deferred
        ]

        let restored = viewModel.restoredBurstReviewStates(
            savedStatesBySignature: saved,
            groups: [
                BurstGroup(id: 7, fileIDs: [first.id, second.id]),
                BurstGroup(id: 0, fileIDs: [third.id])
            ],
            files: [first, second, third],
            catalog: catalog,
        )

        #expect(restored == [7: .deferred])
    }

    @Test
    func `live regroup drops state when reused group id has changed membership`() throws {
        let viewModel = makeRawCullViewModel()
        let catalog = URL(fileURLWithPath: "/tmp/catalog-\(UUID().uuidString)")
        let first = makeCullingTestFile("A.ARW")
        let second = makeCullingTestFile("B.ARW")
        let third = makeCullingTestFile("C.ARW")
        let originalSignature = try #require(
            BurstGroupSignature(files: [first, second], catalog: catalog),
        )

        let restored = viewModel.restoredBurstReviewStates(
            savedStatesBySignature: [originalSignature: .reviewed],
            groups: [BurstGroup(id: 0, fileIDs: [first.id, third.id])],
            files: [first, second, third],
            catalog: catalog,
        )

        #expect(restored.isEmpty)
    }
}
