import AppKit
import Observation

@MainActor
@Observable
final class ObjectPhotoPreviewModel {
    private(set) var image: CGImage?
    private(set) var outlines: [String: CGImage] = [:]
    private(set) var focusMap: CGImage?
    private(set) var autofocusPoint: CGPoint?
    private(set) var spatialEvidence: [String: ObjectFocusSpatialEvidence] = [:]

    func load(
        result: ObjectPhotoAnalysisResult?, file: FileItem?,
        feature: RawCullObjectAnalysisFeature, focusMaskModel: FocusMaskModel,
        focusConfig: FocusDetectorConfig,
    ) async {
        outlines = [:]
        focusMap = nil
        autofocusPoint = nil
        spatialEvidence = [:]
        image = nil
        guard let result, let file else { return }
        let loadedImage = await AnalysisPreviewPreparation.loadImage(
            for: file, maxPixelSize: 2048,
        )
        guard !Task.isCancelled else { return }
        image = loadedImage
        if let image = loadedImage {
            guard
                let focus = await AnalysisPreviewPreparation.prepareFocus(
                    image: image, file: file, model: focusMaskModel, config: focusConfig,
                )
            else { return }
            let masks = await feature.cachedMasks(for: result, file: file)
            var rendered: [String: CGImage] = [:]
            for (id, mask) in masks {
                guard !Task.isCancelled else { return }
                rendered[id] = await ObjectMaskOutlineRenderer.outline(from: mask)
            }
            if !Task.isCancelled {
                autofocusPoint = focus.autofocusPoint
                focusMap = focus.mask
                spatialEvidence = ObjectFocusSpatialMapper.measure(
                    objectMasks: masks, focusMap: focus.mask,
                    autofocusPoint: focus.autofocusPoint,
                )
                outlines = rendered
            }
        }
    }
}
