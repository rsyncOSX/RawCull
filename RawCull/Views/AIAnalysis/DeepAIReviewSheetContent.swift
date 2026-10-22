import SwiftUI

struct DeepAIReviewSheetContent: View {
    let controller: DeepAIReviewController
    let files: [FileItem]
    let completedFiles: [FileItem]
    let completedCandidates: [DeepAIReviewCandidate]
    let state: DeepAIReviewPresentationState
    @Binding var selection: UUID?
    let focusMaskModel: FocusMaskModel
    let focusConfig: FocusDetectorConfig

    var body: some View {
        if completedCandidates.isEmpty {
            emptyContent
        } else {
            if case let .failed(_, failure) = state {
                AIAnalysisErrorView(message: failureMessage(failure))
            } else if case let .unavailable(reason) = state {
                AIAnalysisErrorView(message: reason)
            }
            if case let .preparing(_, totalCount) = state {
                DeepAIReviewProgressHeader(
                    completedCount: 0,
                    totalCount: totalCount,
                    currentFileName: nil,
                )
            } else if case let .running(progress) = state {
                DeepAIReviewProgressHeader(
                    completedCount: progress.completedCount,
                    totalCount: progress.totalCount,
                    currentFileName: progress.currentFileName,
                )
            } else if case .completing = state {
                ProgressView("Completing Deep Review…")
            }

            DeepAIReviewHistoryContent(
                controller: controller,
                files: completedFiles,
                candidates: completedCandidates,
                selection: $selection,
                focusMaskModel: focusMaskModel,
                focusConfig: focusConfig,
            )
        }
    }

    @ViewBuilder
    private var emptyContent: some View {
        switch state {
        case .completed:
            ContentUnavailableView(
                "Ready to Analyze",
                systemImage: "sparkle.magnifyingglass",
                description: Text("Select new images to analyze."),
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .aiAnalysisResultsContainer()

        case let .preparing(_, totalCount):
            let placeholders = files.enumerated().map { index, file in
                DeepAIReviewCandidate.placeholder(rank: index + 1, file: file)
            }
            DeepAIReviewProgressHeader(
                completedCount: 0,
                totalCount: totalCount,
                currentFileName: nil,
            )
            DeepAIReviewCandidateTable(
                candidates: placeholders,
                winnerID: nil,
                selection: $selection,
            )
            .aiAnalysisResultsContainer()

        case let .running(progress):
            DeepAIReviewProgressHeader(
                completedCount: progress.completedCount,
                totalCount: progress.totalCount,
                currentFileName: progress.currentFileName,
            )
            DeepAIReviewCandidateTable(
                candidates: progress.candidates,
                winnerID: nil,
                selection: $selection,
            )
            .aiAnalysisResultsContainer()

        case .completing:
            HStack(spacing: 10) {
                ProgressView()
                Text("Completing Deep Review…")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()

        case let .checking(expectedLocations):
            ContentUnavailableView(
                "Checking Deep Review",
                systemImage: "hourglass",
                description: Text(checkingMessage(expectedLocations)),
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)

        case let .unavailable(reason):
            ContentUnavailableView(
                "Deep Review Unavailable",
                systemImage: "sparkle.magnifyingglass",
                description: Text(reason),
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)

        case .cancelled:
            ContentUnavailableView(
                "Deep Review Cancelled",
                systemImage: "xmark.circle",
                description: Text("Run Deep Review again when you are ready."),
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)

        case let .failed(_, failure):
            ContentUnavailableView(
                "Deep Review Failed",
                systemImage: "exclamationmark.triangle",
                description: Text(failureMessage(failure)),
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)

        case .ready:
            ContentUnavailableView(
                "Ready to Analyze",
                systemImage: "sparkle.magnifyingglass",
                description: Text("Run local AI subject-detail analysis for this burst group."),
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .aiAnalysisResultsContainer()
        }
    }

    private func checkingMessage(_ expectedLocations: [URL]) -> String {
        expectedLocations.first.map {
            "RawCull is checking the selected segmentation model at \($0.path)."
        } ?? "RawCull is checking the selected segmentation model."
    }

    private func failureMessage(_ failure: DeepAIReviewFailure) -> String {
        switch failure {
        case let .modelUnavailable(reason):
            reason

        case .noCandidates:
            "This burst group has no candidates to review."

        case let .pipelineFailed(reason):
            "The in-process segmentation pipeline failed: \(reason)"
        }
    }
}
