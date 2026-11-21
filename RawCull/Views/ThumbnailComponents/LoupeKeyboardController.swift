import SwiftUI

@MainActor
struct LoupeKeyboardController {
    let presentation: WorkspacePresentationModel
    let loupeViewport: LoupeViewportModel
    let navigation: WorkspaceNavigationModel
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
                loupeViewport.scale = ImageReviewViewportPolicy.loupe.zoomedIn(from: loupeViewport.scale)
                loupeViewport.lastScale = loupeViewport.scale
            }
            return .handled

        case .zoomOut:
            withAnimation(.spring()) {
                loupeViewport.scale = ImageReviewViewportPolicy.loupe.zoomedOut(from: loupeViewport.scale)
                loupeViewport.lastScale = loupeViewport.scale
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
                presentation.showsLoupeMetadataPanel.toggle()
            }
            return .handled

        case .inspectActualPixels:
            navigation.openZoomOverlay(
                initialSource: .embeddedJPG,
                initialZoomMode: .actualPixels,
                showFocusPointsOnOpen: true,
            )
            return .handled
        }
    }
}
