import AppKit
import CoreImage
import CoreImage.CIFilterBuiltins
import Observation
import OSLog

struct FocusDetectorConfig: Equatable {
    var preBlurRadius: Float = 1.0
    var threshold: Float = 0.18
    var dilationRadius: Float = 1.5
    var energyMultiplier: Float = 12.0
}

@Observable
final class FocusDetectorMaskModel: @unchecked Sendable {
    var config = FocusDetectorConfig()

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

        // 2. Pre-Blur — increased to suppress water/texture noise before kernel
        let preBlur = CIFilter.gaussianBlur()
        preBlur.inputImage = scaledImage
        preBlur.radius = 1.8
        guard let smoothedImage = preBlur.outputImage else { return nil }

        // 3. Apply custom LoG Kernel
        guard let laplacianKernel = Self.magnitudeKernel else { return nil }

        let laplacianImage = laplacianKernel.apply(
            extent: smoothedImage.extent,
            roiCallback: { _, rect in
                rect.insetBy(dx: -2, dy: -2) // wider neighbourhood for 3x3 kernel
            },
            arguments: [smoothedImage]
        )
        guard let laplacianOutput = laplacianImage else { return nil }

        // 4. Threshold — raised to filter out soft-textured out-of-focus regions
        let thresholdFilter = CIFilter.colorThreshold()
        thresholdFilter.inputImage = laplacianOutput
        thresholdFilter.threshold = 0.35

        guard let thresholdedEdges = thresholdFilter.outputImage else { return nil }

        // 5. Dilation — fills sparse dots on subject into solid regions
        let dilated: CIImage
        if let dilate = CIFilter(name: "CIMorphologyMaximum") {
            dilate.setValue(thresholdedEdges, forKey: kCIInputImageKey)
            dilate.setValue(2.0, forKey: kCIInputRadiusKey)
            dilated = dilate.outputImage ?? thresholdedEdges
        } else {
            dilated = thresholdedEdges
        }

        // 6. Colorize as red overlay
        let redMatrix = CIFilter.colorMatrix()
        redMatrix.inputImage = dilated
        redMatrix.rVector = CIVector(x: 1, y: 0, z: 0, w: 0)
        redMatrix.gVector = CIVector(x: 0, y: 0, z: 0, w: 0)
        redMatrix.bVector = CIVector(x: 0, y: 0, z: 0, w: 0)
        redMatrix.aVector = CIVector(x: 1, y: 0, z: 0, w: 0)
        guard let redMask = redMatrix.outputImage else { return nil }

        // 7. Render
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
                context: context,
                config: self.config // capture config value before entering task
            )
        }.value
    }

    /// CGImage version (used for overlay rendering)
    private static func processImage(
        _ inputImage: CIImage,
        scale: CGFloat,
        context: CIContext,
        config _: FocusDetectorConfig
    ) -> CGImage? {
        let scaledImage = inputImage.transformed(
            by: CGAffineTransform(scaleX: scale, y: scale)
        )

        // Increase pre-blur — this is your #1 lever against water texture noise
        // A radius of 1.5–2.0 kills soft ripple texture before the kernel sees it
        let preBlur = CIFilter.gaussianBlur()
        preBlur.inputImage = scaledImage
        preBlur.radius = 1.8
        guard let smoothedImage = preBlur.outputImage else { return nil }

        guard let laplacianKernel = Self.magnitudeKernel else { return nil }

        let laplacianImage = laplacianKernel.apply(
            extent: smoothedImage.extent,
            roiCallback: { _, rect in rect.insetBy(dx: -2, dy: -2) }, // wider for 3x3
            arguments: [smoothedImage]
        )
        guard let laplacianOutput = laplacianImage else { return nil }

        // Raise threshold significantly — water ripples shouldn't survive this
        let thresholdFilter = CIFilter.colorThreshold()
        thresholdFilter.inputImage = laplacianOutput
        thresholdFilter.threshold = 0.35 // was 0.15 — raise until water disappears

        guard let thresholdedEdges = thresholdFilter.outputImage else { return nil }

        // Optional: morphological dilation to fill in gaps on the subject
        // This helps the bird's body show as a solid region, not scattered dots
        let dilate = CIFilter(name: "CIMorphologyMaximum")
        dilate?.setValue(thresholdedEdges, forKey: kCIInputImageKey)
        dilate?.setValue(2.0, forKey: kCIInputRadiusKey)
        let dilated = dilate?.outputImage ?? thresholdedEdges

        let redMatrix = CIFilter.colorMatrix()
        redMatrix.inputImage = dilated
        redMatrix.rVector = CIVector(x: 1, y: 0, z: 0, w: 0)
        redMatrix.gVector = CIVector(x: 0, y: 0, z: 0, w: 0)
        redMatrix.bVector = CIVector(x: 0, y: 0, z: 0, w: 0)
        redMatrix.aVector = CIVector(x: 1, y: 0, z: 0, w: 0)
        guard let redMask = redMatrix.outputImage else { return nil }

        return context.createCGImage(redMask, from: redMask.extent)
    }
}
