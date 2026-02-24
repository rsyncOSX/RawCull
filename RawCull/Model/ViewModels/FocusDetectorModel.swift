import AppKit
import CoreImage
import CoreImage.CIFilterBuiltins
import Observation

@Observable
final class FocusDetectorModel {
    private let context = CIContext(options: [.workingColorSpace: NSNull()]) // Performance: skip color management for masks

    func generateFocusMask(
        from nsImage: NSImage,
        scale: CGFloat
    ) async -> NSImage? {
        // Use a Task.detached to ensure we don't block the main actor during rendering
        await Task.detached(priority: .userInitiated) { () -> NSImage? in
            guard let cgImage = nsImage.cgImage(
                forProposedRect: nil,
                context: nil,
                hints: nil
            ) else {
                return nil
            }

            let inputImage = CIImage(cgImage: cgImage)
            return await self.processImage(
                inputImage,
                originalSize: nsImage.size,
                scale: scale
            )
        }.value
    }

    private func processImage(
        _ inputImage: CIImage,
        originalSize: NSSize,
        scale: CGFloat
    ) -> NSImage? {
        let scaledImage = inputImage.transformed(by: CGAffineTransform(scaleX: scale, y: scale))

        // 2. Sobel Gradient (More accurate for focus detection than 'edges')
        let sobelFilter = CIFilter.sobelGradients()
        sobelFilter.inputImage = scaledImage
        guard let edges = sobelFilter.outputImage else { return nil }

        // 3. Proper Thresholding (Adjust 'threshold' to change sensitivity)
        let thresholdFilter = CIFilter.colorThreshold()
        thresholdFilter.inputImage = edges
        thresholdFilter.threshold = 0.15 // Lower = more sensitive (shows more "focus")

        guard let thresholdedEdges = thresholdFilter.outputImage else { return nil }

        // 4. Colorizing (Red Overlay)
        let redMatrix = CIFilter.colorMatrix()
        redMatrix.inputImage = thresholdedEdges
        redMatrix.rVector = CIVector(x: 1, y: 0, z: 0, w: 0)
        redMatrix.gVector = CIVector(x: 0, y: 0, z: 0, w: 0)
        redMatrix.bVector = CIVector(x: 0, y: 0, z: 0, w: 0)
        redMatrix.aVector = CIVector(x: 1, y: 0, z: 0, w: 0) // Alpha tied to intensity

        guard let redMask = redMatrix.outputImage else { return nil }

        // 5. Render
        // Note: We render the 'extent' of the mask, which is already scaled down.
        guard let outputCGImage = context.createCGImage(redMask, from: redMask.extent) else {
            return nil
        }

        // NSImage will upscale this back to the 'originalSize' when drawn
        return NSImage(cgImage: outputCGImage, size: originalSize)
    }
}
