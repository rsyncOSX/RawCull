import SwiftUI

struct LoupeImageControls: View {
    let viewModel: RawCullViewModel
    let session: LoupeSessionModel
    let file: FileItem?
    @Binding var showFocusMask: Bool
    @Binding var showSubjectOutline: Bool
    @Binding var showFocusPoints: Bool
    let focusMaskAvailable: Bool
    let outlineAvailable: Bool
    let outlineIsLoading: Bool
    let hasFocusPoints: Bool

    private var useThumbnailSourceBinding: Binding<Bool> {
        Binding(
            get: { session.sourceSelection.selected == .thumbnail },
            set: { session.selectSource($0 ? .thumbnail : .embeddedJPG) },
        )
    }

    var body: some View {
        ImageOverlayControlsView(
            showFocusMask: $showFocusMask,
            focusMaskAvailable: focusMaskAvailable,
            showSubjectOutline: $showSubjectOutline,
            showsSubjectOutlineControl: true,
            subjectOutlineAvailable: outlineAvailable,
            subjectOutlineLoading: outlineIsLoading,
            hasFocusPoints: hasFocusPoints,
            showFocusPoints: $showFocusPoints,
            showShortcutHints: true,
            showImageSourceToggle: true,
            useThumbnailSource: useThumbnailSourceBinding,
            imageSourceSelection: Binding(
                get: { session.sourceSelection },
                set: { session.sourceSelection = $0 },
            ),
            imageSourceURL: file?.url,
            scale: viewModel.loupeViewport.scale,
            canZoomOut: viewModel.loupeViewport.scale > ImageReviewViewportPolicy.loupe.minimumScale,
            canZoomIn: viewModel.loupeViewport.scale < ImageReviewViewportPolicy.loupe.maximumScale,
            canReset: viewModel.loupeViewport.scale != 1.0 || viewModel.loupeViewport.offset != .zero,
            onZoomOut: {
                withAnimation(.spring()) {
                    viewModel.loupeViewport.scale = ImageReviewViewportPolicy.loupe.zoomedOut(from: viewModel.loupeViewport.scale)
                    viewModel.loupeViewport.lastScale = viewModel.loupeViewport.scale
                }
            },
            onZoomReset: { withAnimation(.spring()) { viewModel.loupeViewport.reset() } },
            onZoomIn: {
                withAnimation(.spring()) {
                    viewModel.loupeViewport.scale = ImageReviewViewportPolicy.loupe.zoomedIn(from: viewModel.loupeViewport.scale)
                    viewModel.loupeViewport.lastScale = viewModel.loupeViewport.scale
                }
            },
        )
    }
}
