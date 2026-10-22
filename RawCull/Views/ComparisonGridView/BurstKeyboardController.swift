import OSLog
import SwiftUI

@MainActor
struct BurstKeyboardController {
    let viewModel: RawCullViewModel
    let session: BurstWorkspaceSessionModel
    let groupID: Int
    let selectedFile: FileItem?
    let hasImage: Bool
    let navigate: (Int) -> Void
    let applyRating: (Int) -> Void

    private func handleKeyAction(_ action: ZoomOverlayKeyAction?) -> KeyPress.Result {
        guard let action else { return .ignored }

        switch action {
        case .navigatePrevious:
            navigate(-1)

        case .navigateNext:
            navigate(1)

        case .escape:
            viewModel.returnToActiveBurstGroupView()

        case .zoomIn:
            withAnimation(.spring()) {
                session.viewportState.scale = ImageReviewViewportPolicy.comparison.zoomedIn(from: session.viewportState.scale)
                session.viewportState.lastScale = session.viewportState.scale
            }

        case .zoomOut:
            withAnimation(.spring()) {
                session.viewportState.scale = ImageReviewViewportPolicy.comparison.zoomedOut(from: session.viewportState.scale)
                session.viewportState.lastScale = session.viewportState.scale
            }

        case .toggleEmbeddedJPG:
            session.sourceSelection.toggleExtractionSource(.embeddedJPG)

        case .toggleDevelopedRAW:
            session.sourceSelection.toggleExtractionSource(.developedRAW)

        case .toggleFocusMask:
            session.viewportState.showFocusMask.toggle()
            Logger(subsystem: "RawCull", category: "BurstFocusDebug").notice(
                "Toggle focus: \(session.viewportState.showFocusMask), image: \(hasImage)")

        case .toggleSubjectOutline:
            guard let selectedFile,
                viewModel.deepAIReviewController.maskCandidate(for: selectedFile.id) != nil
            else { return .ignored }
            session.showSubjectOutline.toggle()

        case .toggleFocusPoints:
            session.viewportState.showFocusPoints.toggle()

        case .rating(let rating):
            applyRating(rating)
        }
        return .handled
    }

    func handle(_ characters: String) -> KeyPress.Result {
        if let action = BurstReviewKeyAction.resolve(characters: characters) {
            switch action {
            case .previousImage:
                navigate(-1)

            case .nextImage:
                navigate(1)

            case .nextGroup:
                viewModel.advanceToNextBurstGroup(after: groupID)
            }
            return .handled
        }

        return handleKeyAction(
            ZoomOverlayKeyAction.resolve(
                characters: characters,
                keyCode: 0,
                navigationAxis: .horizontal,
            ))
    }
}
