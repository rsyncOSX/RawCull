import AppKit
import CoreImage
import CoreImage.CIFilterBuiltins
import Observation

@Observable
final class FocusDetectorModel: @unchecked Sendable {
    // CIContext is thread-safe for rendering; created once for performance.
    // @unchecked Sendable is safe here since context is read-only after init.
    private let context = CIContext(options: [.workingColorSpace: NSNull()])
    
    private static let magnitudeKernel: CIColorKernel? = {
        guard
            let url = Bundle.main.url(forResource: "default", withExtension: "metallib"),
            let data = try? Data(contentsOf: url)
        else {
            assertionFailure("FocusDetectorModel: Could not find default.metallib in bundle.")
            return nil
        }
        
        // Temporary: try loading ALL kernel names to see what's available
        let kernelNames = CIKernel.kernelNames(fromMetalLibraryData: data)
        print("✅ Available kernels in metallib: \(kernelNames)")
        
        do {
            let kernel = try CIColorKernel(functionName: "sobelMagnitude", fromMetalLibraryData: data)
            print("✅ sobelMagnitude kernel loaded successfully")
            return kernel
        } catch {
            assertionFailure("FocusDetectorModel: Failed to load sobelMagnitude kernel: \(error)")
            return nil
        }
    }()

/*
    // Loaded once at class level; Metal kernel compilation is expensive.
    private static let magnitudeKernel: CIColorKernel? = {
        guard
            let url = Bundle.main.url(forResource: "Kernels", withExtension: "ci.metallib"),
            let data = try? Data(contentsOf: url)
        else {
            assertionFailure("FocusDetectorModel: Could not find Kernels.ci.metallib in bundle.")
            return nil
        }
        do {
            return try CIColorKernel(functionName: "sobelMagnitude", fromMetalLibraryData: data)
        } catch {
            assertionFailure("FocusDetectorModel: Failed to load sobelMagnitude kernel: \(error)")
            return nil
        }
    }()
*/
    func generateFocusMask(
        from nsImage: NSImage,
        scale: CGFloat
    ) async -> NSImage? {
        // Temporary debug — remove once verified
            print("Bundle contents:")
            Bundle.main.urls(forResourcesWithExtension: nil, subdirectory: nil)?.forEach {
                print($0.lastPathComponent)
            }
        
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

    // Static to make it explicit that this function is pure/stateless.
    private static func processImage(
        _ inputImage: CIImage,
        originalSize: NSSize,
        scale: CGFloat,
        context: CIContext
    ) -> NSImage? {
        // 1. Scale down for performance
        let scaledImage = inputImage.transformed(
            by: CGAffineTransform(scaleX: scale, y: scale)
        )

        // 2. Sobel Gradients — outputs Gx in red channel, Gy in green channel
        let sobelFilter = CIFilter.sobelGradients()
        sobelFilter.inputImage = scaledImage
        guard let sobelOutput = sobelFilter.outputImage else { return nil }

        // 3. Compute true Euclidean gradient magnitude sqrt(Gx² + Gy²) via Metal kernel.
        //    This gives a linear, consistently tunable edge strength value.
        guard
            let magnitudeKernel = Self.magnitudeKernel,
            let magnitudeImage = magnitudeKernel.apply(
                extent: sobelOutput.extent,
                arguments: [sobelOutput]
            )
        else { return nil }

        // 4. Threshold — lower value = more sensitive (shows more edges as "in focus")
        let thresholdFilter = CIFilter.colorThreshold()
        thresholdFilter.inputImage = magnitudeImage
        thresholdFilter.threshold = 0.15

        guard let thresholdedEdges = thresholdFilter.outputImage else { return nil }

        // 5. Colorize as red overlay.
        //    aVector x:1 maps input red (our magnitude) to output alpha,
        //    so edges fade out where intensity is low.
        let redMatrix = CIFilter.colorMatrix()
        redMatrix.inputImage = thresholdedEdges
        redMatrix.rVector = CIVector(x: 1, y: 0, z: 0, w: 0)
        redMatrix.gVector = CIVector(x: 0, y: 0, z: 0, w: 0)
        redMatrix.bVector = CIVector(x: 0, y: 0, z: 0, w: 0)
        // Alpha = input red channel (magnitude), making edges semi-transparent where soft
        redMatrix.aVector = CIVector(x: 1, y: 0, z: 0, w: 0)

        guard let redMask = redMatrix.outputImage else { return nil }

        // 6. Render. The mask extent may have a non-zero origin due to filter padding;
        //    using redMask.extent handles this correctly.
        //    NSImage will scale this back up to originalSize when drawn.
        guard let outputCGImage = context.createCGImage(redMask, from: redMask.extent) else {
            return nil
        }

        return NSImage(cgImage: outputCGImage, size: originalSize)
    }
}

/*
 
 */
