import SwiftUI

struct LoupeImageControls: View {
    let loupeViewport: LoupeViewportModel
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
            scale: loupeViewport.scale,
            canZoomOut: loupeViewport.scale > ImageReviewViewportPolicy.loupe.minimumScale,
            canZoomIn: loupeViewport.scale < ImageReviewViewportPolicy.loupe.maximumScale,
            canReset: loupeViewport.scale != 1.0 || loupeViewport.offset != .zero,
            onZoomOut: {
                withAnimation(.spring()) {
                    loupeViewport.scale = ImageReviewViewportPolicy.loupe.zoomedOut(from: loupeViewport.scale)
                    loupeViewport.lastScale = loupeViewport.scale
                }
            },
            onZoomReset: { withAnimation(.spring()) { loupeViewport.reset() } },
            onZoomIn: {
                withAnimation(.spring()) {
                    loupeViewport.scale = ImageReviewViewportPolicy.loupe.zoomedIn(from: loupeViewport.scale)
                    loupeViewport.lastScale = loupeViewport.scale
                }
            },
        )
    }
}
