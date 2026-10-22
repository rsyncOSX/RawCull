import SwiftUI

struct DeepAIReviewHistoryContent: View {
    let controller: DeepAIReviewController
    let files: [FileItem]
    let candidates: [DeepAIReviewCandidate]
    @Binding var selection: UUID?
    let focusMaskModel: FocusMaskModel
    let focusConfig: FocusDetectorConfig

    private var selectedCandidate: DeepAIReviewCandidate? {
        selection.flatMap { id in
            candidates.first { $0.fileID == id }
        }
    }

    var body: some View {
        HSplitView {
            DeepAIReviewCandidateTable(
                candidates: candidates,
                winnerID: nil,
                selection: $selection,
            )
            .frame(minWidth: 400, idealWidth: 550)

            DeepAIReviewMaskPreview(
                controller: controller,
                files: files,
                candidate: selectedCandidate,
                focusMaskModel: focusMaskModel,
                focusConfig: focusConfig,
            )
            .frame(minWidth: 330, idealWidth: 420)
        }
        .aiAnalysisResultsContainer()
        .task(id: candidates.map(\.fileID)) {
            if selection == nil {
                selection = candidates.first?.fileID
            }
        }
    }
}
