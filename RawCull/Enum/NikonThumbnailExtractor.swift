//
//  NikonThumbnailExtractor.swift
//  RawCull
//
//  Created by Thomas Evensen on 20/04/2026.
//

import AppKit
import Foundation

enum NikonThumbnailExtractor {
    /// Extract thumbnail using generic ImageIO framework.
    /// - Parameters:
    ///   - url: The URL of the RAW image file.
    ///   - maxDimension: Maximum pixel size for the longest edge of the thumbnail.
    ///   - qualityCost: Interpolation cost.
    /// - Returns: A `CGImage` thumbnail.
    static func extractNikonThumbnail(
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

        let thumbOptions: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageIfAbsent: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maxDimension,
            kCGImageSourceShouldCacheImmediately: true
        ]

        try cancellationToken.checkCancellation()
        guard let raw = CGImageSourceCreateThumbnailAtIndex(source, 0, thumbOptions as CFDictionary) else {
            throw ThumbnailError.generationFailed
        }

        try cancellationToken.checkCancellation()
        return try rerender(raw, qualityCost: qualityCost)
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
