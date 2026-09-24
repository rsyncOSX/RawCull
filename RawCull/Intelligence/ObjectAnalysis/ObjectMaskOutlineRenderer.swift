import CoreGraphics
import CoreImage
import CoreImage.CIFilterBuiltins

/// Turns PhotoAIKit's grayscale instance mask into a transparent white contour.
nonisolated enum ObjectMaskOutlineRenderer {
    @concurrent
    static func outline(from mask: CGImage) async -> CGImage? {
        guard mask.width > 0, mask.height > 0, !Task.isCancelled else { return nil }
        let input = CIImage(cgImage: mask)
        let extent = input.extent
        let threshold = CIFilter.colorThreshold()
        threshold.inputImage = input
        threshold.threshold = 0.5
        guard let binary = threshold.outputImage?.cropped(to: extent) else { return nil }
        let radius = min(max(Float(min(mask.width, mask.height)) / 300, 2), 14)
        let dilate = CIFilter.morphologyMaximum()
        dilate.inputImage = binary
        dilate.radius = radius
        let erode = CIFilter.morphologyMinimum()
        erode.inputImage = binary
        erode.radius = radius
        guard let outer = dilate.outputImage?.cropped(to: extent),
              let inner = erode.outputImage?.cropped(to: extent) else { return nil }
        let difference = CIFilter.differenceBlendMode()
        difference.inputImage = outer
        difference.backgroundImage = inner
        guard let contour = difference.outputImage?.cropped(to: extent) else { return nil }
        let color = CIFilter.colorMatrix()
        color.inputImage = contour
        let white = CIVector(x: 0, y: 0, z: 0, w: 1)
        color.rVector = white
        color.gVector = white
        color.bVector = white
        color.aVector = CIVector(x: 1, y: 0, z: 0, w: 0)
        guard let output = color.outputImage?.cropped(to: extent), !Task.isCancelled else { return nil }
        let context = CIContext(options: [.cacheIntermediates: false, .workingColorSpace: NSNull()])
        return context.createCGImage(output, from: extent)
    }
}
