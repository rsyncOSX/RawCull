import Foundation
@testable import RawCull
import RawCullCore
import Testing

private func makeGridTestFile(_ name: String, id: UUID = UUID()) -> FileItem {
    FileItem(
        id: id,
        url: URL(fileURLWithPath: "/tmp/\(name)"),
        name: name,
        size: 1,
        dateModified: Date(timeIntervalSince1970: 0),
        exifData: nil,
        afFocusNormalized: nil,
    )
}

private func makeBurstResult(
    groupID: Int,
    fileIDs: [FileItem.ID],
    recommendedFileID: FileItem.ID,
    reviewState: BurstReviewState = .algorithmReviewed,
) -> BurstAnalysisResult {
    BurstAnalysisResult(
        groupID: groupID,
        fileIDs: fileIDs,
        candidates: [
            BurstCandidateScore(
                fileID: recommendedFileID,
                overallScore: 0.9,
                sharpnessComponent: 0.9,
                burstRelativeSharpnessComponent: nil,
                focusPointComponent: 0.0,
                saliencyComponent: 0.0,
                metadataComponent: 0.0,
                confidence: .medium,
                reasons: [],
                cautions: [],
            )
        ],
        recommendedFileID: recommendedFileID,
        secondBestFileID: nil,
        confidence: .medium,
        reviewState: reviewState,
        isSafeForOneClickCulling: true,
        reasons: [],
        cautions: [],
    )
}

@MainActor
@Suite("CullingGridCoordinator")
struct CullingGridCoordinatorTests {
    @Test(.tags(.smoke))
    func `normal command and shift selection preserve existing grid behavior`() {
        let ids = [UUID(), UUID(), UUID(), UUID()]
        let initial = CullingGridSelectionState(selectedFileID: ids[1], selectedFileIDs: [])

        let normal = CullingGridSelectionCoordinator.toggleSelection(
            fileID: ids[2],
            state: initial,
            visibleIDs: ids,
            modifier: .normal,
        )
        #expect(normal.selectedFileID == ids[2])
        #expect(normal.selectedFileIDs.isEmpty)

        let command = CullingGridSelectionCoordinator.toggleSelection(
            fileID: ids[3],
            state: normal,
            visibleIDs: ids,
            modifier: .command,
        )
        #expect(command.selectedFileID == ids[3])
        #expect(command.selectedFileIDs == [ids[2], ids[3]])

        let shift = CullingGridSelectionCoordinator.toggleSelection(
            fileID: ids[0],
            state: command,
            visibleIDs: ids,
            modifier: .shift,
        )
        #expect(shift.selectedFileID == ids[3])
        #expect(shift.selectedFileIDs == Set(ids[0 ... 3]))
    }

    @Test(.tags(.smoke))
    func `badge selection counts and matching ids come from burst and saliency labels`() {
        let best = makeGridTestFile("best.ARW")
        let subject = makeGridTestFile("subject.ARW")
        let result = makeBurstResult(
            groupID: 7,
            fileIDs: [best.id, subject.id],
            recommendedFileID: best.id,
        )

        let items = CullingGridSelectionCoordinator.badgeSelectionItems(
            visibleFiles: [best, subject],
            burstGroupLookup: [best.id: 7, subject.id: 7],
            burstAnalysisResults: [7: result],
            saliencyInfo: [subject.id: SaliencyInfo(subjectLabel: "person")],
        )

        let countsByLabel = Dictionary(uniqueKeysWithValues: items.map { ($0.label, $0.count) })
        #expect(countsByLabel["Suggested"] == 1)
        #expect(countsByLabel["person"] == 1)

        let matching = CullingGridSelectionCoordinator.matchingIDs(
            forBadge: "person",
            visibleFiles: [best, subject],
            burstGroupLookup: [best.id: 7, subject.id: 7],
            burstAnalysisResults: [7: result],
            saliencyInfo: [subject.id: SaliencyInfo(subjectLabel: "person")],
        )
        #expect(matching == [subject.id])
    }

    @Test(.tags(.smoke))
    func `render cache filters visible burst files and marks manual winner`() {
        let winner = makeGridTestFile("winner.ARW")
        let hidden = makeGridTestFile("hidden.ARW")
        let visible = makeGridTestFile("visible.ARW")
        let group = BurstGroup(id: 3, fileIDs: [winner.id, hidden.id, visible.id])
        let result = makeBurstResult(
            groupID: 3,
            fileIDs: group.fileIDs,
            recommendedFileID: winner.id,
            reviewState: .manualWinnerOverride,
        )

        let cache = CullingGridRenderCache.rebuild(
            files: [winner, visible],
            burstGroups: [group],
            scores: [winner.id: 0.7, visible.id: 0.4],
            maxScore: 0.7,
            burstAnalysisResults: [3: result],
        )

        #expect(cache.visibleBurstGroups.map(\.id) == [3])
        #expect(cache.visibleBurstGroups.first?.files.map(\.id) == [winner.id, visible.id])
        #expect(cache.hasSharpnessScoresSnapshot)
        #expect(cache.bestInGroup[3]?.fileName == "winner.ARW")
        #expect(cache.bestInGroup[3]?.percent == 100)
        #expect(cache.bestInGroup[3]?.isManualWinner == true)
    }

    @Test(.tags(.smoke))
    func `thumbnail source flags are pruned and initialized for comparison files`() {
        let first = makeGridTestFile("first.ARW")
        let second = makeGridTestFile("second.ARW")
        let staleID = UUID()

        let flags = ComparisonGridImageCoordinator.syncSourceStates(
            for: [first, second],
            sourceFlags: [first.id: true, staleID: true],
        )

        #expect(flags == [first.id: true, second.id: false])
    }
}
