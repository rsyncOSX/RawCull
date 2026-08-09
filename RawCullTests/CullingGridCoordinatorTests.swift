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

private func makeReviewQueueResult(
    groupID: Int,
    fileIDs: [FileItem.ID] = [UUID(), UUID()],
    confidence: BurstDecisionConfidence,
    reviewState: BurstReviewState = .none,
    cautions: [String] = [],
    isSafeForOneClickCulling: Bool = false,
) -> BurstAnalysisResult {
    BurstAnalysisResult(
        groupID: groupID,
        fileIDs: fileIDs,
        candidates: [],
        recommendedFileID: fileIDs.first,
        secondBestFileID: nil,
        confidence: confidence,
        reviewState: reviewState,
        isSafeForOneClickCulling: isSafeForOneClickCulling,
        reasons: [],
        cautions: cautions,
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

    @Test
    func `hidden files are pruned from selection and action targets`() {
        let visible = makeGridTestFile("visible.ARW")
        let hidden = makeGridTestFile("hidden.ARW")
        let state = CullingGridSelectionState(
            selectedFileID: hidden.id,
            selectedFileIDs: [visible.id, hidden.id],
        )

        let reconciled = CullingGridSelectionCoordinator.reconcileSelection(
            state,
            visibleIDs: [visible.id],
        )
        let targets = CullingGridSelectionCoordinator.actionFiles(
            requestedIDs: state.selectedFileIDs,
            renderedFiles: [visible],
        )

        #expect(reconciled.selectedFileID == visible.id)
        #expect(reconciled.selectedFileIDs == [visible.id])
        #expect(targets.map(\.id) == [visible.id])
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
    func `render cache filters visible burst files`() {
        let winner = makeGridTestFile("winner.ARW")
        let hidden = makeGridTestFile("hidden.ARW")
        let visible = makeGridTestFile("visible.ARW")
        let group = BurstGroup(id: 3, fileIDs: [winner.id, hidden.id, visible.id])

        let cache = CullingGridRenderCache.rebuild(
            files: [winner, visible],
            burstGroups: [group],
            scores: [winner.id: 0.7, visible.id: 0.4],
        )

        #expect(cache.visibleBurstGroups.map(\.id) == [3])
        #expect(cache.visibleBurstGroups.first?.files.map(\.id) == [winner.id, visible.id])
        #expect(cache.hasSharpnessScoresSnapshot)
    }

    @Test(.tags(.smoke))
    func `burst view lists ranked files in priority order and clean view limits results`() {
        let first = makeGridTestFile("first.ARW")
        let second = makeGridTestFile("second.ARW")
        let third = makeGridTestFile("third.ARW")
        let fourth = makeGridTestFile("fourth.ARW")

        let collapsed = BurstGroupCleanViewPolicy.visibleFiles(
            in: [first, second, third, fourth],
            rankedFileIDs: [third.id, first.id, fourth.id, second.id],
            isCollapsed: true,
        )
        let expanded = BurstGroupCleanViewPolicy.visibleFiles(
            in: [first, second, third, fourth],
            rankedFileIDs: [third.id, first.id, fourth.id, second.id],
            isCollapsed: false,
        )

        #expect(collapsed.map(\.id) == [third.id, first.id, fourth.id])
        #expect(expanded.map(\.id) == [third.id, first.id, fourth.id, second.id])
    }

    @Test
    func `clean view fills missing rankings in original order`() {
        let first = makeGridTestFile("first.ARW")
        let second = makeGridTestFile("second.ARW")
        let third = makeGridTestFile("third.ARW")
        let fourth = makeGridTestFile("fourth.ARW")

        let visible = BurstGroupCleanViewPolicy.visibleFiles(
            in: [first, second, third, fourth],
            rankedFileIDs: [third.id],
            isCollapsed: true,
        )

        #expect(visible.map(\.id) == [third.id, first.id, second.id])
    }

    @Test
    func `render cache key tracks complete membership and score revisions`() {
        let first = makeGridTestFile("first.ARW")
        let middle = makeGridTestFile("middle.ARW")
        let replacement = makeGridTestFile("replacement.ARW")
        let last = makeGridTestFile("last.ARW")
        let group = BurstGroup(id: 1, fileIDs: [first.id, middle.id, last.id])

        func key(
            groups: [BurstGroup] = [group],
            files: [FileItem] = [first, middle, last],
            scoreRevision: Int = 4,
            maxScore: Float = 0.8,
        ) -> CullingGridRenderCacheKey {
            CullingGridRenderCacheKey(
                burstGroups: groups,
                files: files,
                ratingFilter: .all,
                reviewQueueFilter: .all,
                scoresCount: 3,
                scoreRevision: scoreRevision,
                maxScore: maxScore,
                burstAnalysisResults: [:],
            )
        }

        let baseline = key()
        #expect(baseline != key(groups: [BurstGroup(id: 1, fileIDs: [first.id, replacement.id, last.id])]))
        #expect(baseline != key(files: [first, replacement, last]))
        #expect(baseline != key(scoreRevision: 5))
        #expect(baseline != key(maxScore: 0.9))
    }

    @Test
    func `sharpness score revision advances for replacement and incremental mutation`() {
        let model = SharpnessScoringModel()
        let fileID = UUID()
        let initialRevision = model.scoreRevision

        model.scores = [fileID: 0.4]
        let replacementRevision = model.scoreRevision
        model.scores[fileID] = 0.7

        #expect(replacementRevision == initialRevision + 1)
        #expect(model.scoreRevision == replacementRevision + 1)
        #expect(model.maxScore == 0.7)
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

    @Test(.tags(.smoke))
    func `review queue policy includes uncertain groups and excludes completed states`() {
        let low = makeReviewQueueResult(groupID: 1, confidence: .low)
        let caution = makeReviewQueueResult(
            groupID: 2,
            confidence: .high,
            cautions: ["Top two are close"],
            isSafeForOneClickCulling: true,
        )
        let reviewed = makeReviewQueueResult(groupID: 3, confidence: .low, reviewState: .reviewed)
        let deferred = makeReviewQueueResult(groupID: 4, confidence: .low, reviewState: .deferred)
        let applied = makeReviewQueueResult(groupID: 5, confidence: .low, reviewState: .decisionApplied)

        #expect(BurstReviewQueuePolicy.includes(low, filter: .needsReview))
        #expect(BurstReviewQueuePolicy.includes(caution, filter: .needsReview))
        #expect(!BurstReviewQueuePolicy.includes(reviewed, filter: .needsReview))
        #expect(BurstReviewQueuePolicy.includes(deferred, filter: .deferred))
        #expect(!BurstReviewQueuePolicy.includes(applied, filter: .needsReview))

        let counts = BurstReviewQueuePolicy.counts(for: [low, caution, reviewed, deferred, applied])
        #expect(counts.needsReview == 2)
        #expect(counts.deferred == 1)
        #expect(counts.reviewed == 2)
    }

    @Test(.tags(.smoke))
    func `view model filters burst groups by review queue state`() {
        let reviewFile = makeGridTestFile("review.ARW")
        let reviewPeer = makeGridTestFile("review-peer.ARW")
        let deferredFile = makeGridTestFile("deferred.ARW")
        let deferredPeer = makeGridTestFile("deferred-peer.ARW")
        let reviewedFile = makeGridTestFile("reviewed.ARW")
        let reviewedPeer = makeGridTestFile("reviewed-peer.ARW")
        let viewModel = RawCullViewModel()

        viewModel.similarityModel.burstGroups = [
            BurstGroup(id: 1, fileIDs: [reviewFile.id, reviewPeer.id]),
            BurstGroup(id: 2, fileIDs: [deferredFile.id, deferredPeer.id]),
            BurstGroup(id: 3, fileIDs: [reviewedFile.id, reviewedPeer.id])
        ]
        viewModel.burstAnalysisResults = [
            1: makeReviewQueueResult(groupID: 1, fileIDs: [reviewFile.id, reviewPeer.id], confidence: .low),
            2: makeReviewQueueResult(
                groupID: 2,
                fileIDs: [deferredFile.id, deferredPeer.id],
                confidence: .low,
                reviewState: .deferred,
            ),
            3: makeReviewQueueResult(
                groupID: 3,
                fileIDs: [reviewedFile.id, reviewedPeer.id],
                confidence: .low,
                reviewState: .reviewed,
            )
        ]

        viewModel.burstReviewQueueFilter = .needsReview
        #expect(viewModel.filteredBurstGroupsForReviewQueue.map(\.id) == [1])

        viewModel.burstReviewQueueFilter = .deferred
        #expect(viewModel.filteredBurstGroupsForReviewQueue.map(\.id) == [2])

        viewModel.burstReviewQueueFilter = .reviewed
        #expect(viewModel.filteredBurstGroupsForReviewQueue.map(\.id) == [3])
    }

    @Test(.tags(.smoke))
    func `next burst navigation follows the review queue and skips single images`() {
        let first = [makeGridTestFile("first-a.ARW"), makeGridTestFile("first-b.ARW")]
        let single = makeGridTestFile("single.ARW")
        let reviewed = [makeGridTestFile("reviewed-a.ARW"), makeGridTestFile("reviewed-b.ARW")]
        let next = [makeGridTestFile("next-a.ARW"), makeGridTestFile("next-b.ARW")]
        let viewModel = RawCullViewModel()
        viewModel.files = first + [single] + reviewed + next
        viewModel.similarityModel.burstGroups = [
            BurstGroup(id: 1, fileIDs: first.map(\.id)),
            BurstGroup(id: 2, fileIDs: [single.id]),
            BurstGroup(id: 3, fileIDs: reviewed.map(\.id)),
            BurstGroup(id: 4, fileIDs: next.map(\.id))
        ]
        viewModel.burstAnalysisResults = [
            1: makeReviewQueueResult(
                groupID: 1,
                fileIDs: first.map(\.id),
                confidence: .low,
                reviewState: .reviewed,
            ),
            3: makeReviewQueueResult(
                groupID: 3,
                fileIDs: reviewed.map(\.id),
                confidence: .low,
                reviewState: .reviewed,
            ),
            4: makeReviewQueueResult(groupID: 4, fileIDs: next.map(\.id), confidence: .low)
        ]
        viewModel.burstReviewQueueFilter = .needsReview

        #expect(viewModel.advanceToNextBurstGroup(after: 1))
        #expect(viewModel.activeBurstComparisonGroupID == 4)
        #expect(viewModel.selectedFileID == next[0].id)
        #expect(!viewModel.advanceToNextBurstGroup(after: 4))
        #expect(viewModel.activeBurstComparisonGroupID == 4)
    }

    @Test(.tags(.smoke))
    func `next burst navigation defers an unrated current group before advancing`() {
        let current = [makeGridTestFile("current-a.ARW"), makeGridTestFile("current-b.ARW")]
        let next = [makeGridTestFile("next-a.ARW"), makeGridTestFile("next-b.ARW")]
        let viewModel = RawCullViewModel()
        viewModel.files = current + next
        viewModel.similarityModel.burstGroups = [
            BurstGroup(id: 1, fileIDs: current.map(\.id)),
            BurstGroup(id: 2, fileIDs: next.map(\.id))
        ]
        viewModel.burstAnalysisResults = [
            1: makeReviewQueueResult(groupID: 1, fileIDs: current.map(\.id), confidence: .low),
            2: makeReviewQueueResult(groupID: 2, fileIDs: next.map(\.id), confidence: .low)
        ]

        #expect(viewModel.advanceToNextBurstGroup(after: 1))
        #expect(viewModel.burstAnalysisResults[1]?.reviewState == .deferred)
        #expect(viewModel.burstReviewStates[1] == .deferred)
        #expect(viewModel.activeBurstComparisonGroupID == 2)
    }

    @Test(arguments: [-1, 0, 2, 3, 4, 5])
    func `next burst navigation does not defer a group with any rating`(_ rating: Int) {
        let current = [makeGridTestFile("rated-a.ARW"), makeGridTestFile("rated-b.ARW")]
        let next = [makeGridTestFile("next-a.ARW"), makeGridTestFile("next-b.ARW")]
        let viewModel = RawCullViewModel()
        let catalog = ARWSourceCatalog(
            name: "Catalog",
            url: URL(fileURLWithPath: "/tmp/catalog-\(UUID().uuidString)"),
        )
        viewModel.selectedSource = catalog
        viewModel.cullingModel = CullingModel(saveDelayNanoseconds: 0, saveHandler: { _ in })
        viewModel.files = current + next
        viewModel.similarityModel.burstGroups = [
            BurstGroup(id: 1, fileIDs: current.map(\.id)),
            BurstGroup(id: 2, fileIDs: next.map(\.id))
        ]
        viewModel.burstAnalysisResults = [
            1: makeReviewQueueResult(groupID: 1, fileIDs: current.map(\.id), confidence: .low),
            2: makeReviewQueueResult(groupID: 2, fileIDs: next.map(\.id), confidence: .low)
        ]
        viewModel.updateRating(for: current[0], rating: rating)

        #expect(viewModel.advanceToNextBurstGroup(after: 1))
        #expect(viewModel.burstAnalysisResults[1]?.reviewState.rawValue == BurstReviewState.none.rawValue)
        #expect(viewModel.burstReviewStates[1] == nil)
        #expect(viewModel.activeBurstComparisonGroupID == 2)
    }

    @Test
    func `sharpness-only records do not prevent deferring an unrated group`() {
        let current = [makeGridTestFile("scored-a.ARW"), makeGridTestFile("scored-b.ARW")]
        let next = [makeGridTestFile("next-a.ARW"), makeGridTestFile("next-b.ARW")]
        let viewModel = RawCullViewModel()
        let catalog = ARWSourceCatalog(
            name: "Catalog",
            url: URL(fileURLWithPath: "/tmp/catalog-\(UUID().uuidString)"),
        )
        viewModel.selectedSource = catalog
        viewModel.cullingModel = CullingModel(saveDelayNanoseconds: 0, saveHandler: { _ in })
        viewModel.cullingModel.mergeScoringResults(
            [CullingScoringResult(fileName: current[0].name, score: 0.75, saliencySubject: nil)],
            in: catalog.url,
        )
        viewModel.files = current + next
        viewModel.similarityModel.burstGroups = [
            BurstGroup(id: 1, fileIDs: current.map(\.id)),
            BurstGroup(id: 2, fileIDs: next.map(\.id))
        ]
        viewModel.burstAnalysisResults = [
            1: makeReviewQueueResult(groupID: 1, fileIDs: current.map(\.id), confidence: .low),
            2: makeReviewQueueResult(groupID: 2, fileIDs: next.map(\.id), confidence: .low)
        ]

        #expect(viewModel.advanceToNextBurstGroup(after: 1))
        #expect(viewModel.burstAnalysisResults[1]?.reviewState == .deferred)
        #expect(viewModel.activeBurstComparisonGroupID == 2)
    }

    @Test(.tags(.smoke))
    func `burst home counts singleton images and live review states`() {
        let firstSingle = makeGridTestFile("single-one.ARW")
        let secondSingle = makeGridTestFile("single-two.ARW")
        let needsReviewFiles = [makeGridTestFile("needs-one.ARW"), makeGridTestFile("needs-two.ARW")]
        let deferredFiles = [makeGridTestFile("deferred-one.ARW"), makeGridTestFile("deferred-two.ARW")]
        let reviewedFiles = [makeGridTestFile("reviewed-one.ARW"), makeGridTestFile("reviewed-two.ARW")]
        let appliedFiles = [makeGridTestFile("applied-one.ARW"), makeGridTestFile("applied-two.ARW")]
        let viewModel = RawCullViewModel()

        viewModel.similarityModel.burstGroups = [
            BurstGroup(id: 0, fileIDs: [firstSingle.id]),
            BurstGroup(id: 1, fileIDs: needsReviewFiles.map(\.id)),
            BurstGroup(id: 2, fileIDs: deferredFiles.map(\.id)),
            BurstGroup(id: 3, fileIDs: [secondSingle.id]),
            BurstGroup(id: 4, fileIDs: reviewedFiles.map(\.id)),
            BurstGroup(id: 5, fileIDs: appliedFiles.map(\.id))
        ]
        viewModel.burstAnalysisResults = [
            1: makeReviewQueueResult(groupID: 1, fileIDs: needsReviewFiles.map(\.id), confidence: .low),
            2: makeReviewQueueResult(
                groupID: 2,
                fileIDs: deferredFiles.map(\.id),
                confidence: .low,
                reviewState: .deferred,
            ),
            4: makeReviewQueueResult(
                groupID: 4,
                fileIDs: reviewedFiles.map(\.id),
                confidence: .low,
                reviewState: .reviewed,
            ),
            5: makeReviewQueueResult(
                groupID: 5,
                fileIDs: appliedFiles.map(\.id),
                confidence: .high,
                reviewState: .decisionApplied,
                isSafeForOneClickCulling: true,
            )
        ]

        #expect(viewModel.burstGroupsHomeCounts == BurstGroupsHomeCounts(
            singleImages: 2,
            deferred: 1,
            markedReviewed: 1,
            needsReview: 1,
        ))

        viewModel.markBurstGroupReviewed(groupID: 1)

        #expect(viewModel.burstGroupsHomeCounts.markedReviewed == 2)
        #expect(viewModel.burstGroupsHomeCounts.needsReview == 0)
    }

    @Test(.tags(.smoke))
    func `single image category excludes every multi-image burst`() {
        let firstSingle = makeGridTestFile("single-first.ARW")
        let secondSingle = makeGridTestFile("single-second.ARW")
        let burstFiles = [makeGridTestFile("burst-first.ARW"), makeGridTestFile("burst-second.ARW")]
        let viewModel = RawCullViewModel()
        viewModel.similarityModel.burstGroups = [
            BurstGroup(id: 0, fileIDs: [firstSingle.id]),
            BurstGroup(id: 1, fileIDs: burstFiles.map(\.id)),
            BurstGroup(id: 2, fileIDs: [secondSingle.id])
        ]

        viewModel.burstReviewQueueFilter = .singleImages

        #expect(viewModel.filteredBurstGroupsForReviewQueue.map(\.id) == [0, 2])
    }

    @Test(.tags(.smoke))
    func `review and defer actions toggle back to persisted neutral state`() {
        let viewModel = RawCullViewModel()
        let first = makeGridTestFile("toggle-first.ARW")
        let second = makeGridTestFile("toggle-second.ARW")
        let catalog = URL(fileURLWithPath: "/tmp/toggle-catalog")
        viewModel.similarityModel.burstGroups = [
            BurstGroup(id: 1, fileIDs: [first.id, second.id])
        ]
        viewModel.burstAnalysisResults = [
            1: makeReviewQueueResult(
                groupID: 1,
                fileIDs: [first.id, second.id],
                confidence: .low,
            )
        ]

        #expect(viewModel.toggleBurstGroupReviewed(groupID: 1))
        #expect(viewModel.burstAnalysisResults[1]?.reviewState == .reviewed)

        #expect(!viewModel.toggleBurstGroupReviewed(groupID: 1))
        #expect(viewModel.burstAnalysisResults[1]?.reviewState.rawValue == BurstReviewState.none.rawValue)
        #expect(viewModel.reviewStateSnapshots(catalog: catalog, files: [first, second]).isEmpty)

        #expect(viewModel.toggleBurstGroupDeferred(groupID: 1))
        #expect(viewModel.burstAnalysisResults[1]?.reviewState == .deferred)

        #expect(!viewModel.toggleBurstGroupDeferred(groupID: 1))
        #expect(viewModel.burstAnalysisResults[1]?.reviewState.rawValue == BurstReviewState.none.rawValue)
        #expect(viewModel.reviewStateSnapshots(catalog: catalog, files: [first, second]).isEmpty)
    }

    @Test
    func `singleton groups remain visible in all but are excluded from review queues`() {
        let viewModel = RawCullViewModel()
        let singleton = makeGridTestFile("single.ARW")
        let first = makeGridTestFile("burst-a.ARW")
        let second = makeGridTestFile("burst-b.ARW")
        viewModel.similarityModel.burstGroups = [
            BurstGroup(id: 0, fileIDs: [singleton.id]),
            BurstGroup(id: 1, fileIDs: [first.id, second.id])
        ]
        viewModel.burstAnalysisResults = [
            0: makeReviewQueueResult(
                groupID: 0,
                fileIDs: [singleton.id],
                confidence: .low,
            ),
            1: makeReviewQueueResult(
                groupID: 1,
                fileIDs: [first.id, second.id],
                confidence: .low,
            )
        ]

        #expect(viewModel.burstReviewQueueCounts.needsReview == 1)
        #expect(viewModel.filteredBurstGroupsForReviewQueue.map(\.id) == [0, 1])

        viewModel.burstReviewQueueFilter = .needsReview
        #expect(viewModel.filteredBurstGroupsForReviewQueue.map(\.id) == [1])
    }
}
