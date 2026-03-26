import AppKit
import CoreImage
import CoreImage.CIFilterBuiltins
import Observation
import OSLog

struct FocusDetectorConfig: Equatable {
    var preBlurRadius: Float = 1.92
        var threshold: Float = 0.46
        var dilationRadius: Float = 0.43
        var energyMultiplier: Float = 7.62
        var erosionRadius: Float = 0.27
        var featherRadius: Float = 2.0
        var showRawLaplacian: Bool = false
}

@Observable
final class FocusMaskModel: @unchecked Sendable {
    var config = FocusDetectorConfig()

    // IMPROVEMENT 1: Force float32 working format so Laplacian
    // intermediate values are not clipped to 8-bit before thresholding.
    private let context = CIContext(options: [
        .workingColorSpace: NSNull(),
        .workingFormat: CIFormat.RGBAf
    ])

    private static let magnitudeKernel: CIKernel? = {
        guard let url = Bundle.main.url(forResource: "default", withExtension: "metallib"),
              let data = try? Data(contentsOf: url)
        else {
            return nil
        }
        do {
            return try CIKernel(functionName: "focusLaplacian", fromMetalLibraryData: data)
        } catch {
            print("FocusDetector: Failed to load kernel: \(error)")
            return nil
        }
    }()

    // IMPROVEMENT 4: ARW-aware entry point.
    // Loads the raw file via CIRAWFilter with NR, sharpening and boost
    // all disabled so the Laplacian fires on true optical sharpness.
    // Falls back to the CGImage path if CIRAWFilter is unavailable or
    // the URL does not point to a supported RAW format.
    func generateFocusMask(fromRawURL url: URL, scale: CGFloat) async -> CGImage? {
        let context = self.context
        let config = self.config

        return await Task.detached(priority: .userInitiated) { () -> CGImage? in
            guard let rawFilter = CIRAWFilter(imageURL: url) else {
                // Not a RAW file or unsupported — fall back to decoded path
                
                guard let cgImage = CGImage(
                    jpegDataProviderSource: CGDataProvider(url: url as CFURL)!,
                    decode: nil, shouldInterpolate: true, intent: .defaultIntent
                ) else { return nil }
                return await Self.buildFocusMask(from: CIImage(cgImage: cgImage),
                                           scale: scale, context: context, config: config)
            }
            // Disable all in-camera processing before focus analysis
            rawFilter.luminanceNoiseReductionAmount = 0   // luma NR
            rawFilter.colorNoiseReductionAmount = 0       // chroma NR
            rawFilter.contrastAmount = 0                  // contrast
            rawFilter.detailAmount = 0                    // detail / micro-contrast
            rawFilter.moireReductionAmount = 0            // moire
            rawFilter.boostAmount = 0                     // global tone curve
            rawFilter.boostShadowAmount = 0               // shadow lift
            rawFilter.sharpnessAmount = 0                 // critical: no USM
            rawFilter.localToneMapAmount = 0              // local tone mapping
            rawFilter.isGamutMappingEnabled = false       // no gamut clip
            rawFilter.isLensCorrectionEnabled = false       // no lens warp

            guard let linearImage = rawFilter.outputImage else { return nil }
            return await Self.buildFocusMask(from: linearImage,
                                       scale: scale, context: context, config: config)
        }.value
    }

    // Existing NSImage entry point — unchanged public API
    func generateFocusMask(from nsImage: NSImage, scale: CGFloat) async -> NSImage? {
        guard let cgImage = nsImage.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return nil }
        let originalSize = nsImage.size
        let context = self.context
        let config = self.config

        return await Task.detached(priority: .userInitiated) {
            guard let result = await Self.buildFocusMask(
                from: CIImage(cgImage: cgImage),
                scale: scale, context: context, config: config
            ) else { return nil }
            return NSImage(cgImage: result, size: originalSize)
        }.value
    }

    // Existing CGImage entry point — unchanged public API
    func generateFocusMask(from cgImage: CGImage, scale: CGFloat) async -> CGImage? {
        let context = self.context
        let config = self.config

        return await Task.detached(priority: .userInitiated) {
            return await Self.buildFocusMask(
                from: CIImage(cgImage: cgImage),
                scale: scale, context: context, config: config
            )
        }.value
    }

    // IMPROVEMENT 5: Single unified implementation — both public overloads
    // delegate here, eliminating the previous code duplication.
    private static func buildFocusMask(
        from inputImage: CIImage,
        scale: CGFloat,
        context: CIContext,
        config: FocusDetectorConfig
    ) -> CGImage? {
        let scaledImage = inputImage.transformed(
            by: CGAffineTransform(scaleX: scale, y: scale)
        )

        // Pass 1: Gaussian pre-blur (noise suppression)
        let preBlur = CIFilter.gaussianBlur()
        preBlur.inputImage = scaledImage
        preBlur.radius = config.preBlurRadius
        guard let smoothedImage = preBlur.outputImage else { return nil }

        // Pass 2: Laplacian (custom Metal kernel)
        guard let laplacianKernel = Self.magnitudeKernel else { return nil }
        guard let laplacianOutput = laplacianKernel.apply(
            extent: smoothedImage.extent.insetBy(dx: 1, dy: 1),
            roiCallback: { _, rect in rect.insetBy(dx: -2, dy: -2) },
            arguments: [smoothedImage]
        ) else { return nil }

        // IMPROVEMENT 3: Amplify BEFORE threshold so the threshold operates
        // on a boosted signal. The energyMultiplier now affects mask quality,
        // not just overlay brightness.
        let preThresholdBoost = CIFilter.colorMatrix()
        preThresholdBoost.inputImage = laplacianOutput
        preThresholdBoost.rVector = CIVector(x: CGFloat(config.energyMultiplier), y: 0, z: 0, w: 0)
        preThresholdBoost.gVector = CIVector(x: 0, y: CGFloat(config.energyMultiplier), z: 0, w: 0)
        preThresholdBoost.bVector = CIVector(x: 0, y: 0, z: CGFloat(config.energyMultiplier), w: 0)
        preThresholdBoost.aVector = CIVector(x: 0, y: 0, z: 0, w: 1)
        guard let boostedLaplacian = preThresholdBoost.outputImage else { return nil }

        // Debug shortcut: skip threshold/morphology and return the raw
        // Laplacian response directly so preBlurRadius and energyMultiplier
        // can be calibrated visually before touching the other controls.
        if config.showRawLaplacian {
            let cropped = boostedLaplacian.cropped(to: scaledImage.extent)
            return context.createCGImage(cropped, from: cropped.extent)
        }

        // Pass 3: Threshold on the boosted signal
        let thresholdFilter = CIFilter.colorThreshold()
        thresholdFilter.inputImage = boostedLaplacian
        thresholdFilter.threshold = config.threshold
        guard let thresholdedEdges = thresholdFilter.outputImage else { return nil }

        // Pass 4a: Optional erosion — removes isolated noise pixels that
        // survive thresholding before the dilation widens them.
        let eroded: CIImage
        if config.erosionRadius > 0,
           let erode = CIFilter(name: "CIMorphologyMinimum") {
            erode.setValue(thresholdedEdges, forKey: kCIInputImageKey)
            erode.setValue(CGFloat(config.erosionRadius), forKey: kCIInputRadiusKey)
            eroded = erode.outputImage ?? thresholdedEdges
        } else {
            eroded = thresholdedEdges
        }

        // Pass 4b: Dilation — fills small gaps and connects nearby blobs.
        let dilated: CIImage
        if config.dilationRadius > 0,
           let dilate = CIFilter(name: "CIMorphologyMaximum") {
            dilate.setValue(eroded, forKey: kCIInputImageKey)
            dilate.setValue(CGFloat(config.dilationRadius), forKey: kCIInputRadiusKey)
            dilated = dilate.outputImage ?? eroded
        } else {
            dilated = eroded
        }

        // Pass 5: Map to red channel for visual overlay
        let redMatrix = CIFilter.colorMatrix()
        redMatrix.inputImage = dilated
        redMatrix.rVector = CIVector(x: 1, y: 0, z: 0, w: 0)
        redMatrix.gVector = CIVector(x: 0, y: 0, z: 0, w: 0)
        redMatrix.bVector = CIVector(x: 0, y: 0, z: 0, w: 0)
        redMatrix.aVector = CIVector(x: 1, y: 0, z: 0, w: 0)
        guard let redMask = redMatrix.outputImage else { return nil }

        // Pass 6: Optional feather — final Gaussian for soft mask edges.
        let feathered: CIImage
        if config.featherRadius > 0 {
            let featherBlur = CIFilter.gaussianBlur()
            featherBlur.inputImage = redMask
            featherBlur.radius = config.featherRadius
            feathered = featherBlur.outputImage ?? redMask
        } else {
            feathered = redMask
        }

        let croppedMask = feathered.cropped(to: scaledImage.extent)
        return context.createCGImage(croppedMask, from: croppedMask.extent)
    }
}
