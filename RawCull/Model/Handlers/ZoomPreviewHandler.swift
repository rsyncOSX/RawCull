//
//  ZoomPreviewHandler.swift
//  RawCull
//
//  Created by Thomas Evensen on 08/02/2026.
//

import CoreImage
import RawParserKit
import SwiftUI

/// Type to handle JPG/preview extraction and window opening
enum ZoomPreviewHandler {
    enum DevelopedRAWError: Error { case decodingFailed }

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
        maximumDimension: Int? = nil,
        preservingImage: Bool = false,
        renderRAW: @escaping @MainActor (URL, Int?, Double?) async throws -> RAWPreviewRenderer.Preview = { url, dimension, exposure in
            try await loadOverlayRAWPreview(url: url, maximumDimension: dimension, inspectionExposureEV: exposure)
        },
        loadAnalysis: @escaping @MainActor (FileItem, Int) async -> CGImage? = { file, size in
            await loadThumbnailPreview(for: file, thumbnailSizePreview: size)
        },
        onFinished: @escaping @MainActor () -> Void = {},
        onDevelopedRAWFailure: @escaping @MainActor () -> Void = {},
    ) -> Task<Void, Never> {
        if source == .thumbnail {
            Task {
                defer { onFinished() }
                guard !Task.isCancelled else { return }
                let settings = await SettingsViewModel.shared.asyncgetsettings()
                guard !Task.isCancelled else { return }

                await MainActor.run {
                    guard !Task.isCancelled else { return }
                    viewModel.zoomOverlayCGImage = nil
                    viewModel.zoomOverlayNativeSize = nil
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
                defer { onFinished() }
                guard !Task.isCancelled else { return }
                await MainActor.run {
                    guard !Task.isCancelled else { return }
                    if !preservingImage {
                        viewModel.zoomOverlayNSImage = nil
                        viewModel.zoomOverlayCGImage = nil
                        viewModel.zoomOverlayNativeSize = nil
                        viewModel.zoomOverlayAnalysisCGImage = nil
                    }
                    viewModel.zoomOverlayVisible = true
                }

                guard !Task.isCancelled else { return }

                async let analysisImage = loadAnalysis(file, thumbnailSizePreview)
                let image: CGImage?
                var nativeSize: CGSize?
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
                        let access = await RawCullCatalogAccess.shared.retainAccess(for: [file.url])
                        defer { withExtendedLifetime(access) {} }
                        let preview = try await renderRAW(file.url, maximumDimension, evaluateExposure ? exposureEV : nil)
                        image = preview.image
                        nativeSize = preview.nativeSize
                    } catch is CancellationError {
                        return
                    } catch {
                        guard !Task.isCancelled else { return }
                        await MainActor.run { onDevelopedRAWFailure() }
                        return
                    }
                }

                if let image {
                    await MainActor.run {
                        guard !Task.isCancelled else { return }
                        viewModel.zoomOverlayNativeSize = nativeSize
                        viewModel.zoomOverlayCGImage = image
                    }
                }
                let resolvedAnalysisImage = await analysisImage
                guard !Task.isCancelled else { return }
                viewModel.zoomOverlayAnalysisCGImage = resolvedAnalysisImage ?? image
            }
        }
    }

    /// Keep the established native-resolution JPEG/disk-cache policy: real-file
    /// measurements did not justify replacing it with direct native rendering.
    @concurrent
    static func loadOverlayRAWPreview(
        url: URL,
        maximumDimension: Int?,
        inspectionExposureEV: Double?,
        renderer: RAWPreviewRenderer = .shared,
        diskCache: FullSizeJPGDiskCache? = nil
    ) async throws -> RAWPreviewRenderer.Preview {
        if maximumDimension != nil, inspectionExposureEV == nil {
            let key = try RAWPreviewCache.Key(url: url, maximumDimension: maximumDimension, inspectionExposureEV: nil)
            if let preview = try await renderer.cachedPreview(for: key) { return preview }
            // Preserve fast opens for photos developed in an earlier session. The existing
            // full-size JPEG is already suitable for fit view; no new RAW decode is needed.
            if let image = await (diskCache ?? fullSizeCache).load(for: url, variant: .developedRAW) {
                try Task.checkCancellation()
                return RAWPreviewRenderer.Preview(image: image, nativeSize: CGSize(width: image.width, height: image.height))
            }
        }
        if maximumDimension != nil || inspectionExposureEV != nil {
            return try await renderer.render(
                url: url, maximumDimension: maximumDimension, inspectionExposureEV: inspectionExposureEV
            )
        }
        // Release the inspection/fit RAW graph before developing a full-size JPEG.
        await renderer.releaseSource()
        let image = try await loadDevelopedRAWPreview(for: url)
        try Task.checkCancellation()
        return RAWPreviewRenderer.Preview(image: image, nativeSize: CGSize(width: image.width, height: image.height))
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

    /// Loupe and burst previews keep their existing full-size persistent-JPEG policy.
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
