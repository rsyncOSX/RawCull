import RawCullCore
import SwiftUI

@MainActor
struct ZoomOverlayAnalysisCoordinator {
    let catalogController: CatalogController
    let deepAIReviewController: DeepAIReviewController
    let session: ZoomSessionModel

    private var maskAnalysisImage: CGImage? {
        ZoomOverlayImagePolicy.analysisImage(
            dedicatedAnalysisImage: catalogController.zoomOverlay.analysisCGImage,
            displayImage: catalogController.zoomOverlay.cgImage,
        )
    }

    private var subjectOutlineCandidate: DeepAIReviewCandidate? {
        guard let fileID = catalogController.selectedFile?.id else { return nil }
        return deepAIReviewController.maskCandidate(for: fileID)
    }

    func regenerateMaskFromCG() async {
        guard let cg = maskAnalysisImage,
              let selectedFile = catalogController.selectedFile
        else { return }
        let selectedFileID = selectedFile.id
        let previewSource = session.sourceSelection.selected
        let config = focusMaskConfig(for: selectedFile)
        guard !Task.isCancelled,
              catalogController.selectedFile?.id == selectedFileID,
              maskAnalysisImage === cg,
              session.sourceSelection.selected == previewSource
        else { return }
        let result = await catalogController.sharpnessModel.focusMaskModel.generateFocusMaskWithBreakdown(
            from: FocusMaskAnalysisResolutionPolicy.prepare(cg),
            scale: 1.0,
            configOverride: config,
            afPoint: selectedFile.afFocusNormalized,
            iso: selectedFile.exifData?.isoValue ?? 400,
            aperture: selectedFile.exifData?.apertureValue,
            scoringSource: previewSource == .developedRAW ? .rawDemosaic : .embeddedPreview,
        )
        guard !Task.isCancelled,
              catalogController.selectedFile?.id == selectedFileID,
              maskAnalysisImage === cg,
              session.sourceSelection.selected == previewSource
        else { return }
        await MainActor.run {
            session.focusMask = result.mask
            if let breakdown = result.breakdown {
                catalogController.sharpnessModel.breakdowns[selectedFile.id] = breakdown
            }
            if let saliency = result.saliency {
                catalogController.sharpnessModel.saliencyInfo[selectedFile.id] = saliency
            }
        }
    }

    private func focusMaskConfig(for file: FileItem) -> FocusDetectorConfig {
        var config = catalogController.sharpnessModel.effectiveFocusConfig
        config.iso = file.exifData?.isoValue ?? 400
        config.apertureHint = FocusDetectorConfig.ApertureHint.from(aperture: file.exifData?.apertureValue)
        return config
    }

    func loadSubjectOutline() async {
        session.subjectOutline = nil
        session.isLoadingSubjectOutline = false
        guard session.showSubjectOutline,
              let file = catalogController.selectedFile,
              let candidate = subjectOutlineCandidate
        else { return }

        session.isLoadingSubjectOutline = true
        let outline = await ImageReviewSubjectOutlineLoader.load(
            file: file, candidate: candidate, controller: deepAIReviewController,
        )
        guard !Task.isCancelled, catalogController.selectedFile?.id == file.id else { return }
        session.subjectOutline = outline
        session.isLoadingSubjectOutline = false
    }
}
