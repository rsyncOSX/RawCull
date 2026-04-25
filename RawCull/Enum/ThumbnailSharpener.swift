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

    /// Apply CIUnsharpMask aggressively enough to be visible on a 1616 px downsampled preview.
    /// `amount` is the slider value (0.0–3.0). It drives both intensity AND radius so the
    /// effect actually changes character as you crank it (not just a louder version of the same):
    ///   - intensity = amount (CoreImage accepts > 1.0; values 1–3 give clearly visible sharpening)
    ///   - radius scales 4.0 → 8.0 across the slider, so larger amounts also widen the edge halo
    /// At very high `amount` the result is run through CIUnsharpMask twice, which is the only way
    /// to get a really hard-edged "pop" out of a soft input.
    /// Returns nil on failure so the caller can fall back to the unsharpened image.
    nonisolated static func sharpen(_ image: CGImage, amount: Float) -> CGImage? {
        guard amount > 0 else { return image }
        let clamped = min(3.0, max(0, amount))

        let radius = 4.0 + (clamped / 3.0) * 4.0  // 4.0 → 8.0
        let intensity = clamped                    // 0.0 → 3.0

        var ci = CIImage(cgImage: image)
        let extent = ci.extent

        let filter = CIFilter.unsharpMask()
        filter.inputImage = ci
        filter.radius = radius
        filter.intensity = intensity
        guard let firstPass = filter.outputImage else { return nil }
        ci = firstPass

        // Second pass kicks in above amount=2.0 for a visibly stronger result.
        if clamped > 2.0 {
            let secondFilter = CIFilter.unsharpMask()
            secondFilter.inputImage = ci
            secondFilter.radius = radius * 0.5
            secondFilter.intensity = (clamped - 2.0)  // 0.0 → 1.0
            if let secondPass = secondFilter.outputImage {
                ci = secondPass
            }
        }

        return context.createCGImage(ci, from: extent)
    }
}
