//
//  ZoomPreviewHandler.swift
//  RawCull
//
//  Created by Thomas Evensen on 08/02/2026.
//

import RawParserKit
import CoreImage
import SwiftUI

/// Type to handle JPG/preview extraction and window opening
enum ZoomPreviewHandler {
    enum DevelopedRAWError: Error {
        case decodingFailed
    }

    private nonisolated static var fullSizeCache: FullSizeJPGDiskCache {
        SharedMemoryCache.shared.fullSizeJPGDiskCache
    }

    @discardableResult
    static func handleOverlay(
        file: FileItem,
        source: ImagePreviewSource = .embeddedJPG,
        thumbnailSizePreview: Int = 1616,
        viewModel: RawCullViewModel,
        evaluateExposure: Bool = false,
        exposureEV: Double = 0,
        onDevelopedRAWFailure: @escaping @MainActor () -> Void = {},
    ) -> Task<Void, Never> {
        if source == .thumbnail {
            Task {
                let settings = await SettingsViewModel.shared.asyncgetsettings()

                await MainActor.run {
                    viewModel.zoomOverlayCGImage = nil
                    viewModel.zoomOverlayAnalysisCGImage = nil
                    viewModel.zoomOverlayNSImage = nil
                }

                let cgThumb = await RequestThumbnail.shared.requestThumbnail(
                    for: file.url,
                    targetSize: thumbnailSizePreview,
                    purpose: .preview,
                )

                guard !Task.isCancelled else { return }

                let displayImage: CGImage?
                if settings.enableThumbnailSharpening {
                    let url = file.url
                    let size = CGFloat(thumbnailSizePreview)
                    let amount = settings.thumbnailSharpenAmount
                    let sharpened = await Task.detached(priority: .userInitiated) { () -> CGImage? in
                        guard let image = ThumbnailSharpener.sharpenedPreview(from: url, maxDimension: size, amount: amount, useRAW9: true) else {
                            return nil
                        }
                        return OrientationNormalizedImageLoader.applyingSourceOrientation(to: image, from: url)
                    }.value
                    displayImage = sharpened ?? cgThumb
                } else {
                    displayImage = cgThumb
                }

                await MainActor.run {
                    guard !Task.isCancelled else { return }
                    viewModel.zoomOverlayAnalysisCGImage = cgThumb
                    if let displayImage {
                        viewModel.zoomOverlayNSImage = NSImage(cgImage: displayImage, size: .zero)
                    }
                    viewModel.zoomOverlayVisible = true
                }
            }
        } else {
            Task {
                await MainActor.run {
                    viewModel.zoomOverlayNSImage = nil
                    viewModel.zoomOverlayCGImage = nil
                    viewModel.zoomOverlayAnalysisCGImage = nil
                    viewModel.zoomOverlayVisible = true
                }

                guard !Task.isCancelled else { return }

                async let analysisImage = loadThumbnailPreview(for: file, thumbnailSizePreview: thumbnailSizePreview)
                let image: CGImage?
                switch source {
                case .thumbnail:
                    image = nil

                case .embeddedJPG:
                    if let extractedPreview = await loadExtractedJPGPreview(for: file.url) {
                        image = extractedPreview
                    } else {
                        image = await loadThumbnailPreview(for: file, thumbnailSizePreview: thumbnailSizePreview)
                    }

                case .developedRAW:
                    do {
                        if evaluateExposure {
                            image = try await RAWExposurePreviewRenderer.shared.render(
                                url: file.url, exposureEV: exposureEV,
                            )
                        } else {
                            image = try await loadDevelopedRAWPreview(for: file.url)
                        }
                    } catch is CancellationError {
                        return
                    } catch {
                        guard !Task.isCancelled else { return }
                        await MainActor.run { onDevelopedRAWFailure() }
                        return
                    }
                }

                let resolvedAnalysisImage = await analysisImage
                if let image {
                    await MainActor.run {
                        guard !Task.isCancelled else { return }
                        viewModel.zoomOverlayAnalysisCGImage = resolvedAnalysisImage ?? image
                        viewModel.zoomOverlayCGImage = image
                    }
                }
            }
        }
    }

    static func loadExtractedJPGPreview(for rawURL: URL) async -> CGImage? {
        await FullSizePreviewLoader.shared.loadEmbeddedPreview(for: rawURL)
    }

    private static func loadThumbnailPreview(for file: FileItem, thumbnailSizePreview: Int) async -> CGImage? {
        await RequestThumbnail.shared.requestThumbnail(
            for: file.url,
            targetSize: thumbnailSizePreview,
            purpose: .preview,
        )
    }

    @concurrent
    static func loadDevelopedRAWPreview(for rawURL: URL) async throws -> CGImage {
        if let cached = await fullSizeCache.load(for: rawURL, variant: .developedRAW) {
            try Task.checkCancellation()
            return cached
        }

        try Task.checkCancellation()
        let jpegData = try await SonyRawFormat.createFullSizeJPEG(from: rawURL, quality: 1.0, useRAW9: true)
        try Task.checkCancellation()

        guard let image = OrientationNormalizedImageLoader.loadCGImage(from: jpegData) else {
            throw DevelopedRAWError.decodingFailed
        }

        await fullSizeCache.save(jpegData, for: rawURL, variant: .developedRAW)
        try Task.checkCancellation()
        return image
    }
}

/// Serializes expensive inspection renders. Adjusted previews never enter the export/JPEG cache.
private actor RAWExposurePreviewRenderer {
    static let shared = RAWExposurePreviewRenderer()
    // Initialize on this actor's executor, not in the initializer called by the UI.
    private var context: CIContext?

    func render(url: URL, exposureEV: Double) async throws -> CGImage {
        let access = await RawCullCatalogAccess.shared.retainAccess(for: [url])
        defer { withExtendedLifetime(access) {} }
        try Task.checkCancellation()
        return try autoreleasepool {
            dispatchPrecondition(condition: .notOnQueue(.main))
            let context = self.context ?? CIContext(options: [.workingFormat: CIFormat.RGBAh])
            self.context = context
            guard let raw = CIRAWFilter(imageURL: url) else {
                throw ZoomPreviewHandler.DevelopedRAWError.decodingFailed
            }
            if let version = RAW9Support.preferredVersion(in: raw.supportedDecoderVersions) {
                raw.decoderVersion = version
            }
            raw.exposure = Float(exposureEV)
            raw.boostShadowAmount = 2
            if #available(macOS 26.0, *), raw.isHighlightRecoverySupported {
                raw.isHighlightRecoveryEnabled = true
            }
            guard let developed = raw.outputImage else {
                throw ZoomPreviewHandler.DevelopedRAWError.decodingFailed
            }
            // Compress highlights for inspection before the final display conversion.
            let inspected = developed.applyingFilter("CIHighlightShadowAdjust", parameters: [
                "inputHighlightAmount": 0.25,
                "inputShadowAmount": 0.0,
            ])
            try Task.checkCancellation()
            guard let image = context.createCGImage(
                inspected, from: inspected.extent, format: .RGBA8,
                colorSpace: CGColorSpace(name: CGColorSpace.sRGB)!,
                deferred: false,
            ) else {
                throw ZoomPreviewHandler.DevelopedRAWError.decodingFailed
            }
            try Task.checkCancellation()
            return image
        }
    }
}
