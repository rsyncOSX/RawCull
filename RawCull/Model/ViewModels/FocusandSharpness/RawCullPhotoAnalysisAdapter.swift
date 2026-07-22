import CoreImage
import CoreImage.CIFilterBuiltins
import Foundation
import OSLog
import PhotoAnalysisKit
import RawCullCore

nonisolated struct RawCullPhotoAnalysisFile: Sendable {
    let url: URL
    let iso: Int
    let aperture: Double?
    let normalizedAFPoint: CGPoint?
}

nonisolated struct RawCullPhotoAnalysisRequest<Identifier: Sendable>: Sendable {
    let id: Identifier
    let file: RawCullPhotoAnalysisFile
}

nonisolated struct RawCullPhotoAnalysisResult<Identifier: Sendable>: Sendable {
    let id: Identifier
    let score: Float?
    let saliency: SaliencyInfo?
    let breakdown: SharpnessBreakdown?
}

/// Adapts RawCull file loading and source selection to PhotoAnalysisKit's
/// decoded-image API. No application model or persistence state crosses into
/// the package.
nonisolated struct RawCullPhotoAnalysisAdapter: Sendable {
    typealias InputLoader = @Sendable (
        RawCullPhotoAnalysisFile,
        Int,
        SharpnessScoringSource,
    ) async -> PhotoAnalysisInput?

    private let analyzer = PhotoAnalyzer()
    private let inputLoaderOverride: InputLoader?

    init(inputLoaderOverride: InputLoader? = nil) {
        self.inputLoaderOverride = inputLoaderOverride
    }

    func analyzeBatch<Identifier: Sendable>(
        requests: [RawCullPhotoAnalysisRequest<Identifier>],
        configuration: FocusDetectorConfig,
        maximumPixelSize: Int,
        source: SharpnessScoringSource,
        maximumConcurrentTasks: Int,
        progress: (@Sendable (_ completedCount: Int, _ totalCount: Int) async -> Void)? = nil,
    ) async -> [RawCullPhotoAnalysisResult<Identifier>]? {
        Logger.process.debugMessageOnly(
            "RawCullPhotoAnalysisAdapter.analyzeBatch(): analyzing \(requests.count) requests",
        )
        let packageRequests = requests.map { request in
            PhotoAnalysisBatchRequest(id: request.id) {
                await input(
                    for: request.file,
                    maximumPixelSize: maximumPixelSize,
                    source: source,
                )
            }
        }
        guard let results = await analyzer.analyzeBatch(
            packageRequests,
            configuration: configuration,
            maximumConcurrentTasks: maximumConcurrentTasks,
            progress: { update in
                await progress?(update.completedCount, update.totalCount)
            },
        ) else {
            Logger.process.debugMessageOnly(
                "RawCullPhotoAnalysisAdapter.analyzeBatch(): analyzer returned no results",
            )
            return nil
        }

        Logger.process.debugMessageOnly(
            "RawCullPhotoAnalysisAdapter.analyzeBatch(): received \(results.count) results",
        )
        return results.map { result in
            Self.adapt(result, scoringSource: source)
        }
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
        Logger.process.debugMessageOnly(
            "RawCullPhotoAnalysisAdapter.calibrate(): calibrating with \(files.count) files",
        )
        guard !files.isEmpty else {
            Logger.process.debugMessageOnly(
                "RawCullPhotoAnalysisAdapter.calibrate(): skipped because no files were supplied",
            )
            return nil
        }
        let requests = files.enumerated().map { index, file in
            PhotoAnalysisBatchRequest(id: index) {
                await input(
                    for: file,
                    maximumPixelSize: maximumPixelSize,
                    source: source,
                )
            }
        }
        let result = await analyzer.calibrate(
            from: requests,
            baseConfiguration: baseConfiguration,
            thresholdPercentile: thresholdPercentile,
            minimumSuccessfulImages: minimumSuccessfulImages,
            maximumConcurrentTasks: maximumConcurrentTasks,
        )
        Logger.process.debugMessageOnly(
            "RawCullPhotoAnalysisAdapter.calibrate(): calibration finished; result available: \(result != nil)",
        )
        return result
    }

    private func input(
        for file: RawCullPhotoAnalysisFile,
        maximumPixelSize: Int,
        source: SharpnessScoringSource,
    ) async -> PhotoAnalysisInput? {
        let boundedSize = maximumPixelSize > 0
            ? min(maximumPixelSize, SharpnessScoringSizeOption.maximumPixelSize)
            : SharpnessScoringSizeOption.maximumPixelSize
        if let inputLoaderOverride {
            return await inputLoaderOverride(file, boundedSize, source)
        }

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

    private static func adapt<Identifier: Sendable>(
        _ result: PhotoAnalysisBatchResult<Identifier>,
        scoringSource: SharpnessScoringSource,
    ) -> RawCullPhotoAnalysisResult<Identifier> {
        let saliency = result.analysis?.saliency.map {
            SaliencyInfo(
                subjectLabel: $0.subjectLabel,
                subjectConfidence: $0.subjectConfidence,
            )
        }
        let breakdown = result.analysis?.breakdown.map {
            SharpnessBreakdown(package: $0, scoringSource: scoringSource)
        }
        return RawCullPhotoAnalysisResult(
            id: result.id,
            score: result.analysis?.score,
            saliency: saliency,
            breakdown: breakdown,
        )
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
            .workingFormat: CIFormat.RGBAf
        ])
        return context.createCGImage(image, from: image.extent)
    }
}
