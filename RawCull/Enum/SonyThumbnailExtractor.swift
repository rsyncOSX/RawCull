//
//  SonyThumbnailExtractor.swift
//  RawCull
//
//  Created by Thomas Evensen on 19/02/2026.
//

import AppKit
import Foundation

enum SonyThumbnailExtractor {
    /// Extract thumbnail using generic ImageIO framework.
    /// - Parameters:
    ///   - url: The URL of the RAW image file.
    ///   - maxDimension: Maximum pixel size for the longest edge of the thumbnail.
    ///   - qualityCost: Interpolation cost.
    /// - Returns: A `CGImage` thumbnail.
    static func extractSonyThumbnail(
        from url: URL,
        maxDimension: CGFloat,
        qualityCost: Int = 4,
    ) async throws -> CGImage {
        try await CancellableImageIOWork.run(qos: .userInitiated) { token in
            try Self.extractSync(
                from: url,
                maxDimension: maxDimension,
                qualityCost: qualityCost,
                cancellationToken: token,
            )
        }
    }

    // MARK: - Private

    private nonisolated static func extractSync(
        from url: URL,
        maxDimension: CGFloat,
        qualityCost: Int,
        cancellationToken: ImageIOCancellationToken,
    ) throws -> CGImage {
        try cancellationToken.checkCancellation()

        let sourceOptions = [kCGImageSourceShouldCache: false] as CFDictionary

        guard let source = CGImageSourceCreateWithURL(url as CFURL, sourceOptions) else {
            throw ThumbnailError.invalidSource
        }

        // Use the embedded JPEG preview that all Sony ARW files contain in IFD0.
        // kCGImageSourceCreateThumbnailFromImageAlways forces ImageIO to synthesize
        // a thumbnail from the full RAW data (RA16 on A7V), which fails with err=-50.
        // kCGImageSourceCreateThumbnailFromImageIfAbsent uses the embedded preview
        // when one exists — which it always does in ARW — and only synthesizes if not.
        let thumbOptions: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageIfAbsent: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maxDimension,
            kCGImageSourceShouldCacheImmediately: true
        ]

        // ImageIO path: works for A1, A1 II, A7R V. Falls back for ARW 6.0 (A7V / RA16).
        try cancellationToken.checkCancellation()
        var rawThumbnail = CGImageSourceCreateThumbnailAtIndex(source, 0, thumbOptions as CFDictionary)
        if rawThumbnail == nil {
            rawThumbnail = try Self.binaryFallbackThumbnail(
                from: url,
                maxDimension: maxDimension,
                cancellationToken: cancellationToken,
            )
        }

        guard let rawThumbnail else {
            throw ThumbnailError.generationFailed
        }

        try cancellationToken.checkCancellation()
        return try rerender(rawThumbnail, qualityCost: qualityCost)
    }

    /// Binary fallback for ARW 6.0 files where the macOS RA16 decoder returns err=-50.
    /// Reads the embedded preview JPEG directly from the file without going through ImageIO's
    /// raw decoder, then asks ImageIO to thumbnail the extracted JPEG bytes.
    private nonisolated static func binaryFallbackThumbnail(
        from url: URL,
        maxDimension: CGFloat,
        cancellationToken: ImageIOCancellationToken,
    ) throws -> CGImage? {
        try cancellationToken.checkCancellation()

        guard let locations = SonyMakerNoteParser.embeddedJPEGLocations(from: url),
              let loc = locations.preview ?? locations.thumbnail ?? locations.fullJPEG
        else { return nil }

        try cancellationToken.checkCancellation()

        guard let data = SonyMakerNoteParser.readEmbeddedJPEGData(at: loc, from: url),
              let src = CGImageSourceCreateWithData(data as CFData, nil)
        else { return nil }

        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maxDimension,
            kCGImageSourceShouldCacheImmediately: true
        ]

        try cancellationToken.checkCancellation()
        return CGImageSourceCreateThumbnailAtIndex(src, 0, options as CFDictionary)
    }

    private nonisolated static func rerender(_ image: CGImage, qualityCost: Int) throws -> CGImage {
        let interpolationQuality: CGInterpolationQuality = switch qualityCost {
        case 1 ... 2: .low
        case 3 ... 4: .medium
        default: .high
        }

        guard let colorSpace = CGColorSpace(name: CGColorSpace.sRGB) else {
            throw ThumbnailError.contextCreationFailed
        }

        let bitmapInfo = CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue)

        guard let context = CGContext(
            data: nil,
            width: image.width,
            height: image.height,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: colorSpace,
            bitmapInfo: bitmapInfo.rawValue,
        ) else {
            throw ThumbnailError.contextCreationFailed
        }

        context.interpolationQuality = interpolationQuality
        context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))

        guard let result = context.makeImage() else {
            throw ThumbnailError.generationFailed
        }

        return result
    }
}
