import SwiftUI

@MainActor
struct LoupeKeyboardController {
    let viewModel: RawCullViewModel
    let session: LoupeSessionModel
    let focusPresentation: LoupeFocusPresentationModel
    let outlinePresentation: SubjectOutlinePresentationModel
    let hasSubjectOutline: Bool
    @Binding var showFocusPoints: Bool

    func handle(_ action: LoupeImageKeyAction?) -> KeyPress.Result {
        guard let action else { return .ignored }
        switch action {
        case .zoomIn:
            withAnimation(.spring()) {
                viewModel.scale = ImageReviewViewportPolicy.loupe.zoomedIn(from: viewModel.scale)
                viewModel.lastScale = viewModel.scale
            }
            return .handled

        case .zoomOut:
            withAnimation(.spring()) {
                viewModel.scale = ImageReviewViewportPolicy.loupe.zoomedOut(from: viewModel.scale)
                viewModel.lastScale = viewModel.scale
            }
            return .handled

        case .toggleEmbeddedJPG:
            session.toggleSource(.embeddedJPG)
            return .handled

        case .toggleDevelopedRAW:
            session.toggleSource(.developedRAW)
            return .handled

        case .toggleFocusMask:
            focusPresentation.isPresented.toggle()
            return .handled

        case .toggleSubjectOutline:
            guard hasSubjectOutline else { return .ignored }
            outlinePresentation.isPresented.toggle()
            return .handled

        case .toggleFocusPoints:
            showFocusPoints.toggle()
            return .handled

        case .toggleMetadata:
            withAnimation(.snappy) {
                viewModel.showsLoupeMetadataPanel.toggle()
            }
            return .handled

        case .inspectActualPixels:
            viewModel.openZoomOverlay(
                initialSource: .embeddedJPG,
                initialZoomMode: .actualPixels,
                showFocusPointsOnOpen: true,
            )
            return .handled
        }
    }
}
