import AppKit

/// Shared preparation for analysis previews; callers retain their own task identity.
@MainActor
enum AnalysisPreviewPreparation {
    struct FocusPreview {
        let mask: CGImage?
        let autofocusPoint: CGPoint?
    }

    static func loadImage(for file: FileItem, maxPixelSize: Int) async -> CGImage? {
        guard !Task.isCancelled else { return nil }
        let image = await RawParserKitImageLoader.shared.thumbnailCGImage(
            for: file.url, maxPixelSize: maxPixelSize,
        )
        return Task.isCancelled ? nil : image
    }

    static func prepareFocus(
        image: CGImage,
        file: FileItem,
        model: FocusMaskModel,
        config: FocusDetectorConfig,
    ) async -> FocusPreview? {
        guard !Task.isCancelled else { return nil }
        let point: CGPoint? = if let recorded = file.afFocusNormalized {
            recorded
        } else {
            await RawParserKitImageLoader.shared.fileMetadata(for: file.url)?.focusPoint
        }
        guard !Task.isCancelled else { return nil }
        var adjusted = config
        adjusted.iso = file.exifData?.isoValue ?? 400
        adjusted.apertureHint = FocusDetectorConfig.ApertureHint.from(
            aperture: file.exifData?.apertureValue,
        )
        let generated = await model.generateFocusMaskWithBreakdown(
            from: FocusMaskAnalysisResolutionPolicy.prepare(image),
            scale: 1.0, configOverride: adjusted, afPoint: point,
            iso: file.exifData?.isoValue ?? 400,
            aperture: file.exifData?.apertureValue,
        )
        guard !Task.isCancelled else { return nil }
        return FocusPreview(mask: generated.mask, autofocusPoint: point)
    }
}
