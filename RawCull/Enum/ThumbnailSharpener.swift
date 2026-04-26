//
//  ThumbnailSharpener.swift
//  RawCull
//
//  Created by Thomas Evensen on 25/04/2026.
//

import CoreImage
import CoreImage.CIFilterBuiltins
import Foundation

enum ThumbnailSharpener {
    private nonisolated static let context = CIContext(options: [.useSoftwareRenderer: false])

    /// Build a sharpened preview from the demosaiced raw via `CIRAWFilter`.
    ///
    /// This bypasses Sony's embedded JPEG preview entirely. The embedded JPEG already has Sony's
    /// in-camera sharpening baked in and JPEG quantization that has stripped most fine detail,
    /// so an `unsharpMask` on it produces halos around existing edges instead of recovering
    /// texture. Working off the demosaiced sensor data gives the sharpen stages something
    /// real to act on.
    ///
    /// `amount` is the slider value (0.0–2.0) and drives both sharpen stages:
    ///   - `unsharpMask` intensity = amount * 0.4 (radius held at 0.8 for micro-detail)
    ///   - `sharpenLuminance` sharpness = amount * 0.3 (luminance edges only, halo-free)
    ///
    /// Returns nil when `CIRAWFilter` cannot decode the source (e.g. ARW 6.0 / RA16 from A7V),
    /// so the caller can fall back to the cached embedded-JPEG thumbnail.
    nonisolated static func sharpenedPreview(
        from url: URL,
        maxDimension: CGFloat,
        amount: Float,
    ) -> CGImage? {
        guard let rawFilter = CIRAWFilter(imageURL: url) else { return nil }

        rawFilter.sharpnessAmount = 0.0
        rawFilter.detailAmount = 0.6
        rawFilter.contrastAmount = 1.0
        rawFilter.exposure = 0.0
        rawFilter.neutralChromaticity = CGPoint(x: 0.3457, y: 0.3585)

        guard var ci = rawFilter.outputImage else { return nil }

        let toneFilter = CIFilter.colorControls()
        toneFilter.inputImage = ci
        toneFilter.contrast = 1.05
        toneFilter.saturation = 1.0
        toneFilter.brightness = 0.0
        if let toned = toneFilter.outputImage { ci = toned }

        let nrFilter = CIFilter.noiseReduction()
        nrFilter.inputImage = ci
        nrFilter.noiseLevel = 0.02
        nrFilter.sharpness = 0.4
        if let denoised = nrFilter.outputImage { ci = denoised }

        let extent = ci.extent
        let scale = maxDimension / max(extent.width, extent.height)
        if scale < 1.0 {
            ci = ci.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
        }

        if amount > 0 {
            let unsharp = CIFilter.unsharpMask()
            unsharp.inputImage = ci
            unsharp.radius = 0.8
            unsharp.intensity = amount * 0.4
            if let pass1 = unsharp.outputImage { ci = pass1 }

            let luma = CIFilter.sharpenLuminance()
            luma.inputImage = ci
            luma.sharpness = amount * 0.3
            if let pass2 = luma.outputImage { ci = pass2 }
        }

        return context.createCGImage(ci, from: ci.extent)
    }
}
