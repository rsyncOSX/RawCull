import AppKit
import RawCullCore
import SwiftUI

@MainActor
struct ComparisonKeyboardController {
    let viewModel: RawCullViewModel
    let session: ComparisonSessionModel
    @Binding var showCandidateInspector: Bool

    private var presentation: ComparisonSessionPresentation {
        session.presentation(
            filteredFiles: viewModel.catalog.filteredFiles, comparisonFileIDs: viewModel.selection.comparisonFileIDs,
            activeBurstComparisonGroupID: viewModel.burstWorkflow.activeBurstComparisonGroupID,
            burstAnalysisResult: viewModel.burstWorkflow.burstAnalysisResult(for:),
        )
    }

    private var files: [FileItem] {
        presentation.files
    }

    private var allComparisonFiles: [FileItem] {
        presentation.allComparisonFiles
    }

    private var selectedComparisonFile: FileItem? {
        presentation.selectedComparisonFile
    }

    private var canApplyOneClickCulling: Bool {
        presentation.burstComparisonResult?.canApplyOneClickCulling(
            hasSharpnessScores: !viewModel.sharpnessModel.scores.isEmpty,
        ) ?? false
    }

    private func applyRating(_ rating: Int) -> KeyPress.Result {
        guard let file = selectedComparisonFile else { return .ignored }
        viewModel.updateRatingAndAdvance(for: file, rating: rating, in: files)
        return .handled
    }

    private func applyBurstKeepBest() -> KeyPress.Result {
        guard viewModel.burstWorkflow.activeBurstComparisonGroupID != nil,
              canApplyOneClickCulling,
              !allComparisonFiles.isEmpty
        else { return .ignored }
        viewModel.burstWorkflow.keepBestInGroup(from: allComparisonFiles)
        return .handled
    }

    func handleKeyEvent(_ event: NSEvent) -> KeyPress.Result {
        let burstAction =
            viewModel.burstWorkflow.activeBurstComparisonGroupID == nil
                ? nil
                : BurstReviewKeyAction.resolve(characters: event.characters)
        if let burstAction {
            return handleBurstReviewKeyAction(burstAction)
        }

        guard
            let action = ComparisonGridKeyAction.resolve(
                characters: event.characters,
                keyCode: event.keyCode,
            )
        else { return .ignored }

        return handleKeyAction(action)
    }

    private func handleBurstReviewKeyAction(_ action: BurstReviewKeyAction) -> KeyPress.Result {
        switch action {
        case .previousImage:
            navigate(.left)

        case .nextImage:
            navigate(.right)

        case .nextGroup:
            guard let groupID = viewModel.burstWorkflow.activeBurstComparisonGroupID else { return .ignored }
            viewModel.burstWorkflow.advanceToNextBurstGroup(after: groupID)
        }
        return .handled
    }

    private func handleKeyAction(_ action: ComparisonGridKeyAction) -> KeyPress.Result {
        switch action {
        case let .navigate(direction):
            navigate(direction)
            return .handled

        case .escape:
            if viewModel.burstWorkflow.activeBurstComparisonGroupID != nil {
                viewModel.burstWorkflow.returnToActiveBurstGroupView()
                return .handled
            }
            return .ignored

        case .zoomIn:
            return increaseZoom()

        case .zoomOut:
            return decreaseZoom()

        case .toggleImageSource:
            return toggleSelectedImageSource()

        case .toggleInspector:
            showCandidateInspector.toggle()
            return .handled

        case .toggleFocusMask:
            return toggleSelectedFocusMask()

        case .toggleFocusPoints:
            return toggleSelectedFocusPoints()

        case .inspectActualPixels:
            return inspectSelectedActualPixels()

        case .keepBest:
            return applyBurstKeepBest()

        case let .rating(rating):
            return applyRating(rating)
        }
    }

    private func navigate(_ direction: ComparisonGridNavigationDirection) {
        session.moveSelection(direction, in: files)
    }

    @discardableResult
    private func selectedFileIDForInteraction() -> FileItem.ID? {
        guard let selectedID = viewModel.selection.selectedFileID,
              files.contains(where: { $0.id == selectedID })
        else { return nil }

        return selectedID
    }

    private func toggleSelectedFocusMask() -> KeyPress.Result {
        guard let selectedID = selectedFileIDForInteraction() else { return .ignored }
        var state = session.viewportState(for: selectedID)
        state.showFocusMask.toggle()
        session.setViewportState(state, for: selectedID)
        return .handled
    }

    private func toggleSelectedFocusPoints() -> KeyPress.Result {
        guard let selectedID = selectedFileIDForInteraction() else { return .ignored }
        var state = session.viewportState(for: selectedID)
        state.showFocusPoints.toggle()
        session.setViewportState(state, for: selectedID)
        return .handled
    }

    private func toggleSelectedImageSource() -> KeyPress.Result {
        guard let selectedID = selectedFileIDForInteraction() else { return .ignored }
        session.setUsesThumbnailSource(
            !session.usesThumbnailSource(for: selectedID),
            for: selectedID,
        )
        return .handled
    }

    private func inspectSelectedActualPixels() -> KeyPress.Result {
        guard selectedFileIDForInteraction() != nil else { return .ignored }
        viewModel.openZoomOverlay(
            navigationIDs: files.map(\.id),
            initialSource: .embeddedJPG,
            initialZoomMode: .actualPixels,
            showFocusPointsOnOpen: true,
        )
        return .handled
    }

    private func increaseZoom() -> KeyPress.Result {
        guard let selectedID = selectedFileIDForInteraction() else { return .ignored }
        withAnimation(.spring()) {
            var state = session.viewportState(for: selectedID)
            state.zoomIn()
            session.setViewportState(state, for: selectedID)
        }
        return .handled
    }

    private func decreaseZoom() -> KeyPress.Result {
        guard let selectedID = selectedFileIDForInteraction() else { return .ignored }
        withAnimation(.spring()) {
            var state = session.viewportState(for: selectedID)
            state.zoomOut()
            session.setViewportState(state, for: selectedID)
        }
        return .handled
    }

    private func inspectFinalists() {
        guard session.focusFinalists(in: presentation.burstComparisonResult) else { return }
        showCandidateInspector = true
    }

    private func showAllCandidates() {
        session.showAllCandidates(in: allComparisonFiles)
    }
}
