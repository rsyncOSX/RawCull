import AppKit
import RawCullCore
import SwiftUI

struct ZoomOverlayControls: View {
    let viewModel: RawCullViewModel
    let session: ZoomSessionModel
    let hasFocusTarget: Bool
    let onRate: (Int) -> Void
    let onZoomOut: () -> Void
    let onZoomReset: () -> Void
    let onZoomIn: () -> Void

    private var maskAnalysisImage: CGImage? {
        ZoomOverlayImagePolicy.analysisImage(
            dedicatedAnalysisImage: viewModel.zoomOverlayAnalysisCGImage,
            displayImage: viewModel.zoomOverlayCGImage,
        )
    }

    private var subjectOutlineAvailable: Bool {
        guard let file = viewModel.selectedFile else { return false }
        return viewModel.deepAIReviewController.maskCandidate(for: file.id) != nil
    }

    private var useThumbnailSourceBinding: Binding<Bool> {
        Binding(
            get: { session.sourceSelection.selected == .thumbnail },
            set: { session.sourceSelection.select($0 ? .thumbnail : .embeddedJPG) },
        )
    }

    var body: some View {
        @Bindable var session = session
        VStack(spacing: 8) {
            if session.evaluateRAWExposure {
                if session.showRAWClippingWarning {
                    Text("Preview warning: red = near white · blue = near black · not a RAW recoverability test")
                        .font(.caption)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .background(.regularMaterial, in: Capsule())
                }

                RAWExposureInspectionControls(session: session, image: viewModel.zoomOverlayCGImage)
            }
            if !session.evaluateRAWExposure {
                HStack(spacing: 12) {
                    ImageOverlayControlsView(
                        showFocusMask: $session.viewport.showFocusMask,
                        focusMaskAvailable: maskAnalysisImage != nil || session.focusMask != nil,
                        showSubjectOutline: $session.showSubjectOutline,
                        showsSubjectOutlineControl: true,
                        subjectOutlineAvailable: subjectOutlineAvailable,
                        subjectOutlineLoading: session.isLoadingSubjectOutline,
                        hasFocusPoints: hasFocusTarget,
                        showFocusPoints: $session.viewport.showFocusPoints,
                        showShortcutHints: true,
                        showImageSourceToggle: true,
                        useThumbnailSource: useThumbnailSourceBinding,
                        imageSourceSelection: $session.sourceSelection,
                        imageSourceURL: viewModel.selectedFile?.url,
                        scale: session.viewport.scale,
                        canZoomOut: session.viewport.scale > 0.5,
                        canZoomIn: session.viewport.scale < 5.0,
                        canReset: session.viewport.scale != 1.0 || session.viewport.offset != .zero,
                        onZoomOut: onZoomOut,
                        onZoomReset: onZoomReset,
                        onZoomIn: onZoomIn,
                    )
                    Toggle("EV analysis", isOn: Binding(
                        get: { session.evaluateRAWExposure },
                        set: {
                            if $0 {
                                session.beginRAWExposureInspection()
                            }
                        },
                    ))
                    .toggleStyle(.button)
                    .buttonStyle(.plain)
                    .disabled(viewModel.selectedFile == nil || session.sourceSelection.rawUnavailable)
                    .help("Inspect highlights and shadows in the current RAW image")
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(.regularMaterial, in: Capsule())
                }
            }
        }
        .padding(.bottom, 20)
    }
}
