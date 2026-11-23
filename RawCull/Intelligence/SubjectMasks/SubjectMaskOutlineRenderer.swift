import CoreGraphics
import CoreImage
import CoreImage.CIFilterBuiltins

/// Converts a filled subject mask into a thin, transparent contour for the
/// subject outline (S key). Keeping this presentation work in RawCull avoids
/// coupling PhotoAnalysisKit's focus analysis to PhotoAIKit segmentation.
nonisolated enum SubjectMaskOutlineRenderer {
    @concurrent
    static func outline(from mask: CGImage) async -> CGImage? {
        guard mask.width > 0, mask.height > 0, !Task.isCancelled else { return nil }

        let input = CIImage(cgImage: mask)
        let extent = input.extent

        // Subject masks carry their signal either in alpha (RGBA masks) or in
        // gray intensity (Review's SAM masks, white = foreground, no alpha).
        // Reading alpha from an opaque grayscale mask selects the whole frame,
        // so pick the channel from the mask's encoding before morphology.
        let extractAlpha = CIFilter.colorMatrix()
        extractAlpha.inputImage = input
        let alphaVector = usesIntensity(mask)
            ? CIVector(x: 1, y: 0, z: 0, w: 0)
            : CIVector(x: 0, y: 0, z: 0, w: 1)
        extractAlpha.rVector = alphaVector
        extractAlpha.gVector = alphaVector
        extractAlpha.bVector = alphaVector
        extractAlpha.aVector = alphaVector
        guard let alpha = extractAlpha.outputImage?.cropped(to: extent) else { return nil }

        let threshold = CIFilter.colorThreshold()
        threshold.inputImage = alpha
        threshold.threshold = 0.5
        guard let binary = threshold.outputImage?.cropped(to: extent) else { return nil }

        // A proportional radius keeps the visible stroke close to the same
        // screen width across differently sized cached masks.
        let minimumDimension = Float(min(mask.width, mask.height))
        let radius = min(max(minimumDimension / 300, 2), 14)

        let dilate = CIFilter.morphologyMaximum()
        dilate.inputImage = binary
        dilate.radius = radius

        let erode = CIFilter.morphologyMinimum()
        erode.inputImage = binary
        erode.radius = radius

        guard let outer = dilate.outputImage?.cropped(to: extent),
              let inner = erode.outputImage?.cropped(to: extent)
        else { return nil }

        let difference = CIFilter.differenceBlendMode()
        difference.inputImage = outer
        difference.backgroundImage = inner
        guard let contour = difference.outputImage?.cropped(to: extent) else { return nil }

        // Return a neutral white contour whose alpha follows the morphology
        // result. SwiftUI applies the presentation color.
        let contourAlpha = CIFilter.colorMatrix()
        contourAlpha.inputImage = contour
        let redVector = CIVector(x: 1, y: 0, z: 0, w: 0)
        contourAlpha.rVector = redVector
        contourAlpha.gVector = redVector
        contourAlpha.bVector = redVector
        contourAlpha.aVector = redVector
        guard let output = contourAlpha.outputImage?.cropped(to: extent),
              !Task.isCancelled
        else { return nil }

        return context.createCGImage(output, from: extent)
    }

    /// One context for every outline. Creating a CIContext is expensive and goes through
    /// Metal's shared shader-cache database; CIContext is thread-safe to share.
    private static let context = CIContext(options: [.cacheIntermediates: false, .workingColorSpace: NSNull()])

    /// True when the mask's foreground is encoded as gray intensity rather than alpha.
    static func usesIntensity(_ mask: CGImage) -> Bool {
        if let channel = try? SubjectMaskForeground.channel(mask) {
            return channel == .grayscaleIntensity
        }
        return [.none, .noneSkipFirst, .noneSkipLast].contains(mask.alphaInfo)
    }
}
