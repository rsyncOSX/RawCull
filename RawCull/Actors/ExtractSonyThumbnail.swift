//
//  ExtractSonyThumbnail.swift
//  RawCull
//
//  Created by Thomas Evensen on 11/02/2026.
//

import AppKit
import Foundation

actor ExtractSonyThumbnail {
    /// Extract thumbnail using generic ImageIO framework
    /// qualityCost: 1-8 level of interpolation quality (not bytes per pixel - memory is always 4 bytes RGBA)
    @concurrent
    nonisolated func extractSonyThumbnail(from url: URL, maxDimension: CGFloat, qualityCost: Int = 4) async throws -> CGImage {
        try await Task.detached(priority: .userInitiated) {
            let options = [kCGImageSourceShouldCache: false] as CFDictionary

            guard let source = CGImageSourceCreateWithURL(url as CFURL, options) else {
                throw ThumbnailError.invalidSource
            }

            // Map quality cost to interpolation quality
            let interpolationQuality: CGInterpolationQuality
            switch qualityCost {
            case 1 ... 2:
                interpolationQuality = .low

            case 3 ... 4:
                interpolationQuality = .medium

            default: // 5...8
                interpolationQuality = .high
            }

            let thumbOptions: [CFString: Any] = [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceThumbnailMaxPixelSize: maxDimension,
                kCGImageSourceShouldCacheImmediately: false
            ]

            guard var image = CGImageSourceCreateThumbnailAtIndex(source, 0, thumbOptions as CFDictionary) else {
                throw ThumbnailError.generationFailed
            }

            // Apply interpolation quality through image rendering context
            if qualityCost != 4 { // Only reprocess if different from default
                let colorSpace = CGColorSpaceCreateDeviceRGB()
                if let context = CGContext(data: nil,
                                           width: image.width,
                                           height: image.height,
                                           bitsPerComponent: image.bitsPerComponent,
                                           bytesPerRow: 0,
                                           space: colorSpace,
                                           bitmapInfo: image.bitmapInfo.rawValue) {
                    context.interpolationQuality = interpolationQuality
                    context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
                    if let processedImage = context.makeImage() {
                        image = processedImage
                    }
                }
            }

            return image
        }.value
    }
}
