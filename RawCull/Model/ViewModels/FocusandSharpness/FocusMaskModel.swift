import AppKit
import Observation
import PhotoAnalysisKit
import RawCullCore

@Observable @MainActor
final class FocusMaskModel {
    var config = FocusDetectorConfig()

    private nonisolated let analyzer = PhotoAnalyzer()
    private nonisolated let fileAdapter = RawCullPhotoAnalysisAdapter()

    func generateFocusMask(
        from nsImage: NSImage,
        scale: CGFloat,
        configOverride: FocusDetectorConfig? = nil,
        afPoint: CGPoint? = nil,
        iso: Int = 400,
        aperture: Double? = nil,
        evidence: FocusEvidence? = nil,
    ) async -> NSImage? {
        guard let cgImage = nsImage.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return nil }
        let input = PhotoAnalysisInput(
            image: cgImage,
            iso: iso,
            aperture: aperture,
            normalizedAFPoint: afPoint,
        )
        guard let result = await analyzer.focusMask(
            for: input,
            scale: scale,
            configuration: configOverride ?? config,
            evidence: evidence,
        ) else { return nil }

        return NSImage(cgImage: result, size: nsImage.size)
    }

    func generateFocusMaskWithBreakdown(
        from cgImage: CGImage,
        scale: CGFloat,
        configOverride: FocusDetectorConfig? = nil,
        afPoint: CGPoint? = nil,
        iso: Int = 400,
        aperture: Double? = nil,
        scoringSource: SharpnessScoringSource = .embeddedPreview,
    ) async -> (mask: CGImage?, saliency: SaliencyInfo?, breakdown: SharpnessBreakdown?) {
        let input = PhotoAnalysisInput(
            image: cgImage,
            iso: iso,
            aperture: aperture,
            normalizedAFPoint: afPoint,
        )
        let result = await analyzer.analyzeWithFocusMask(
            input,
            scale: scale,
            configuration: configOverride ?? config,
        )
        let saliency = result.saliency.map {
            SaliencyInfo(subjectLabel: $0.subjectLabel, subjectConfidence: $0.subjectConfidence)
        }
        let breakdown = result.breakdown.map {
            SharpnessBreakdown(package: $0, scoringSource: scoringSource)
        }
        return (result.focusMask, saliency, breakdown)
    }

    // periphery:ignore
    nonisolated static func robustTailScore(_ samples: [Float]) -> Float? {
        SharpnessMetrics.robustTailScore(samples)
    }

    // periphery:ignore
    nonisolated static func microContrast(_ samples: [Float]) -> Float {
        SharpnessMetrics.microContrast(samples)
    }

    // periphery:ignore
    nonisolated static func isoScalingFactor(iso: Int) -> Float {
        SharpnessMetrics.isoScalingFactor(iso: iso)
    }

    // periphery:ignore
    nonisolated static func classifyFocusFailure(
        globalScore: Float?,
        subjectScore: Float?,
        afPointScore: Float?,
        blurGateSigma: Float,
    ) -> FocusFailureKind {
        SharpnessMetrics.classifyFocusFailure(
            globalScore: globalScore,
            subjectScore: subjectScore,
            afPointScore: afPointScore,
            blurGateSigma: blurGateSigma,
        )
    }

    func applyCalibration(_ result: FocusCalibrationResult) {
        var calibrated = config
        calibrated.threshold = result.threshold
        config = calibrated
    }

    func calibrateAndApplyFromBurstParallel(
        files: [(url: URL, iso: Int?, aperture: Double?)],
        baseConfigOverride: FocusDetectorConfig? = nil,
        thumbnailMaxPixelSize: Int = 512,
        scoringSource: SharpnessScoringSource = .embeddedPreview,
        thresholdPercentile: Float = 0.90,
        minSamples: Int = 5,
        maxConcurrentTasks: Int = 8,
    ) async -> FocusCalibrationResult? {
        let analysisFiles = files.map {
            RawCullPhotoAnalysisFile(
                url: $0.url,
                iso: $0.iso ?? 400,
                aperture: $0.aperture,
                normalizedAFPoint: nil,
            )
        }
        guard let result = await fileAdapter.calibrate(
            files: analysisFiles,
            baseConfiguration: baseConfigOverride ?? config,
            maximumPixelSize: thumbnailMaxPixelSize,
            source: scoringSource,
            thresholdPercentile: thresholdPercentile,
            minimumSuccessfulImages: minSamples,
            maximumConcurrentTasks: maxConcurrentTasks,
        ) else { return nil }

        applyCalibration(result)
        return result
    }
}
