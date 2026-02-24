//
//  FocusDetectorCGImageModel.swift
//  RawCull
//
//  Created by Thomas Evensen on 24/02/2026.
//

import AppKit
import CoreImage
import CoreImage.CIFilterBuiltins
import Observation
import OSLog

@Observable
final class FocusDetectorCGImageModel: @unchecked Sendable {
    /// CIContext is thread-safe for rendering; created once for performance.
    /// @unchecked Sendable is safe here since context is read-only after init.
    private let context = CIContext(options: [.workingColorSpace: NSNull()])

    private static let magnitudeKernel: CIColorKernel? = {
        guard
            let url = Bundle.main.url(forResource: "default", withExtension: "metallib"),
            let data = try? Data(contentsOf: url)
        else {
            assertionFailure("FocusDetectorModel: Could not find default.metallib in bundle.")
            return nil
        }

        do {
            let kernel = try CIColorKernel(functionName: "sobelMagnitude", fromMetalLibraryData: data)
            Logger.process.debugMessageOnly("✅ sobelMagnitude kernel loaded successfully")
            return kernel
        } catch {
            assertionFailure("FocusDetectorModel: Failed to load sobelMagnitude kernel: \(error)")
            return nil
        }
    }()

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
        let scaledImage = inputImage.transformed(
            by: CGAffineTransform(scaleX: scale, y: scale)
        )

        let sobelFilter = CIFilter.sobelGradients()
        sobelFilter.inputImage = scaledImage
        guard let sobelOutput = sobelFilter.outputImage else { return nil }

        guard
            let magnitudeKernel = Self.magnitudeKernel,
            let magnitudeImage = magnitudeKernel.apply(
                extent: sobelOutput.extent,
                arguments: [sobelOutput]
            )
        else { return nil }

        let thresholdFilter = CIFilter.colorThreshold()
        thresholdFilter.inputImage = magnitudeImage
        thresholdFilter.threshold = 0.15
        guard let thresholdedEdges = thresholdFilter.outputImage else { return nil }

        let redMatrix = CIFilter.colorMatrix()
        redMatrix.inputImage = thresholdedEdges
        redMatrix.rVector = CIVector(x: 1, y: 0, z: 0, w: 0)
        redMatrix.gVector = CIVector(x: 0, y: 0, z: 0, w: 0)
        redMatrix.bVector = CIVector(x: 0, y: 0, z: 0, w: 0)
        redMatrix.aVector = CIVector(x: 1, y: 0, z: 0, w: 0)
        guard let redMask = redMatrix.outputImage else { return nil }

        return context.createCGImage(redMask, from: redMask.extent)
    }
}
