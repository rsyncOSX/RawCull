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

    @Test(.tags(.smoke))
    func `medium confidence recommendation is not safe for one click culling`() {
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
            scores: [files[0].id: 0.80, files[1].id: 0.70, files[2].id: 0.20],
            maxScore: 1.0,
            saliencyInfo: [:],
            boundaryEvidence: evidence,
        )

        #expect(result.confidence == .medium)
        #expect(!result.isSafeForOneClickCulling)
    }

    @Test(.tags(.smoke))
    func `confidence titles use conservative recommendation copy`() {
        #expect(BurstDecisionConfidence.high.title == "High confidence")
        #expect(BurstDecisionConfidence.medium.title == "Review recommended")
        #expect(BurstDecisionConfidence.low.title == "Low confidence")
    }
}

@Suite("BurstGroupPresentation")
@MainActor
struct BurstGroupPresentationTests {
    @Test(.tags(.smoke))
    func `high confidence presentation recommends keeping full order frame`() {
        let files = [
            burstTestFile("a.ARW", seconds: 0),
            burstTestFile("b.ARW", seconds: 0.3),
            burstTestFile("c.ARW", seconds: 0.6)
        ]
        let result = presentationResult(
            files: files,
            recommended: files[1].id,
            confidence: .high,
            reasons: ["Sharpest candidate leads", "Exposure stable", "Subject stable", "Best is clearly ahead"],
        )

        let presentation = BurstGroupPresentation.make(result: result, files: files)

        #expect(presentation.decision == "Keep frame 2")
        #expect(presentation.confidenceLabel == "High confidence")
        #expect(presentation.primaryActionTitle == "Keep best")
        #expect(presentation.primaryAction == .keepBest)
        #expect(presentation.recommendedBadge == "Best")
        #expect(presentation.explanation == "Sharpest frame · stable exposure · same subject")
    }

    @Test(.tags(.smoke))
    func `medium confidence presentation uses review copy and one caution`() {
        let files = [
            burstTestFile("a.ARW", seconds: 0),
            burstTestFile("b.ARW", seconds: 0.3),
            burstTestFile("c.ARW", seconds: 0.6)
        ]
        let result = presentationResult(
            files: files,
            recommended: files[2].id,
            confidence: .medium,
            reasons: ["Sharpest candidate leads", "Exposure stable"],
            cautions: ["Top two are close", "Similarity spread is wider"],
        )

        let presentation = BurstGroupPresentation.make(result: result, files: files)

        #expect(presentation.decision == "Suggested: frame 3")
        #expect(presentation.confidenceLabel == "Review recommended")
        #expect(presentation.primaryActionTitle == "Compare top 2")
        #expect(presentation.primaryAction == .compare)
        #expect(presentation.recommendedBadge == "Suggested")
        #expect(presentation.explanation == "Sharpest frame · stable exposure · top frames are close")
    }

    @Test(.tags(.smoke))
    func `low confidence presentation asks for review without inventing a frame`() {
        let files = [
            burstTestFile("a.ARW", seconds: 0),
            burstTestFile("b.ARW", seconds: 0.3)
        ]
        let result = presentationResult(
            files: files,
            recommended: nil,
            confidence: .low,
            cautions: ["Sharpness scores missing", "Top two are close"],
        )

        let presentation = BurstGroupPresentation.make(result: result, files: files)

        #expect(presentation.decision == "Needs review")
        #expect(presentation.confidenceLabel == "Low confidence")
        #expect(presentation.primaryActionTitle == "Open burst")
        #expect(presentation.primaryAction == .compare)
        #expect(presentation.recommendedBadge == nil)
        #expect(presentation.explanation == "sharpness unavailable · top frames are close")
    }

    @Test(.tags(.smoke))
    func `manual winner presentation takes precedence over confidence`() {
        let files = [
            burstTestFile("a.ARW", seconds: 0),
            burstTestFile("b.ARW", seconds: 0.3),
            burstTestFile("c.ARW", seconds: 0.6)
        ]
        let result = presentationResult(
            files: files,
            recommended: files[2].id,
            confidence: .high,
            reviewState: .manualWinnerOverride,
            reasons: ["Sharpest candidate leads"],
        )

        let presentation = BurstGroupPresentation.make(result: result, files: files)

        #expect(presentation.decision == "Manual winner: frame 3")
        #expect(presentation.confidenceLabel == "Manual")
        #expect(presentation.primaryActionTitle == "Open burst")
        #expect(presentation.recommendedBadge == "Manual")
    }

    @Test(.tags(.smoke))
    func `applied presentation preserves confidence decision and exposes applied state`() {
        let files = [
            burstTestFile("a.ARW", seconds: 0),
            burstTestFile("b.ARW", seconds: 0.3)
        ]
        let result = presentationResult(
            files: files,
            recommended: files[0].id,
            confidence: .high,
            reviewState: .decisionApplied,
            reasons: ["Sharpest candidate leads"],
        )

        let presentation = BurstGroupPresentation.make(result: result, files: files)

        #expect(presentation.decision == "Keep frame 1")
        #expect(presentation.confidenceLabel == "High confidence")
        #expect(presentation.showsAppliedStatus)
    }

    @Test(.tags(.smoke))
    func `thumbnail recommendation labels only apply to recommended candidate`() throws {
        let files = [
            burstTestFile("a.ARW", seconds: 0),
            burstTestFile("b.ARW", seconds: 0.3)
        ]
        let result = presentationResult(
            files: files,
            recommended: files[1].id,
            confidence: .medium,
        )
        let recommended = try #require(result.candidates.first { $0.fileID == files[1].id })
        let other = try #require(result.candidates.first { $0.fileID == files[0].id })

        #expect(BurstGroupPresentation.recommendationBadge(for: recommended, in: result) == "Suggested")
        #expect(BurstGroupPresentation.recommendationBadge(for: other, in: result) == nil)
    }

    private func presentationResult(
        files: [FileItem],
        recommended: UUID?,
        confidence: BurstDecisionConfidence,
        reviewState: BurstReviewState = .none,
        reasons: [String] = [],
        cautions: [String] = [],
    ) -> BurstAnalysisResult {
        BurstAnalysisResult(
            groupID: 0,
            fileIDs: files.map(\.id),
            candidates: files.map {
                BurstCandidateScore(
                    fileID: $0.id,
                    overallScore: $0.id == recommended ? 0.9 : 0.4,
                    sharpnessComponent: $0.id == recommended ? 0.9 : 0.4,
                    focusPointComponent: 0.7,
                    saliencyComponent: 0.7,
                    metadataComponent: 0.7,
                    confidence: confidence,
                    reasons: [],
                    cautions: [],
                )
            },
            recommendedFileID: recommended,
            secondBestFileID: files.first { $0.id != recommended }?.id,
            confidence: confidence,
            reviewState: reviewState,
            isSafeForOneClickCulling: confidence == .high,
            reasons: reasons,
            cautions: cautions,
        )
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
        viewModel.sharpnessModel.scores = [
            files[0].id: 0.2,
            files[1].id: 0.9,
            files[2].id: 0.7
        ]
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
        viewModel.sharpnessModel.scores = [
            files[0].id: 0.2,
            files[1].id: 0.9,
            files[2].id: 0.7
        ]
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
        #expect(viewModel.getRating(for: files[2]) == 3)
        #expect(viewModel.getRating(for: files[0]) == 0)
        #expect(viewModel.getRating(for: files[1]) == 0)
        #expect(viewModel.burstAnalysisResults[0]?.recommendedFileID == files[2].id)
        #expect(viewModel.burstAnalysisResults[0]?.secondBestFileID == files[1].id)
        #expect(viewModel.burstAnalysisResults[0]?.reviewState == .manualWinnerOverride)

        viewModel.keepBestInGroup(from: files)
        #expect(viewModel.getRating(for: files[2]) == 3)
        #expect(viewModel.getRating(for: files[0]) == -1)
        #expect(viewModel.getRating(for: files[1]) == -1)
        #expect(viewModel.burstAnalysisResults[0]?.reviewState == .manualWinnerOverride)

        viewModel.undoLastBurstAction()
        #expect(viewModel.getRating(for: files[0]) == 0)
        #expect(viewModel.getRating(for: files[1]) == 0)
        #expect(viewModel.getRating(for: files[2]) == 3)
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
                memberFileNames: files.map(\.name),
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
    func `unsafe burst actions do not apply automatic ratings`() {
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
        viewModel.sharpnessModel.scores = [
            files[0].id: 0.2,
            files[1].id: 0.9,
            files[2].id: 0.7
        ]
        viewModel.similarityModel.burstGroups = [BurstGroup(id: 0, fileIDs: files.map(\.id))]
        viewModel.similarityModel.burstGroupLookup = Dictionary(uniqueKeysWithValues: files.map { ($0.id, 0) })
        viewModel.burstAnalysisResults[0] = BurstAnalysisResult(
            groupID: 0,
            fileIDs: files.map(\.id),
            candidates: [
                BurstCandidateScore(fileID: files[1].id, overallScore: 0.9, sharpnessComponent: 0.9, focusPointComponent: 0.7, saliencyComponent: 0.7, metadataComponent: 0.7, confidence: .medium, reasons: [], cautions: []),
                BurstCandidateScore(fileID: files[2].id, overallScore: 0.7, sharpnessComponent: 0.7, focusPointComponent: 0.7, saliencyComponent: 0.7, metadataComponent: 0.7, confidence: .medium, reasons: [], cautions: []),
                BurstCandidateScore(fileID: files[0].id, overallScore: 0.2, sharpnessComponent: 0.2, focusPointComponent: 0.7, saliencyComponent: 0.7, metadataComponent: 0.7, confidence: .medium, reasons: [], cautions: [])
            ],
            recommendedFileID: files[1].id,
            secondBestFileID: files[2].id,
            confidence: .medium,
            reviewState: .none,
            isSafeForOneClickCulling: false,
            reasons: [],
            cautions: [],
        )

        #expect(!viewModel.canApplyOneClickCulling(to: files))

        viewModel.keepBestInGroup(from: files)
        #expect(viewModel.getRating(for: files[0]) == 0)
        #expect(viewModel.getRating(for: files[1]) == 0)
        #expect(viewModel.getRating(for: files[2]) == 0)

        viewModel.keepTopTwoInGroup(from: files)
        #expect(viewModel.getRating(for: files[0]) == 0)
        #expect(viewModel.getRating(for: files[1]) == 0)
        #expect(viewModel.getRating(for: files[2]) == 0)
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
        #expect(viewModel.sharpnessModel.breakdowns.isEmpty)
        #expect(viewModel.sharpnessModel.sortBySharpness == false)
        #expect(viewModel.similarityModel.embeddings.isEmpty)
        #expect(viewModel.similarityModel.distances.isEmpty)
        #expect(viewModel.similarityModel.burstGroups.isEmpty)
        #expect(viewModel.similarityModel.burstGroupLookup.isEmpty)
        #expect(viewModel.similarityModel.burstBoundaryEvidence.isEmpty)
        #expect(viewModel.similarityModel.burstModeActive == false)
    }
}

@Suite("Sharpness comparison summary")
@MainActor
struct SharpnessComparisonSummaryTests {
    @Test(.tags(.smoke))
    func `subject breakdown drives comparison rank and winner deltas`() throws {
        let winnerID = UUID()
        let rejectedID = UUID()
        let thirdID = UUID()
        let breakdowns = [
            winnerID: comparisonBreakdown(global: 0.61, subject: 0.78),
            rejectedID: comparisonBreakdown(global: 0.64, subject: 0.66),
            thirdID: comparisonBreakdown(global: 0.40, subject: 0.30)
        ]

        let context = try #require(SharpnessComparisonSummary.context(
            for: rejectedID,
            fileIDs: [winnerID, rejectedID, thirdID],
            scores: [winnerID: 0.5, rejectedID: 0.9, thirdID: 0.4],
            breakdowns: breakdowns,
            winnerID: winnerID,
        ))

        #expect(context.rankTitle == "#2 of 3 in subject sharpness")
        #expect(context.deltaParts == [
            SharpnessComparisonDeltaPart(label: "Subject", value: -12),
            SharpnessComparisonDeltaPart(label: "Global", value: 3)
        ])
        #expect(context.deltaParts.map(\.title) == ["Subject -12", "Global +3"])
    }

    @Test(.tags(.smoke))
    func `zero winner delta keeps neutral comparison value`() throws {
        let winnerID = UUID()
        let tiedID = UUID()
        let breakdowns = [
            winnerID: comparisonBreakdown(global: 0.55, subject: 0.55),
            tiedID: comparisonBreakdown(global: 0.55, subject: 0.55)
        ]

        let context = try #require(SharpnessComparisonSummary.context(
            for: tiedID,
            fileIDs: [winnerID, tiedID],
            scores: [winnerID: 0.55, tiedID: 0.55],
            breakdowns: breakdowns,
            winnerID: winnerID,
        ))

        #expect(context.rankTitle.hasSuffix("of 2 in subject sharpness"))
        #expect(context.deltaParts == [
            SharpnessComparisonDeltaPart(label: "Subject", value: 0),
            SharpnessComparisonDeltaPart(label: "Global", value: 0)
        ])
        #expect(context.deltaParts.map(\.title) == ["Subject 0", "Global 0"])
    }

    @Test(.tags(.smoke))
    func `scalar score drives comparison rank when breakdowns are absent`() throws {
        let firstID = UUID()
        let secondID = UUID()

        let context = try #require(SharpnessComparisonSummary.context(
            for: secondID,
            fileIDs: [firstID, secondID],
            scores: [firstID: 0.7, secondID: 0.9],
            breakdowns: [:],
            winnerID: firstID,
        ))

        #expect(context.rankTitle == "#1 of 2 in sharpness")
        #expect(context.deltaParts.isEmpty)
    }
}

private func comparisonBreakdown(global: Float, subject: Float) -> SharpnessBreakdown {
    SharpnessBreakdown(
        finalScore: subject,
        globalScore: global,
        subjectScore: subject,
        afPointScore: nil,
        blurGateSigma: 0.03,
        subjectLabel: nil,
        subjectConfidence: nil,
        focusFailureKind: .none,
    )
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
