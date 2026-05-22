import Foundation
@testable import RawCull
import Testing

private func reviewQueueFile(
    _ name: String,
    seconds: TimeInterval = 0,
) -> FileItem {
    FileItem(
        url: URL(fileURLWithPath: "/tmp/\(name)"),
        name: name,
        size: 1,
        dateModified: Date(timeIntervalSince1970: seconds),
        exifData: ExifMetadata(
            shutterSpeed: "1/1000",
            focalLength: "100mm",
            aperture: "f/5.6",
            apertureValue: 5.6,
            iso: "ISO 400",
            isoValue: 400,
            camera: "ILCE-1",
            lensModel: "Lens",
            rawFileType: nil,
            rawSizeClass: nil,
            pixelWidth: nil,
            pixelHeight: nil,
        ),
        afFocusNormalized: nil,
    )
}

private func reviewQueueBurstResult(
    groupID: Int,
    fileIDs: [UUID],
    confidence: BurstDecisionConfidence,
    reviewState: BurstReviewState = .none,
) -> BurstAnalysisResult {
    BurstAnalysisResult(
        groupID: groupID,
        fileIDs: fileIDs,
        candidates: fileIDs.map {
            BurstCandidateScore(
                fileID: $0,
                overallScore: 0.5,
                sharpnessComponent: 0.5,
                focusPointComponent: 0.5,
                saliencyComponent: 0.5,
                metadataComponent: 0.5,
                confidence: confidence,
                reasons: [],
                cautions: [],
            )
        },
        recommendedFileID: fileIDs.first,
        secondBestFileID: fileIDs.dropFirst().first,
        confidence: confidence,
        reviewState: reviewState,
        isSafeForOneClickCulling: confidence == .high,
        reasons: ["Close candidates"],
        cautions: [],
    )
}

@MainActor
@Suite("Review Queue")
struct ReviewQueueTests {
    @Test(.tags(.smoke))
    func `low-confidence burst creates one burst queue item`() {
        let files = [reviewQueueFile("a.ARW"), reviewQueueFile("b.ARW")]
        let input = ReviewQueueBuilder.Input(
            catalog: URL(fileURLWithPath: "/tmp/catalog"),
            files: files,
            burstGroups: [BurstGroup(id: 7, fileIDs: files.map(\.id))],
            burstResults: [7: reviewQueueBurstResult(groupID: 7, fileIDs: files.map(\.id), confidence: .low)],
            boundaryEvidence: [],
            sharpnessScores: [:],
            sharpnessWasExpected: false,
            diagnosticIssues: [],
            copyOutput: [],
            persistedStates: [],
        )

        let items = ReviewQueueBuilder().build(input: input)

        #expect(items.count == 1)
        #expect(items.first?.category == .burst)
        #expect(items.first?.severity == .warning)
    }

    @Test(.tags(.smoke))
    func `medium-confidence burst is skipped after user decision`() {
        let files = [reviewQueueFile("a.ARW"), reviewQueueFile("b.ARW")]
        let openInput = ReviewQueueBuilder.Input(
            catalog: URL(fileURLWithPath: "/tmp/catalog"),
            files: files,
            burstGroups: [BurstGroup(id: 1, fileIDs: files.map(\.id))],
            burstResults: [1: reviewQueueBurstResult(groupID: 1, fileIDs: files.map(\.id), confidence: .medium)],
            boundaryEvidence: [],
            sharpnessScores: [:],
            sharpnessWasExpected: false,
            diagnosticIssues: [],
            copyOutput: [],
            persistedStates: [],
        )
        var decidedInput = openInput
        decidedInput.burstResults = [1: reviewQueueBurstResult(groupID: 1, fileIDs: files.map(\.id), confidence: .medium, reviewState: .decisionApplied)]

        #expect(ReviewQueueBuilder().build(input: openInput).count == 1)
        #expect(ReviewQueueBuilder().build(input: decidedInput).isEmpty)
    }

    @Test(.tags(.smoke))
    func `metadata boundary evidence creates metadata review item`() {
        let files = [reviewQueueFile("a.ARW"), reviewQueueFile("b.ARW", seconds: 1)]
        let evidence = BurstBoundaryEvidence(
            previousID: files[0].id,
            currentID: files[1].id,
            visualDistance: 0.1,
            timeGapSeconds: 1,
            focalLengthDelta: 0,
            exposureChanged: true,
            cameraChanged: false,
            lensChanged: false,
            startsNewGroup: false,
            reasons: [],
        )
        let input = ReviewQueueBuilder.Input(
            catalog: URL(fileURLWithPath: "/tmp/catalog"),
            files: files,
            burstGroups: [],
            burstResults: [:],
            boundaryEvidence: [evidence],
            sharpnessScores: [:],
            sharpnessWasExpected: false,
            diagnosticIssues: [],
            copyOutput: [],
            persistedStates: [],
        )

        #expect(ReviewQueueBuilder().build(input: input).first?.category == .metadata)
    }

    @Test(.tags(.smoke))
    func `missing sharpness appears only when scoring was expected`() {
        let files = [reviewQueueFile("a.ARW"), reviewQueueFile("b.ARW")]
        let base = ReviewQueueBuilder.Input(
            catalog: URL(fileURLWithPath: "/tmp/catalog"),
            files: files,
            burstGroups: [],
            burstResults: [:],
            boundaryEvidence: [],
            sharpnessScores: [files[0].id: 0.8],
            sharpnessWasExpected: false,
            diagnosticIssues: [],
            copyOutput: [],
            persistedStates: [],
        )
        var expected = base
        expected.sharpnessWasExpected = true

        #expect(ReviewQueueBuilder().build(input: base).isEmpty)
        #expect(ReviewQueueBuilder().build(input: expected).count == 1)
        #expect(ReviewQueueBuilder().build(input: expected).first?.fileName == "b.ARW")
    }

    @Test(.tags(.smoke))
    func `diagnostic copy duplicate and de-duplication items are generated`() {
        let files = [reviewQueueFile("a.ARW"), reviewQueueFile("a.ARW")]
        let issue = RawFileDiagnosticIssue(
            fileName: "a.ARW",
            category: .parser,
            severity: .warning,
            message: "Sony parser failed",
            recoveryHint: "Open diagnostics.",
        )
        let input = ReviewQueueBuilder.Input(
            catalog: URL(fileURLWithPath: "/tmp/catalog"),
            files: files,
            burstGroups: [],
            burstResults: [:],
            boundaryEvidence: [],
            sharpnessScores: [:],
            sharpnessWasExpected: false,
            diagnosticIssues: [issue, issue],
            copyOutput: ["rsync: failed to open a.ARW: Permission denied"],
            persistedStates: [],
        )

        let items = ReviewQueueBuilder().build(input: input)

        #expect(items.count(where: { $0.category == .parser }) == 1)
        #expect(items.contains { $0.category == .copy })
        #expect(items.contains { $0.category == .catalog })
    }

    @Test(.tags(.smoke))
    func `resolved overlay hides and reopen restores item`() throws {
        let file = reviewQueueFile("a.ARW")
        let catalog = URL(fileURLWithPath: "/tmp/catalog")
        let issue = RawFileDiagnosticIssue(
            fileName: file.name,
            category: .parser,
            severity: .warning,
            message: "Parser failed",
            recoveryHint: "Open diagnostics.",
        )
        let openInput = ReviewQueueBuilder.Input(
            catalog: catalog,
            files: [file],
            burstGroups: [],
            burstResults: [:],
            boundaryEvidence: [],
            sharpnessScores: [:],
            sharpnessWasExpected: false,
            diagnosticIssues: [issue],
            copyOutput: [],
            persistedStates: [],
        )
        let fingerprint = try #require(ReviewQueueBuilder().build(input: openInput).first?.fingerprint)
        var resolvedInput = openInput
        resolvedInput.persistedStates = [
            ReviewQueueItemState(fingerprint: fingerprint, resolutionState: .resolved, resolvedAt: Date())
        ]

        let item = try #require(ReviewQueueBuilder().build(input: resolvedInput).first)
        let viewModel = RawCullViewModel()
        viewModel.reviewQueueItems = [item]

        #expect(item.resolutionState == .resolved)
        #expect(viewModel.visibleReviewQueueItems.isEmpty)
        viewModel.showResolvedReviewQueueItems = true
        #expect(viewModel.visibleReviewQueueItems == [item])
    }

    @Test(.tags(.smoke))
    func `old savedfiles json without reviewQueueStates decodes`() throws {
        let json = """
        {
          "catalog": "file:///tmp/catalog/",
          "dateStart": "today",
          "filerecords": []
        }
        """
        let decoded = try JSONDecoder().decode(DecodeSavedFiles.self, from: Data(json.utf8))
        let saved = SavedFiles(decoded)

        #expect(saved.reviewQueueStates == nil)
        #expect(saved.catalog?.path == "/tmp/catalog")
    }

    @Test(.tags(.smoke))
    func `opening queue item selects file or burst context`() throws {
        let viewModel = RawCullViewModel()
        let catalog = ARWSourceCatalog(name: "Catalog", url: URL(fileURLWithPath: "/tmp/catalog"))
        let files = [reviewQueueFile("a.ARW"), reviewQueueFile("b.ARW")]
        viewModel.selectedSource = catalog
        viewModel.files = files
        viewModel.filteredFiles = files
        viewModel.cullingModel = CullingModel(saveDelayNanoseconds: 0, saveHandler: { _ in })
        viewModel.similarityModel.burstGroups = [BurstGroup(id: 3, fileIDs: files.map(\.id))]
        viewModel.similarityModel.burstGroupLookup = Dictionary(uniqueKeysWithValues: files.map { ($0.id, 3) })

        let input = ReviewQueueBuilder.Input(
            catalog: catalog.url,
            files: files,
            burstGroups: viewModel.similarityModel.burstGroups,
            burstResults: [3: reviewQueueBurstResult(groupID: 3, fileIDs: files.map(\.id), confidence: .low)],
            boundaryEvidence: [],
            sharpnessScores: [:],
            sharpnessWasExpected: false,
            diagnosticIssues: [],
            copyOutput: [],
            persistedStates: [],
        )
        let burstItem = try #require(ReviewQueueBuilder().build(input: input).first)

        viewModel.openReviewQueueItem(burstItem)

        #expect(viewModel.mainViewMode == .comparisonGrid)
        #expect(viewModel.activeBurstComparisonGroupID == 3)
        #expect(viewModel.selectedFileID == files[0].id)
    }
}
