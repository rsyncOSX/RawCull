//
//  ThumbnailSharpener.swift
//  RawCull
//
//  Created by Thomas Evensen on 25/04/2026.
//

import CoreImage
import CoreImage.CIFilterBuiltins

enum ThumbnailSharpener {
    private nonisolated static let context = CIContext(options: [.useSoftwareRenderer: false])

    /// Apply CIUnsharpMask. `amount` (0.0–1.0) maps to CIUnsharpMask.intensity; radius held at 2.5.
    /// Returns nil on failure so the caller can fall back to the unsharpened image.
    nonisolated static func sharpen(_ image: CGImage, amount: Float) -> CGImage? {
        guard amount > 0 else { return image }
        let ci = CIImage(cgImage: image)
        let filter = CIFilter.unsharpMask()
        filter.inputImage = ci
        filter.radius = 2.5
        filter.intensity = max(0, min(1, amount))
        guard let output = filter.outputImage else { return nil }
        return context.createCGImage(output, from: ci.extent)
    }
}
