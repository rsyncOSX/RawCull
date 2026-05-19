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

        let changed = [burstTestFile("a.ARW", seconds: 0, size: 999), files[1]]
        let invalid = await cache.load(catalog: catalog, files: changed, thumbnailMaxPixelSize: 512)
        #expect(invalid == nil)
    }
}
