import RawCullCore
import SwiftUI

@MainActor
struct ZoomOverlayAnalysisCoordinator {
    let viewModel: RawCullViewModel
    let session: ZoomSessionModel

    private var maskAnalysisImage: CGImage? {
        ZoomOverlayImagePolicy.analysisImage(
            dedicatedAnalysisImage: viewModel.zoomOverlayAnalysisCGImage,
            displayImage: viewModel.zoomOverlayCGImage,
        )
    }

    private var subjectOutlineCandidate: DeepAIReviewCandidate? {
        guard let fileID = viewModel.selectedFile?.id else { return nil }
        return viewModel.deepAIReviewController.maskCandidate(for: fileID)
    }

    func regenerateMaskFromCG() async {
        guard let cg = maskAnalysisImage,
            let selectedFile = viewModel.selectedFile
        else { return }
        let selectedFileID = selectedFile.id
        let previewSource = session.sourceSelection.selected
        let config = focusMaskConfig(for: selectedFile)
        guard !Task.isCancelled,
            viewModel.selectedFile?.id == selectedFileID,
            maskAnalysisImage === cg,
            session.sourceSelection.selected == previewSource
        else { return }
        let result = await viewModel.sharpnessModel.focusMaskModel.generateFocusMaskWithBreakdown(
            from: FocusMaskAnalysisResolutionPolicy.prepare(cg),
            scale: 1.0,
            configOverride: config,
            afPoint: selectedFile.afFocusNormalized,
            iso: selectedFile.exifData?.isoValue ?? 400,
            aperture: selectedFile.exifData?.apertureValue,
            scoringSource: previewSource == .developedRAW ? .rawDemosaic : .embeddedPreview,
        )
        guard !Task.isCancelled,
            viewModel.selectedFile?.id == selectedFileID,
            maskAnalysisImage === cg,
            session.sourceSelection.selected == previewSource
        else { return }
        await MainActor.run {
            session.focusMask = result.mask
            if let breakdown = result.breakdown {
                viewModel.sharpnessModel.breakdowns[selectedFile.id] = breakdown
            }
            if let saliency = result.saliency {
                viewModel.sharpnessModel.saliencyInfo[selectedFile.id] = saliency
            }
        }
    }

    private func focusMaskConfig(for file: FileItem) -> FocusDetectorConfig {
        var config = viewModel.sharpnessModel.effectiveFocusConfig
        config.iso = file.exifData?.isoValue ?? 400
        config.apertureHint = FocusDetectorConfig.ApertureHint.from(aperture: file.exifData?.apertureValue)
        return config
    }

    func loadSubjectOutline() async {
        session.subjectOutline = nil
        session.isLoadingSubjectOutline = false
        guard session.showSubjectOutline,
            let file = viewModel.selectedFile,
            let candidate = subjectOutlineCandidate
        else { return }

        session.isLoadingSubjectOutline = true
        let outline = await ImageReviewSubjectOutlineLoader.load(
            file: file, candidate: candidate, controller: viewModel.deepAIReviewController,
        )
        guard !Task.isCancelled, viewModel.selectedFile?.id == file.id else { return }
        session.subjectOutline = outline
        session.isLoadingSubjectOutline = false
    }
}
