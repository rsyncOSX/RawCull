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
            set: { session.selectSource($0 ? .thumbnail : .embeddedJPG) })
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
            scale: viewModel.scale,
            canZoomOut: viewModel.scale > ImageReviewViewportPolicy.loupe.minimumScale,
            canZoomIn: viewModel.scale < ImageReviewViewportPolicy.loupe.maximumScale,
            canReset: viewModel.scale != 1.0 || viewModel.offset != .zero,
            onZoomOut: {
                withAnimation(.spring()) {
                    viewModel.scale = ImageReviewViewportPolicy.loupe.zoomedOut(from: viewModel.scale)
                    viewModel.lastScale = viewModel.scale
                }
            },
            onZoomReset: { withAnimation(.spring()) { viewModel.resetZoom() } },
            onZoomIn: {
                withAnimation(.spring()) {
                    viewModel.scale = ImageReviewViewportPolicy.loupe.zoomedIn(from: viewModel.scale)
                    viewModel.lastScale = viewModel.scale
                }
            },
        )
    }
}
