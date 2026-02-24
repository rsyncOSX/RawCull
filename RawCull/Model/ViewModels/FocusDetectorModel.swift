import AppKit
import CoreImage
import CoreImage.CIFilterBuiltins
import Foundation
import Observation

@Observable
final class FocusDetectorModel {
    private let context = CIContext()

    func generateFocusMask(from nsImage: NSImage) async -> NSImage? {
        // 1. Corrected Conversion: NSImage -> CGImage
        // We pass nil for the rect, context, and hints to get the default full-size image.
        guard let cgImage = nsImage.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            // Fallback: If cgImage fails, try via TIFF (covers some rare image loading cases)
            guard let tiffData = nsImage.tiffRepresentation,
                  let ciFallback = CIImage(data: tiffData) else { return nil }
            return processImage(ciFallback, originalSize: nsImage.size)
        }

        let inputImage = CIImage(cgImage: cgImage)
        return processImage(inputImage, originalSize: nsImage.size)
    }

    private func processImage(_ inputImage: CIImage, originalSize: NSSize) -> NSImage? {
        // 2. Downscale for Performance (0.5)
        let scale: CGFloat = 1.0
        let scaledImage = inputImage.transformed(by: CGAffineTransform(scaleX: scale, y: scale))

        // 3. Edge Detection
        let edgeFilter = CIFilter.edges()
        edgeFilter.inputImage = scaledImage
        edgeFilter.intensity = 5.0

        guard let edges = edgeFilter.outputImage else { return nil }

        // 4. Thresholding (The "Focus" magic)
        let thresholdFilter = CIFilter.colorControls()
        thresholdFilter.inputImage = edges
        thresholdFilter.contrast = 10.0 // High contrast acts as a threshold
        thresholdFilter.brightness = 0.0

        guard let thresholdedEdges = thresholdFilter.outputImage else { return nil }

        // 5. Colorizing (Red Overlay)
        let redMatrix = CIFilter.colorMatrix()
        redMatrix.inputImage = thresholdedEdges
        redMatrix.rVector = CIVector(x: 1, y: 0, z: 0, w: 0)
        redMatrix.gVector = CIVector(x: 0, y: 0, z: 0, w: 0)
        redMatrix.bVector = CIVector(x: 0, y: 0, z: 0, w: 0)
        redMatrix.aVector = CIVector(x: 1, y: 0, z: 0, w: 0) // Alpha = Intensity

        guard let redMask = redMatrix.outputImage else { return nil }

        // 6. Render back to NSImage
        guard let outputCGImage = context.createCGImage(redMask, from: redMask.extent) else {
            return nil
        }

        return NSImage(cgImage: outputCGImage, size: originalSize)
    }
}
