import Foundation
@testable import RawCull
import Testing

private func burstTestFile(
    _ name: String,
    seconds: TimeInterval,
    size: Int64 = 1,
    aperture: Double? = 5.6,
    iso: Int? = 400,
    camera: String? = "ILCE-1",
    lens: String? = "FE 600mm",
    focalLength: String? = "600.0mm",
    af: CGPoint? = CGPoint(x: 0.5, y: 0.5),
) -> FileItem {
    FileItem(
        url: URL(fileURLWithPath: "/tmp/\(name)"),
        name: name,
        size: size,
        dateModified: Date(timeIntervalSince1970: seconds),
        exifData: ExifMetadata(
            shutterSpeed: "1/2000",
            focalLength: focalLength,
            aperture: aperture.map { "f/\($0)" },
            apertureValue: aperture,
            iso: iso.map { "ISO \($0)" },
            isoValue: iso,
            camera: camera,
            lensModel: lens,
            rawFileType: nil,
            rawSizeClass: nil,
            pixelWidth: nil,
            pixelHeight: nil,
        ),
        afFocusNormalized: af,
    )
}

@Suite("BurstGroupingEngine")
@MainActor
struct BurstGroupingEngineTests {
    @Test(.tags(.smoke))
    func `groups adjacent frames below threshold`() {
        let files = [
            burstTestFile("a.ARW", seconds: 0),
            burstTestFile("b.ARW", seconds: 0.4),
            burstTestFile("c.ARW", seconds: 0.8)
        ]
        let distances = [
            BurstPairKey.cacheKey(previousID: files[0].id, currentID: files[1].id): Float(0.10),
            BurstPairKey.cacheKey(previousID: files[1].id, currentID: files[2].id): Float(0.12)
        ]

        let output = BurstGroupingEngine.group(
            files: files,
            adjacentDistances: distances,
            config: BurstGroupingConfig(visualDistanceThreshold: 0.25),
        )

        #expect(output.groups.map(\.fileIDs.count) == [3])
        #expect(output.boundaryEvidence.allSatisfy { !$0.startsNewGroup })
    }

    @Test(.tags(.smoke))
    func `splits on visual distance and missing evidence`() {
        let files = [
            burstTestFile("a.ARW", seconds: 0),
            burstTestFile("b.ARW", seconds: 0.4),
            burstTestFile("c.ARW", seconds: 0.8)
        ]
        let distances = [
            BurstPairKey.cacheKey(previousID: files[0].id, currentID: files[1].id): Float(0.35)
        ]

        let output = BurstGroupingEngine.group(
            files: files,
            adjacentDistances: distances,
            config: BurstGroupingConfig(visualDistanceThreshold: 0.25),
        )

        #expect(output.groups.map(\.fileIDs.count) == [1, 1, 1])
        #expect(output.boundaryEvidence.map(\.startsNewGroup) == [true, true])
    }

    @Test(.tags(.smoke))
    func `splits on time gap and metadata changes`() {
        let files = [
            burstTestFile("a.ARW", seconds: 0, iso: 400),
            burstTestFile("b.ARW", seconds: 4.0, iso: 800)
        ]
        let distances = [
            BurstPairKey.cacheKey(previousID: files[0].id, currentID: files[1].id): Float(0.10)
        ]

        let output = BurstGroupingEngine.group(
            files: files,
            adjacentDistances: distances,
            config: BurstGroupingConfig(visualDistanceThreshold: 0.25, maxTimeGapSeconds: 2.0),
        )

        #expect(output.groups.map(\.fileIDs.count) == [1, 1])
        #expect(output.boundaryEvidence.first?.exposureChanged == true)
    }
}

@Suite("BurstRankingEngine")
@MainActor
struct BurstRankingEngineTests {
    @Test(.tags(.smoke))
    func `recommends sharpest candidate with high confidence when evidence is stable`() {
        let files = [
            burstTestFile("a.ARW", seconds: 0),
            burstTestFile("b.ARW", seconds: 0.3),
            burstTestFile("c.ARW", seconds: 0.6)
        ]
        let group = BurstGroup(id: 0, fileIDs: files.map(\.id))
        let evidence = [
            BurstBoundaryEvidence(previousID: files[0].id, currentID: files[1].id, visualDistance: 0.10, timeGapSeconds: 0.3, focalLengthDelta: 0, exposureChanged: false, cameraChanged: false, lensChanged: false, startsNewGroup: false, reasons: []),
            BurstBoundaryEvidence(previousID: files[1].id, currentID: files[2].id, visualDistance: 0.10, timeGapSeconds: 0.3, focalLengthDelta: 0, exposureChanged: false, cameraChanged: false, lensChanged: false, startsNewGroup: false, reasons: [])
        ]

        let result = BurstRankingEngine.rankGroup(
            group,
            filesByID: Dictionary(uniqueKeysWithValues: files.map { ($0.id, $0) }),
            scores: [files[0].id: 0.40, files[1].id: 1.0, files[2].id: 0.35],
            maxScore: 1.0,
            saliencyInfo: Dictionary(uniqueKeysWithValues: files.map { ($0.id, SaliencyInfo(subjectLabel: "bird")) }),
            boundaryEvidence: evidence,
        )

        #expect(result.recommendedFileID == files[1].id)
        #expect(result.confidence == .high)
        #expect(result.isSafeForOneClickCulling)
    }

    @Test(.tags(.smoke))
    func `close top candidates produce lower confidence`() {
        let files = [
            burstTestFile("a.ARW", seconds: 0),
            burstTestFile("b.ARW", seconds: 0.3),
            burstTestFile("c.ARW", seconds: 0.6)
        ]
        let group = BurstGroup(id: 0, fileIDs: files.map(\.id))

        let result = BurstRankingEngine.rankGroup(
            group,
            filesByID: Dictionary(uniqueKeysWithValues: files.map { ($0.id, $0) }),
            scores: [files[0].id: 0.90, files[1].id: 0.88, files[2].id: 0.20],
            maxScore: 1.0,
            saliencyInfo: [:],
            boundaryEvidence: [],
        )

        #expect(result.confidence == .low)
        #expect(!result.isSafeForOneClickCulling)
    }
}

@MainActor
@Suite("Burst ViewModel actions")
struct BurstViewModelActionTests {
    @Test(.tags(.critical))
    func `back from burst comparison restores active grouped burst view`() {
        let viewModel = RawCullViewModel()
        let files = [
            burstTestFile("a.ARW", seconds: 0),
            burstTestFile("b.ARW", seconds: 0.3),
            burstTestFile("c.ARW", seconds: 0.6)
        ]
        viewModel.files = files
        viewModel.filteredFiles = files
        viewModel.similarityModel.burstModeActive = true
        viewModel.similarityModel.burstGroups = [BurstGroup(id: 0, fileIDs: files.map(\.id))]
        viewModel.similarityModel.burstGroupLookup = Dictionary(uniqueKeysWithValues: files.map { ($0.id, 0) })

        viewModel.compareBurstGroup(files)
        #expect(viewModel.mainViewMode == .comparisonGrid)
        #expect(viewModel.similarityModel.burstModeActive == false)
        #expect(viewModel.activeBurstComparisonGroupID == 0)

        viewModel.returnToActiveBurstGroupView()
        #expect(viewModel.mainViewMode == .similarityGrid)
        #expect(viewModel.similarityModel.burstModeActive == true)
        #expect(viewModel.activeBurstComparisonGroupID == nil)
    }

    @Test(.tags(.critical))
    func `keep best keep top two and undo use rating policy`() {
        let viewModel = RawCullViewModel()
        let catalog = ARWSourceCatalog(name: "Catalog", url: URL(fileURLWithPath: "/tmp/catalog-\(UUID().uuidString)"))
        let files = [
            burstTestFile("a.ARW", seconds: 0),
            burstTestFile("b.ARW", seconds: 0.3),
            burstTestFile("c.ARW", seconds: 0.6)
        ]
        viewModel.selectedSource = catalog
        viewModel.files = files
        viewModel.filteredFiles = files
        viewModel.cullingModel = CullingModel(saveDelayNanoseconds: 0, saveHandler: { _ in })
        viewModel.similarityModel.burstGroups = [BurstGroup(id: 0, fileIDs: files.map(\.id))]
        viewModel.similarityModel.burstGroupLookup = Dictionary(uniqueKeysWithValues: files.map { ($0.id, 0) })
        viewModel.burstAnalysisResults[0] = BurstAnalysisResult(
            groupID: 0,
            fileIDs: files.map(\.id),
            candidates: [
                BurstCandidateScore(fileID: files[1].id, overallScore: 0.9, sharpnessComponent: 0.9, focusPointComponent: 0.7, saliencyComponent: 0.7, metadataComponent: 0.7, confidence: .high, reasons: [], cautions: []),
                BurstCandidateScore(fileID: files[2].id, overallScore: 0.7, sharpnessComponent: 0.7, focusPointComponent: 0.7, saliencyComponent: 0.7, metadataComponent: 0.7, confidence: .high, reasons: [], cautions: []),
                BurstCandidateScore(fileID: files[0].id, overallScore: 0.2, sharpnessComponent: 0.2, focusPointComponent: 0.7, saliencyComponent: 0.7, metadataComponent: 0.7, confidence: .high, reasons: [], cautions: [])
            ],
            recommendedFileID: files[1].id,
            secondBestFileID: files[2].id,
            confidence: .high,
            reviewState: .none,
            isSafeForOneClickCulling: true,
            reasons: [],
            cautions: [],
        )

        viewModel.keepBestInGroup(from: files)
        #expect(viewModel.getRating(for: files[1]) == 3)
        #expect(viewModel.getRating(for: files[0]) == -1)
        #expect(viewModel.getRating(for: files[2]) == -1)

        viewModel.undoLastBurstAction()
        #expect(viewModel.getRating(for: files[0]) == 0)
        #expect(viewModel.getRating(for: files[1]) == 0)

        viewModel.keepTopTwoInGroup(from: files)
        #expect(viewModel.getRating(for: files[1]) == 3)
        #expect(viewModel.getRating(for: files[2]) == 2)
        #expect(viewModel.getRating(for: files[0]) == -1)
    }

    @Test(.tags(.critical))
    func `manual burst winner overrides keep best and survives undo`() {
        let viewModel = RawCullViewModel()
        let catalog = ARWSourceCatalog(name: "Catalog", url: URL(fileURLWithPath: "/tmp/catalog-\(UUID().uuidString)"))
        let files = [
            burstTestFile("a.ARW", seconds: 0),
            burstTestFile("b.ARW", seconds: 0.3),
            burstTestFile("c.ARW", seconds: 0.6)
        ]
        viewModel.selectedSource = catalog
        viewModel.files = files
        viewModel.filteredFiles = files
        viewModel.cullingModel = CullingModel(saveDelayNanoseconds: 0, saveHandler: { _ in })
        viewModel.similarityModel.burstGroups = [BurstGroup(id: 0, fileIDs: files.map(\.id))]
        viewModel.similarityModel.burstGroupLookup = Dictionary(uniqueKeysWithValues: files.map { ($0.id, 0) })
        viewModel.burstAnalysisResults[0] = BurstAnalysisResult(
            groupID: 0,
            fileIDs: files.map(\.id),
            candidates: [
                BurstCandidateScore(fileID: files[1].id, overallScore: 0.9, sharpnessComponent: 0.9, focusPointComponent: 0.7, saliencyComponent: 0.7, metadataComponent: 0.7, confidence: .high, reasons: [], cautions: []),
                BurstCandidateScore(fileID: files[2].id, overallScore: 0.7, sharpnessComponent: 0.7, focusPointComponent: 0.7, saliencyComponent: 0.7, metadataComponent: 0.7, confidence: .high, reasons: [], cautions: []),
                BurstCandidateScore(fileID: files[0].id, overallScore: 0.2, sharpnessComponent: 0.2, focusPointComponent: 0.7, saliencyComponent: 0.7, metadataComponent: 0.7, confidence: .high, reasons: [], cautions: [])
            ],
            recommendedFileID: files[1].id,
            secondBestFileID: files[2].id,
            confidence: .high,
            reviewState: .none,
            isSafeForOneClickCulling: true,
            reasons: [],
            cautions: [],
        )

        viewModel.setManualBurstWinner(files[2], in: files)
        #expect(viewModel.burstAnalysisResults[0]?.recommendedFileID == files[2].id)
        #expect(viewModel.burstAnalysisResults[0]?.secondBestFileID == files[1].id)
        #expect(viewModel.burstAnalysisResults[0]?.reviewState == .manualWinnerOverride)

        viewModel.keepBestInGroup(from: files)
        #expect(viewModel.getRating(for: files[2]) == 3)
        #expect(viewModel.getRating(for: files[0]) == -1)
        #expect(viewModel.getRating(for: files[1]) == -1)
        #expect(viewModel.burstAnalysisResults[0]?.reviewState == .manualWinnerOverride)

        viewModel.undoLastBurstAction()
        #expect(viewModel.getRating(for: files[2]) == 0)
        #expect(viewModel.cullingModel.burstWinnerOverrides(in: catalog.url).first?.winnerFileName == "c.ARW")
    }

    @Test(.tags(.critical))
    func `manual burst winner reattaches to regrouped winner group`() {
        let viewModel = RawCullViewModel()
        let catalog = ARWSourceCatalog(name: "Catalog", url: URL(fileURLWithPath: "/tmp/catalog-\(UUID().uuidString)"))
        let files = [
            burstTestFile("a.ARW", seconds: 0),
            burstTestFile("b.ARW", seconds: 0.3),
            burstTestFile("c.ARW", seconds: 0.6)
        ]
        viewModel.selectedSource = catalog
        viewModel.files = files
        viewModel.filteredFiles = files
        viewModel.cullingModel = CullingModel(saveDelayNanoseconds: 0, saveHandler: { _ in })
        viewModel.cullingModel.upsertBurstWinnerOverride(
            BurstWinnerOverride(
                winnerFileName: "c.ARW",
                winnerFileID: files[2].id,
                memberFileNames: files.map(\.name),
                dateApplied: "19 May 2026 12:00",
            ),
            in: catalog.url,
        )
        viewModel.similarityModel.burstGroups = [
            BurstGroup(id: 0, fileIDs: [files[0].id, files[1].id]),
            BurstGroup(id: 1, fileIDs: [files[2].id])
        ]
        viewModel.similarityModel.burstGroupLookup = [
            files[0].id: 0,
            files[1].id: 0,
            files[2].id: 1
        ]
        viewModel.burstAnalysisResults[0] = BurstAnalysisResult(
            groupID: 0,
            fileIDs: [files[0].id, files[1].id],
            candidates: [],
            recommendedFileID: files[1].id,
            secondBestFileID: files[0].id,
            confidence: .medium,
            reviewState: .none,
            isSafeForOneClickCulling: false,
            reasons: [],
            cautions: [],
        )
        viewModel.burstAnalysisResults[1] = BurstAnalysisResult(
            groupID: 1,
            fileIDs: [files[2].id],
            candidates: [
                BurstCandidateScore(fileID: files[2].id, overallScore: 0.4, sharpnessComponent: 0.4, focusPointComponent: 0.7, saliencyComponent: 0.7, metadataComponent: 0.7, confidence: .low, reasons: [], cautions: [])
            ],
            recommendedFileID: nil,
            secondBestFileID: nil,
            confidence: .low,
            reviewState: .none,
            isSafeForOneClickCulling: false,
            reasons: [],
            cautions: [],
        )

        viewModel.reapplyManualBurstWinnerOverridesForCurrentGroups()

        #expect(viewModel.burstAnalysisResults[0]?.reviewState == BurstReviewState.none)
        #expect(viewModel.burstAnalysisResults[1]?.recommendedFileID == files[2].id)
        #expect(viewModel.burstAnalysisResults[1]?.reviewState == .manualWinnerOverride)
    }

    @Test(.tags(.critical))
    func `clear loaded burst analysis for reindex discards stale analysis state`() {
        let viewModel = RawCullViewModel()
        let files = [
            burstTestFile("a.ARW", seconds: 0),
            burstTestFile("b.ARW", seconds: 0.3)
        ]
        viewModel.files = files
        viewModel.filteredFiles = files
        viewModel.comparisonFileIDs = files.map(\.id)
        viewModel.activeBurstComparisonGroupID = 0
        viewModel.lastBurstUndoEntry = BurstUndoEntry(groupID: 0, previousRatingsByFileName: ["a.ARW": 3])
        viewModel.burstAnalysisProgress = BurstAnalysisProgress(step: .ranking)
        viewModel.burstReviewStates = [0: .decisionApplied]
        viewModel.burstAnalysisResults[0] = BurstAnalysisResult(
            groupID: 0,
            fileIDs: files.map(\.id),
            candidates: [],
            recommendedFileID: files[0].id,
            secondBestFileID: files[1].id,
            confidence: .high,
            reviewState: .decisionApplied,
            isSafeForOneClickCulling: true,
            reasons: [],
            cautions: [],
        )
        viewModel.sharpnessModel.scores = [files[0].id: 0.9]
        viewModel.sharpnessModel.saliencyInfo = [files[0].id: SaliencyInfo(subjectLabel: "bird")]
        viewModel.sharpnessModel.sortBySharpness = true
        viewModel.similarityModel.embeddings = [files[0].id: Data([1])]
        viewModel.similarityModel.distances = [files[1].id: 0.2]
        viewModel.similarityModel.burstGroups = [BurstGroup(id: 0, fileIDs: files.map(\.id))]
        viewModel.similarityModel.burstGroupLookup = Dictionary(uniqueKeysWithValues: files.map { ($0.id, 0) })
        viewModel.similarityModel.burstBoundaryEvidence = [
            BurstBoundaryEvidence(
                previousID: files[0].id,
                currentID: files[1].id,
                visualDistance: 0.2,
                timeGapSeconds: 0.3,
                focalLengthDelta: 0,
                exposureChanged: false,
                cameraChanged: false,
                lensChanged: false,
                startsNewGroup: false,
                reasons: [],
            )
        ]
        viewModel.similarityModel.burstModeActive = true

        viewModel.clearLoadedBurstAnalysisForReindex()

        #expect(viewModel.burstAnalysisResults.isEmpty)
        #expect(viewModel.burstReviewStates.isEmpty)
        #expect(viewModel.activeBurstComparisonGroupID == nil)
        #expect(viewModel.lastBurstUndoEntry == nil)
        #expect(viewModel.comparisonFileIDs.isEmpty)
        #expect(viewModel.burstAnalysisProgress == BurstAnalysisProgress())
        #expect(viewModel.sharpnessModel.scores.isEmpty)
        #expect(viewModel.sharpnessModel.saliencyInfo.isEmpty)
        #expect(viewModel.sharpnessModel.sortBySharpness == false)
        #expect(viewModel.similarityModel.embeddings.isEmpty)
        #expect(viewModel.similarityModel.distances.isEmpty)
        #expect(viewModel.similarityModel.burstGroups.isEmpty)
        #expect(viewModel.similarityModel.burstGroupLookup.isEmpty)
        #expect(viewModel.similarityModel.burstBoundaryEvidence.isEmpty)
        #expect(viewModel.similarityModel.burstModeActive == false)
    }
}

@Suite("BurstAnalysisCache")
@MainActor
struct BurstAnalysisCacheTests {
    @Test(.tags(.smoke))
    func `cache round trip and invalidation`() async {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("rawcull-burst-cache-\(UUID().uuidString)", isDirectory: true)
        let cache = BurstAnalysisCache(cacheDirectory: directory)
        let catalog = URL(fileURLWithPath: "/tmp/catalog-\(UUID().uuidString)")
        let files = [burstTestFile("a.ARW", seconds: 0), burstTestFile("b.ARW", seconds: 0.5)]
        let snapshot = BurstAnalysisCacheSnapshot(
            schemaVersion: BurstAnalysisCache.schemaVersion,
            algorithmVersion: BurstGroupingConfig.algorithmVersion,
            catalogPath: catalog.path,
            thumbnailMaxPixelSize: 512,
            files: files.map { BurstAnalysisCacheFile(id: $0.id, path: $0.url.path, size: $0.size, modificationDate: $0.dateModified) },
            embeddings: [files[0].id: Data([1, 2, 3])],
            sharpnessScores: [files[0].id: 0.8],
            saliencyInfo: [files[0].id: SaliencyInfo(subjectLabel: "bird")],
            groups: [BurstGroup(id: 0, fileIDs: files.map(\.id))],
            boundaryEvidence: [],
            results: [],
            reviewStates: [0: .decisionApplied],
        )

        await cache.save(snapshot, catalog: catalog)
        let loaded = await cache.load(catalog: catalog, files: files, thumbnailMaxPixelSize: 512)
        #expect(loaded?.reviewStates[0] == .decisionApplied)

        await cache.delete(catalog: catalog)
        let deleted = await cache.load(catalog: catalog, files: files, thumbnailMaxPixelSize: 512)
        #expect(deleted == nil)

        await cache.save(snapshot, catalog: catalog)
        let changed = [burstTestFile("a.ARW", seconds: 0, size: 999), files[1]]
        let invalid = await cache.load(catalog: catalog, files: changed, thumbnailMaxPixelSize: 512)
        #expect(invalid == nil)
    }
}
