import AppKit
import CoreImage
import CoreImage.CIFilterBuiltins
import Observation
import OSLog

struct FocusDetectorConfig: Equatable {
    var preBlurRadius: Float = 1.5 // was 1.0 — reduces water noise immediately
    var threshold: Float = 0.30 // was 0.18 — cleaner first impression
    var dilationRadius: Float = 1.5 // unchanged
    var energyMultiplier: Float = 8.0
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

    func generateFocusMask(from nsImage: NSImage, scale: CGFloat) async -> NSImage? {
        guard let cgImage = nsImage.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return nil }
        let originalSize = nsImage.size
        let context = self.context
        let config = self.config // <-- capture before detached task

        return await Task.detached(priority: .userInitiated) {
            let inputImage = CIImage(cgImage: cgImage)
            return await Self.processImage(
                inputImage,
                originalSize: originalSize,
                scale: scale,
                context: context,
                config: config // <-- pass it in
            )
        }.value
    }

    static func processImage(
        _ inputImage: CIImage,
        originalSize: NSSize,
        scale: CGFloat,
        context: CIContext,
        config: FocusDetectorConfig // <-- add this
    ) -> NSImage? {
        let scaledImage = inputImage.transformed(by: CGAffineTransform(scaleX: scale, y: scale))

        let preBlur = CIFilter.gaussianBlur()
        preBlur.inputImage = scaledImage
        preBlur.radius = config.preBlurRadius // <-- use config
        guard let smoothedImage = preBlur.outputImage else { return nil }

        guard let laplacianKernel = Self.magnitudeKernel else { return nil }
        let laplacianImage = laplacianKernel.apply(
            extent: smoothedImage.extent.insetBy(dx: 1, dy: 1),
            roiCallback: { _, rect in rect.insetBy(dx: -2, dy: -2) },
            arguments: [smoothedImage]
        )
        guard let laplacianOutput = laplacianImage else { return nil }

        let thresholdFilter = CIFilter.colorThreshold()
        thresholdFilter.inputImage = laplacianOutput
        thresholdFilter.threshold = config.threshold // <-- use config
        guard let thresholdedEdges = thresholdFilter.outputImage else { return nil }

        let dilated: CIImage
        if let dilate = CIFilter(name: "CIMorphologyMaximum") {
            dilate.setValue(thresholdedEdges, forKey: kCIInputImageKey)
            dilate.setValue(CGFloat(config.dilationRadius), forKey: kCIInputRadiusKey) // <-- use config
            dilated = dilate.outputImage ?? thresholdedEdges
        } else {
            dilated = thresholdedEdges
        }

        let redMatrix = CIFilter.colorMatrix()
        redMatrix.inputImage = dilated
        redMatrix.rVector = CIVector(x: CGFloat(config.energyMultiplier), y: 0, z: 0, w: 0) // <-- use config
        redMatrix.gVector = CIVector(x: 0, y: 0, z: 0, w: 0)
        redMatrix.bVector = CIVector(x: 0, y: 0, z: 0, w: 0)
        redMatrix.aVector = CIVector(x: 1, y: 0, z: 0, w: 0)
        guard let redMask = redMatrix.outputImage else { return nil }

        let croppedMask = redMask.cropped(to: scaledImage.extent)
        guard let outputCGImage = context.createCGImage(croppedMask, from: croppedMask.extent) else {
            return nil
        }
        return NSImage(cgImage: outputCGImage, size: originalSize)
    }

    func generateFocusMask(
        from cgImage: CGImage,
        scale: CGFloat
    ) async -> CGImage? {
        let context = self.context
        let config = self.config // <-- capture before detached task

        return await Task.detached(priority: .userInitiated) {
            let inputImage = CIImage(cgImage: cgImage)
            return await Self.processImage(
                inputImage,
                scale: scale,
                context: context,
                config: config // <-- pass captured value
            )
        }.value
    }

    /// CGImage version (used for overlay rendering)
    private static func processImage(
        _ inputImage: CIImage,
        scale: CGFloat,
        context: CIContext,
        config: FocusDetectorConfig // <-- remove the underscore
    ) -> CGImage? {
        let scaledImage = inputImage.transformed(
            by: CGAffineTransform(scaleX: scale, y: scale)
        )

        let preBlur = CIFilter.gaussianBlur()
        preBlur.inputImage = scaledImage
        preBlur.radius = config.preBlurRadius // <-- use config

        guard let smoothedImage = preBlur.outputImage else { return nil }
        guard let laplacianKernel = Self.magnitudeKernel else { return nil }

        let laplacianImage = laplacianKernel.apply(
            extent: smoothedImage.extent.insetBy(dx: 1, dy: 1),
            roiCallback: { _, rect in rect.insetBy(dx: -2, dy: -2) },
            arguments: [smoothedImage]
        )
        guard let laplacianOutput = laplacianImage else { return nil }

        let thresholdFilter = CIFilter.colorThreshold()
        thresholdFilter.inputImage = laplacianOutput
        thresholdFilter.threshold = config.threshold // <-- use config

        guard let thresholdedEdges = thresholdFilter.outputImage else { return nil }

        let dilate = CIFilter(name: "CIMorphologyMaximum")
        dilate?.setValue(thresholdedEdges, forKey: kCIInputImageKey)
        dilate?.setValue(CGFloat(config.dilationRadius), forKey: kCIInputRadiusKey) // needs CGFloat
        let dilated = dilate?.outputImage ?? thresholdedEdges

        let redMatrix = CIFilter.colorMatrix()
        redMatrix.inputImage = dilated
        redMatrix.rVector = CIVector(x: CGFloat(config.energyMultiplier), y: 0, z: 0, w: 0)
        redMatrix.gVector = CIVector(x: 0, y: 0, z: 0, w: 0)
        redMatrix.bVector = CIVector(x: 0, y: 0, z: 0, w: 0)
        redMatrix.aVector = CIVector(x: 1, y: 0, z: 0, w: 0)
        guard let redMask = redMatrix.outputImage else { return nil }

        let croppedMask = redMask.cropped(to: scaledImage.extent)
        guard let outputCGImage = context.createCGImage(croppedMask, from: croppedMask.extent) else {
            return nil
        }
        return outputCGImage
    }
}
