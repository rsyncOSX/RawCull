//
//  ZoomPreviewHandler.swift
//  RawCull
//
//  Created by Thomas Evensen on 08/02/2026.
//

import RawParserKit
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
        onDevelopedRAWFailure: @escaping @MainActor () -> Void = {},
    ) -> Task<Void, Never> {
        if source == .thumbnail {
            Task {
                let settings = await SettingsViewModel.shared.asyncgetsettings()

                await MainActor.run {
                    viewModel.zoomOverlayCGImage = nil
                    viewModel.zoomOverlayNSImage = nil
                }

                let cgThumb = await RequestThumbnail.shared.requestThumbnail(
                    for: file.url,
                    targetSize: thumbnailSizePreview,
                )

                guard !Task.isCancelled else { return }

                let displayImage: CGImage?
                if settings.enableThumbnailSharpening {
                    let url = file.url
                    let size = CGFloat(thumbnailSizePreview)
                    let amount = settings.thumbnailSharpenAmount
                    let sharpened = await Task.detached(priority: .userInitiated) { () -> CGImage? in
                        guard let image = ThumbnailSharpener.sharpenedPreview(from: url, maxDimension: size, amount: amount) else {
                            return nil
                        }
                        return OrientationNormalizedImageLoader.applyingSourceOrientation(to: image, from: url)
                    }.value
                    displayImage = sharpened ?? cgThumb
                } else {
                    displayImage = cgThumb
                }

                await MainActor.run {
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
                    viewModel.zoomOverlayVisible = true
                }

                guard !Task.isCancelled else { return }

                let image: CGImage?
                switch source {
                case .thumbnail:
                    image = nil

                case .embeddedJPG:
                    image = await loadExtractedJPGPreview(for: file.url)

                case .developedRAW:
                    do {
                        image = try await loadDevelopedRAWPreview(for: file.url)
                    } catch is CancellationError {
                        return
                    } catch {
                        await MainActor.run { onDevelopedRAWFailure() }
                        return
                    }
                }

                if let image {
                    await MainActor.run {
                        guard !Task.isCancelled else { return }
                        viewModel.zoomOverlayCGImage = image
                    }
                }
            }
        }
    }

    static func loadExtractedJPGPreview(for rawURL: URL) async -> CGImage? {
        let sidecarJPGURL = rawURL
            .deletingPathExtension()
            .appendingPathExtension(SupportedFileType.jpg.rawValue)

        let sidecarImage = await Task.detached(priority: .userInitiated) {
            OrientationNormalizedImageLoader.loadCGImage(from: sidecarJPGURL)
        }.value

        guard !Task.isCancelled else { return nil }
        if let sidecarImage {
            return sidecarImage
        }

        if let cached = await fullSizeCache.load(for: rawURL) {
            guard !Task.isCancelled else { return nil }
            return cached
        }

        guard !Task.isCancelled,
              let format = RawFormatRegistry.format(for: rawURL)
        else { return nil }

        let orientedPreview = await Task.detached(priority: .userInitiated) {
            OrientationNormalizedImageLoader.loadSonyEmbeddedPreview(from: rawURL)
        }.value
        let extracted: CGImage? = if let orientedPreview {
            orientedPreview
        } else {
            if let image = await format.extractFullJPEG(from: rawURL, fullSize: false) {
                OrientationNormalizedImageLoader.applyingSourceOrientation(to: image, from: rawURL) ?? image
            } else {
                nil
            }
        }
        guard !Task.isCancelled else { return nil }

        if let extracted,
           let jpegData = FullSizeJPGDiskCache.jpegData(from: extracted) {
            await fullSizeCache.save(jpegData, for: rawURL)
        }

        return extracted
    }

    static func loadDevelopedRAWPreview(for rawURL: URL) async throws -> CGImage {
        if let cached = await fullSizeCache.load(for: rawURL, variant: .developedRAW) {
            try Task.checkCancellation()
            return cached
        }

        try Task.checkCancellation()
        let jpegData = try await SonyRawFormat.createFullSizeJPEG(from: rawURL, quality: 1.0)
        try Task.checkCancellation()

        guard let image = OrientationNormalizedImageLoader.loadCGImage(from: jpegData) else {
            throw DevelopedRAWError.decodingFailed
        }

        await fullSizeCache.save(jpegData, for: rawURL, variant: .developedRAW)
        try Task.checkCancellation()
        return image
    }
}
