import Foundation

extension RawCullViewModel {
    var visibleReviewQueueItems: [ReviewQueueItem] {
        reviewQueueItems.filter { item in
            let categoryMatches = selectedReviewQueueCategory.map { $0 == item.category } ?? true
            let stateMatches = showResolvedReviewQueueItems || item.resolutionState == .open
            return categoryMatches && stateMatches
        }
    }

    var reviewQueueSummaryText: String {
        let open = reviewQueueItems.count(where: { $0.resolutionState == .open })
        let attention = reviewQueueOpenAttentionCount
        if attention == 0 {
            return "\(open) open"
        }
        return "\(attention) need attention"
    }

    func rebuildReviewQueue() {
        guard let catalog = selectedSource?.url else {
            reviewQueueItems = []
            return
        }

        let persistedStates = cullingModel.reviewQueueStates(in: catalog)
        let input = ReviewQueueBuilder.Input(
            catalog: catalog,
            files: files,
            burstGroups: similarityModel.burstGroups,
            burstResults: burstAnalysisResults,
            boundaryEvidence: similarityModel.burstBoundaryEvidence,
            sharpnessScores: sharpnessModel.scores,
            sharpnessWasExpected: reviewQueueSharpnessExpected,
            diagnosticIssues: reviewQueueDiagnosticIssues,
            copyOutput: lastCopyOutputLines,
            persistedStates: persistedStates,
        )
        let items = ReviewQueueBuilder().build(input: input)
        reviewQueueItems = items
        cullingModel.pruneReviewQueueStates(
            validFingerprints: Set(items.map(\.fingerprint)),
            in: catalog,
        )
    }

    func resolveReviewQueueItem(_ item: ReviewQueueItem) {
        updateReviewQueueItemState(item, state: .resolved)
    }

    func ignoreReviewQueueItem(_ item: ReviewQueueItem) {
        updateReviewQueueItemState(item, state: .ignored)
    }

    func reopenReviewQueueItem(_ item: ReviewQueueItem) {
        guard let catalog = selectedSource?.url else { return }
        cullingModel.reopenReviewQueueState(fingerprint: item.fingerprint, in: catalog)
        rebuildReviewQueue()
    }

    func openReviewQueueItem(_ item: ReviewQueueItem) {
        switch item.category {
        case .burst, .metadata:
            if let groupID = item.groupID,
               let group = similarityModel.burstGroups.first(where: { $0.id == groupID }) {
                let groupFiles = group.fileIDs.compactMap { id in files.first { $0.id == id } }
                compareBurstGroup(groupFiles)
            } else {
                selectFileForReviewItem(item)
            }

        case .parser, .catalog, .sharpness, .cache:
            selectFileForReviewItem(item)
            if item.category == .parser || item.category == .catalog,
               let file = selectedFile {
                rawDiagnosticsPresentation = RawDiagnosticsPresentation(log: RawFileDiagnostics.log(for: file))
            }

        case .copy:
            sheetType = .detailsview
            showcopyARWFilesView = remotedatanumbers != nil
        }
    }

    func recordCopyResult(outputLines: [String]?) {
        lastCopyOutputLines = outputLines ?? []
        rebuildReviewQueue()
    }

    func refreshReviewQueueDiagnostics() {
        reviewQueueDiagnosticIssues = files.flatMap { RawFileDiagnostics.issues(for: $0) }
        rebuildReviewQueue()
    }

    func presentRawDiagnostics(for file: FileItem) {
        rawDiagnosticsPresentation = RawDiagnosticsPresentation(log: RawFileDiagnostics.log(for: file))
    }

    private func updateReviewQueueItemState(_ item: ReviewQueueItem, state: ReviewQueueResolutionState) {
        guard let catalog = selectedSource?.url else { return }
        cullingModel.updateReviewQueueState(
            ReviewQueueItemState(
                fingerprint: item.fingerprint,
                resolutionState: state,
                resolvedAt: Date(),
            ),
            in: catalog,
        )
        rebuildReviewQueue()
    }

    private func selectFileForReviewItem(_ item: ReviewQueueItem) {
        if let fileID = item.fileID, files.contains(where: { $0.id == fileID }) {
            selectedFileID = fileID
        } else if let fileName = item.fileName,
                  let file = files.first(where: { $0.name == fileName }) {
            selectedFileID = file.id
        }
        selectMainViewMode(.loupe)
    }
}
