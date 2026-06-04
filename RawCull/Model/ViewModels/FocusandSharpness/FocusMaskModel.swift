import AppKit
import Observation
import RawCullCore

@Observable @MainActor
final class FocusMaskModel {
    var config = FocusDetectorConfig()

    private nonisolated let engine = FocusMaskEngine()

    func generateFocusMask(
        from nsImage: NSImage,
        scale: CGFloat,
        configOverride: FocusDetectorConfig? = nil,
        afPoint: CGPoint? = nil,
        evidence: FocusEvidence? = nil,
    ) async -> NSImage? {
        guard let cgImage = nsImage.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return nil }
        let originalSize = nsImage.size
        let config = configOverride ?? self.config

        guard let result = await engine.generateFocusMask(
            from: cgImage,
            scale: scale,
            config: config,
            afPoint: afPoint,
            evidence: evidence,
        ) else { return nil }

        return NSImage(cgImage: result, size: originalSize)
    }

    func generateFocusMaskWithBreakdown(
        from cgImage: CGImage,
        scale: CGFloat,
        configOverride: FocusDetectorConfig? = nil,
        afPoint: CGPoint? = nil,
    ) async -> (mask: CGImage?, saliency: SaliencyInfo?, breakdown: SharpnessBreakdown?) {
        let config = configOverride ?? self.config
        return await engine.generateFocusMaskWithBreakdown(
            from: cgImage,
            scale: scale,
            config: config,
            afPoint: afPoint,
        )
    }

    nonisolated static func robustTailScore(_ samples: [Float]) -> Float? {
        FocusMaskEngine.robustTailScore(samples)
    }

    nonisolated static func microContrast(_ samples: [Float]) -> Float {
        FocusMaskEngine.microContrast(samples)
    }

    nonisolated static func isoScalingFactor(iso: Int) -> Float {
        FocusMaskEngine.isoScalingFactor(iso: iso)
    }

    nonisolated static func classifyFocusFailure(
        globalScore: Float?,
        subjectScore: Float?,
        afPointScore: Float?,
        blurGateSigma: Float,
    ) -> FocusFailureKind {
        FocusMaskEngine.classifyFocusFailure(
            globalScore: globalScore,
            subjectScore: subjectScore,
            afPointScore: afPointScore,
            blurGateSigma: blurGateSigma,
        )
    }

    @MainActor
    func applyCalibration(_ result: FocusCalibrationResult) {
        var cfg = config
        cfg.threshold = result.threshold
        config = cfg
    }

    @MainActor
    func calibrateAndApplyFromBurstParallel(
        files: [(url: URL, iso: Int?)],
        baseConfigOverride: FocusDetectorConfig? = nil,
        thumbnailMaxPixelSize: Int = 512,
        scoringSource: SharpnessScoringSource = .embeddedPreview,
        thresholdPercentile: Float = 0.90,
        minSamples: Int = 5,
        maxConcurrentTasks: Int = 8,
    ) async -> FocusCalibrationResult? {
        let base = baseConfigOverride ?? config
        guard let result = await engine.calibrateFromBurstParallel(
            files: files,
            baseConfig: base,
            thumbnailMaxPixelSize: thumbnailMaxPixelSize,
            scoringSource: scoringSource,
            thresholdPercentile: thresholdPercentile,
            minSamples: minSamples,
            maxConcurrentTasks: maxConcurrentTasks,
        ) else { return nil }

        applyCalibration(result)
        return result
    }
}
