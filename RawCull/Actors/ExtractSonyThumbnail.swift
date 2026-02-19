//
//  ExtractSonyThumbnail.swift
//  RawCull
//
//  Created by Thomas Evensen on 11/02/2026.
//

import AppKit
import Foundation

actor ExtractSonyThumbnail {
    /// Extract thumbnail using generic ImageIO framework.
    /// - Parameters:
    ///   - url: The URL of the RAW image file.
    ///   - maxDimension: Maximum pixel size for the longest edge of the thumbnail.
    ///   - qualityCost: Interpolation cost on a scale of 1–8. Memory is always 4 bytes (RGBA)
    ///                  regardless of this value. Higher values produce better quality at more CPU cost.
    ///                  Defaults to 4 (medium).
    /// - Returns: A `CGImage` thumbnail.
    /// - Throws: `ThumbnailError.invalidSource`, `ThumbnailError.generationFailed`,
    ///           or `ThumbnailError.contextCreationFailed`.
    func extractSonyThumbnail(
        from url: URL,
        maxDimension: CGFloat,
        qualityCost: Int = 4
    ) async throws -> CGImage {
        // Hop off the actor onto a background thread for the blocking ImageIO work
        try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                do {
                    let image = try Self.extractSync(from: url, maxDimension: maxDimension, qualityCost: qualityCost)
                    continuation.resume(returning: image)
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    // MARK: - Private

    private static func extractSync(
        from url: URL,
        maxDimension: CGFloat,
        qualityCost: Int
    ) throws -> CGImage {
        // kCGImageSourceShouldCache: false — avoids caching the full RAW decode at source creation
        let sourceOptions = [kCGImageSourceShouldCache: false] as CFDictionary

        guard let source = CGImageSourceCreateWithURL(url as CFURL, sourceOptions) else {
            throw ThumbnailError.invalidSource
        }

        let thumbOptions: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,   // Respect EXIF orientation
            kCGImageSourceThumbnailMaxPixelSize: maxDimension,
            kCGImageSourceShouldCacheImmediately: true          // Pre-decode — we render immediately after
        ]

        guard let rawThumbnail = CGImageSourceCreateThumbnailAtIndex(source, 0, thumbOptions as CFDictionary) else {
            throw ThumbnailError.generationFailed
        }

        // Re-render into a known-good colour space and fixed bitmap format.
        // CGImageSourceCreateThumbnailAtIndex may return an image with an unusual alpha/colour-space
        // combination that is incompatible with later CGContext operations, so we normalise here.
        return try rerender(rawThumbnail, qualityCost: qualityCost)
    }

    private static func rerender(_ image: CGImage, qualityCost: Int) throws -> CGImage {
        let interpolationQuality: CGInterpolationQuality
        switch qualityCost {
        case 1 ... 2:
            interpolationQuality = .low
        case 3 ... 4:
            interpolationQuality = .medium
        default: // 5...8
            interpolationQuality = .high
        }

        let colorSpace = CGColorSpaceCreateDeviceRGB()

        // Use a fixed, known-good bitmap format (premultipliedLast / RGBA) instead of forwarding
        // the source image's bitmapInfo, which can carry unsupported alpha flags for some RAW files.
        let bitmapInfo = CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue)

        guard let context = CGContext(
            data: nil,
            width: image.width,
            height: image.height,
            bitsPerComponent: 8,           // Fixed 8 bpc to match premultipliedLast / RGBA
            bytesPerRow: 0,                // Let CoreGraphics compute the optimal stride
            space: colorSpace,
            bitmapInfo: bitmapInfo.rawValue
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
