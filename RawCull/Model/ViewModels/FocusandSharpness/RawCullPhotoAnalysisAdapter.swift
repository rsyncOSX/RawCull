import CoreImage
import CoreImage.CIFilterBuiltins
import Foundation
import PhotoAnalysisKit
import RawCullCore

nonisolated struct RawCullPhotoAnalysisFile: Sendable {
    let url: URL
    let iso: Int
    let aperture: Double?
    let normalizedAFPoint: CGPoint?
}

/// Adapts RawCull file loading and source selection to PhotoAnalysisKit's
/// decoded-image API. No application model or persistence state crosses into
/// the package.
nonisolated struct RawCullPhotoAnalysisAdapter: Sendable {
    private let analyzer = PhotoAnalyzer()

    func analyze(
        file: RawCullPhotoAnalysisFile,
        configuration: FocusDetectorConfig,
        maximumPixelSize: Int,
        source: SharpnessScoringSource,
    ) async -> (score: Float?, saliency: SaliencyInfo?, breakdown: SharpnessBreakdown?) {
        guard let input = await input(
            for: file,
            maximumPixelSize: maximumPixelSize,
            source: source,
        ) else { return (nil, nil, nil) }

        let result = await analyzer.analyze(input, configuration: configuration)
        return Self.adapt(result, scoringSource: source)
    }

    func calibrate(
        files: [RawCullPhotoAnalysisFile],
        baseConfiguration: FocusDetectorConfig,
        maximumPixelSize: Int,
        source: SharpnessScoringSource,
        thresholdPercentile: Float,
        minimumSuccessfulImages: Int,
        maximumConcurrentTasks: Int,
    ) async -> FocusCalibrationResult? {
        guard !files.isEmpty else { return nil }
        let concurrency = max(1, min(maximumConcurrentTasks, files.count))
        var inputs = [PhotoAnalysisInput]()
        var nextIndex = 0

        await withTaskGroup(of: PhotoAnalysisInput?.self) { group in
            func enqueue(_ file: RawCullPhotoAnalysisFile) {
                group.addTask {
                    await input(
                        for: file,
                        maximumPixelSize: maximumPixelSize,
                        source: source,
                    )
                }
            }

            for _ in 0 ..< concurrency where nextIndex < files.count {
                enqueue(files[nextIndex])
                nextIndex += 1
            }

            while let decoded = await group.next() {
                guard !Task.isCancelled else {
                    group.cancelAll()
                    return
                }
                if let decoded {
                    inputs.append(decoded)
                }
                if nextIndex < files.count {
                    enqueue(files[nextIndex])
                    nextIndex += 1
                }
            }
        }

        guard !Task.isCancelled else { return nil }
        return await analyzer.calibrate(
            from: inputs,
            baseConfiguration: baseConfiguration,
            thresholdPercentile: thresholdPercentile,
            minimumSuccessfulImages: minimumSuccessfulImages,
            maximumConcurrentTasks: maximumConcurrentTasks,
        )
    }

    private func input(
        for file: RawCullPhotoAnalysisFile,
        maximumPixelSize: Int,
        source: SharpnessScoringSource,
    ) async -> PhotoAnalysisInput? {
        let boundedSize = maximumPixelSize > 0
            ? min(maximumPixelSize, SharpnessScoringSizeOption.maximumPixelSize)
            : SharpnessScoringSizeOption.maximumPixelSize
        let image: CGImage? = switch source {
        case .embeddedPreview:
            await RawParserKitImageLoader.shared.thumbnailCGImage(
                for: file.url,
                maxPixelSize: boundedSize,
            )

        case .rawDemosaic:
            await Task { @concurrent in
                Self.decodeDemosaicedRawThumbnail(at: file.url, maximumPixelSize: boundedSize)
            }.value
        }

        guard !Task.isCancelled, let image else { return nil }
        return PhotoAnalysisInput(
            image: image,
            iso: file.iso,
            aperture: file.aperture,
            normalizedAFPoint: file.normalizedAFPoint,
        )
    }

    private static func adapt(
        _ result: PhotoAnalysisResult,
        scoringSource: SharpnessScoringSource,
    ) -> (score: Float?, saliency: SaliencyInfo?, breakdown: SharpnessBreakdown?) {
        let saliency = result.saliency.map {
            SaliencyInfo(
                subjectLabel: $0.subjectLabel,
                subjectConfidence: $0.subjectConfidence,
            )
        }
        let breakdown = result.breakdown.map {
            SharpnessBreakdown(package: $0, scoringSource: scoringSource)
        }
        return (result.score, saliency, breakdown)
    }

    private static func decodeDemosaicedRawThumbnail(
        at url: URL,
        maximumPixelSize: Int,
    ) -> CGImage? {
        guard !Task.isCancelled, let rawFilter = CIRAWFilter(imageURL: url) else { return nil }

        rawFilter.sharpnessAmount = 0.0
        rawFilter.detailAmount = 0.6
        rawFilter.contrastAmount = 1.0
        rawFilter.exposure = 0.0

        guard var image = rawFilter.outputImage else { return nil }
        let maximumDimension = max(image.extent.width, image.extent.height)
        if maximumDimension > CGFloat(maximumPixelSize), maximumDimension > 0 {
            let scale = CGFloat(maximumPixelSize) / maximumDimension
            image = image.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
        }

        guard !Task.isCancelled else { return nil }
        let context = CIContext(options: [
            .workingColorSpace: NSNull(),
            .workingFormat: CIFormat.RGBAf,
        ])
        return context.createCGImage(image, from: image.extent)
    }
}
