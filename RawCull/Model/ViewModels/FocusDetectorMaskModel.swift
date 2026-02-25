import AppKit
import CoreImage
import CoreImage.CIFilterBuiltins
import Observation
import OSLog

@Observable
final class FocusDetectorMaskModel: @unchecked Sendable {
    /// CIContext is thread-safe for rendering; created once for performance.
    /// @unchecked Sendable is safe here since context is read-only after init.
    private let context = CIContext(options: [.workingColorSpace: NSNull()])

    /// Static property to load the Metal kernel
    private static let magnitudeKernel: CIKernel? = {
        guard let url = Bundle.main.url(forResource: "default", withExtension: "metallib"),
              let data = try? Data(contentsOf: url)
        else {
            return nil
        }
        do {
            // Loading as a general CIKernel to allow neighbor sampling (sampler)
            return try CIKernel(functionName: "focusLaplacian", fromMetalLibraryData: data)
        } catch {
            print("FocusDetector: Failed to load: \(error)")
            return nil
        }
    }()

    func generateFocusMask(
        from nsImage: NSImage,
        scale: CGFloat
    ) async -> NSImage? {
        // Extract what we need from NSImage before entering the detached task,
        // avoiding implicit capture of 'self' or non-Sendable NSImage across actor boundaries.
        guard let cgImage = nsImage.cgImage(
            forProposedRect: nil,
            context: nil,
            hints: nil
        ) else { return nil }

        let originalSize = nsImage.size
        let context = self.context

        return await Task.detached(priority: .userInitiated) {
            let inputImage = CIImage(cgImage: cgImage)
            return await Self.processImage(
                inputImage,
                originalSize: originalSize,
                scale: scale,
                context: context
            )
        }.value
    }

    static func processImage(
        _ inputImage: CIImage,
        originalSize: NSSize,
        scale: CGFloat,
        context: CIContext
    ) -> NSImage? {
        // 1. Scale down for performance
        let scaledImage = inputImage.transformed(by: CGAffineTransform(scaleX: scale, y: scale))

        // 2. Pre-Blur (Crucial for the puffin's feet)
        // This smooths out soft high-contrast edges so they don't trigger the sharpness math.
        let preBlur = CIFilter.gaussianBlur()
        preBlur.inputImage = scaledImage
        preBlur.radius = 1.0
        guard let smoothedImage = preBlur.outputImage else { return nil }

        // 3. Apply custom Laplacian Kernel
        guard let laplacianKernel = self.magnitudeKernel else { return nil }

        let laplacianImage = laplacianKernel.apply(
            extent: smoothedImage.extent,
            roiCallback: { _, rect in
                // We need 1 pixel of context around each pixel to calculate sharpness
                rect.insetBy(dx: -1, dy: -1)
            },
            arguments: [smoothedImage]
        )

        guard let laplacianOutput = laplacianImage else { return nil }

        // 4. Threshold (This defines what counts as "in focus")
        // Use a higher value (0.6 - 0.75) to ensure the blurred feet disappear.
        let thresholdFilter = CIFilter.colorThreshold()
        thresholdFilter.inputImage = laplacianOutput
        thresholdFilter.threshold = 0.7

        guard let thresholdedEdges = thresholdFilter.outputImage else { return nil }

        // 5. Colorize as red overlay.
        let redMatrix = CIFilter.colorMatrix()
        redMatrix.inputImage = thresholdedEdges
        redMatrix.rVector = CIVector(x: 1, y: 0, z: 0, w: 0)
        redMatrix.gVector = CIVector(x: 0, y: 0, z: 0, w: 0)
        redMatrix.bVector = CIVector(x: 0, y: 0, z: 0, w: 0)
        redMatrix.aVector = CIVector(x: 1, y: 0, z: 0, w: 0)

        guard let redMask = redMatrix.outputImage else { return nil }

        // 6. Render
        guard let outputCGImage = context.createCGImage(redMask, from: redMask.extent) else {
            return nil
        }

        return NSImage(cgImage: outputCGImage, size: originalSize)
    }

    func generateFocusMask(
        from cgImage: CGImage,
        scale: CGFloat
    ) async -> CGImage? {
        let context = self.context

        return await Task.detached(priority: .userInitiated) {
            let inputImage = CIImage(cgImage: cgImage)

            return await Self.processImage(
                inputImage,
                scale: scale,
                context: context
            )
        }.value
    }

    private static func processImage(
        _ inputImage: CIImage,
        scale: CGFloat,
        context: CIContext
    ) -> CGImage? {
        // 1. Scale down for performance
        let scaledImage = inputImage.transformed(
            by: CGAffineTransform(scaleX: scale, y: scale)
        )

        // 2. Pre-Blur (Crucial to ignore blurred high-contrast areas like feet)
        let preBlur = CIFilter.gaussianBlur()
        preBlur.inputImage = scaledImage
        preBlur.radius = 0.6 // Consistent with the NSImage version
        guard let smoothedImage = preBlur.outputImage else { return nil }

        // 3. Custom Laplacian Kernel (Sharpness Detection)
        // We replace SobelGradients with the custom Metal Kernel
        guard let laplacianKernel = Self.magnitudeKernel else { return nil }

        let laplacianImage = laplacianKernel.apply(
            extent: smoothedImage.extent,
            roiCallback: { _, rect in
                // Neighborhood sampling requires 1 pixel of context
                rect.insetBy(dx: -1, dy: -1)
            },
            arguments: [smoothedImage]
        )

        guard let laplacianOutput = laplacianImage else { return nil }

        // 4. Threshold
        // Lowered to 0.15 to let the eyes/fish scales through while the blur stays hidden
        let thresholdFilter = CIFilter.colorThreshold()
        thresholdFilter.inputImage = laplacianOutput
        thresholdFilter.threshold = 0.15

        guard let thresholdedEdges = thresholdFilter.outputImage else { return nil }

        // 5. Colorize as Red
        let redMatrix = CIFilter.colorMatrix()
        redMatrix.inputImage = thresholdedEdges
        redMatrix.rVector = CIVector(x: 1, y: 0, z: 0, w: 0)
        redMatrix.gVector = CIVector(x: 0, y: 0, z: 0, w: 0)
        redMatrix.bVector = CIVector(x: 0, y: 0, z: 0, w: 0)
        redMatrix.aVector = CIVector(x: 1, y: 0, z: 0, w: 0)

        guard let redMask = redMatrix.outputImage else { return nil }

        // 6. Render directly to CGImage
        // Using redMask.extent ensures we don't get artifacts from filter padding
        return context.createCGImage(redMask, from: redMask.extent)
    }
}
