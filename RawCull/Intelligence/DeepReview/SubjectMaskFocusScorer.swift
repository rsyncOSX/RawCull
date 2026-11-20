import CoreGraphics
import Foundation
import OSLog
import PhotoAnalysisKit

nonisolated struct SubjectMaskFocusEvidence: Equatable, Sendable {
    var scorerVersion: String?
    var foregroundCount: Int?
    var totalPixelCount: Int?
    var usableForegroundCount: Int?
    var interiorPixelCount: Int?
    var borderPixels: Int?
    var foregroundBounds: CGRect?
    var suspectNearFullOccupancy: Bool?
    let finalScore: Float
    let broadSubjectScore: Float?
    let localDetailScore: Float?
    let fineDetailScore: Float
    let maskCoverage: Float
    let autofocusInsideMask: Bool?
    let usableLocalPatch: Bool
    let backgroundDominancePenaltyApplied: Bool
}

nonisolated protocol SubjectMaskFocusScoring: Sendable {
    /// - Parameter iso: Capture ISO, used to scale noise suppression. Nil is treated
    ///   as a clean base ISO.
    func score(
        image: CGImage,
        subjectMask: CGImage,
        normalizedAFPoint: CGPoint?,
        iso: Int?,
    ) async throws -> SubjectMaskFocusEvidence?
}

extension SubjectMaskFocusScoring {
    func score(
        image: CGImage,
        subjectMask: CGImage,
        normalizedAFPoint: CGPoint?,
    ) async throws -> SubjectMaskFocusEvidence? {
        try await score(image: image, subjectMask: subjectMask, normalizedAFPoint: normalizedAFPoint, iso: nil)
    }
}

/// RawCull-owned subject-detail scorer. PhotoAIKit acquires and evaluates the
/// mask; this type measures focus evidence inside that mask without choosing a
/// winner or mutating culling state.
nonisolated struct SubjectMaskFocusScorer: SubjectMaskFocusScoring, Sendable {
    /// v3: edge energy is measured at a normalized working resolution, reduced
    /// further at high ISO, so noise and decode size no longer inflate the score.
    static let semanticsVersion = "subject-detail-v3"
    private static let patchColumns = 6
    private static let patchRows = 6
    /// Long side the 3×3 edge filter runs at for a clean, base-ISO frame. Larger
    /// renders are area-averaged down to it so embedded previews (≈1616 px) and RAW
    /// renders (2048 px) measure detail at the same scale.
    static let workingLongSide = 1024

    /// Working size for an image: area-average down to `workingLongSide`, divided by
    /// the engine's ISO noise factor so high-ISO frames are averaged harder, the same
    /// role the ISO pre-blur plays in the main sharpness engine. Never upsamples.
    static func workingSize(width: Int, height: Int, iso: Int?) -> (width: Int, height: Int) {
        let longSide = max(width, height)
        let isoFactor = SharpnessMetrics.isoScalingFactor(iso: iso ?? 100)
        let target = max(64, Int((Float(workingLongSide) / isoFactor).rounded()))
        guard longSide > target else { return (width, height) }
        let scale = Double(target) / Double(longSide)
        return (max(1, Int((Double(width) * scale).rounded())), max(1, Int((Double(height) * scale).rounded())))
    }

    /// Box (area) average of a single-channel plane into a smaller plane.
    static func areaAverage(_ plane: [Float], width: Int, height: Int, to outWidth: Int, _ outHeight: Int) -> [Float] {
        guard outWidth != width || outHeight != height else { return plane }
        var output = [Float](repeating: 0, count: outWidth * outHeight)
        for oy in 0 ..< outHeight {
            let y0 = oy * height / outHeight
            let y1 = max(y0 + 1, (oy + 1) * height / outHeight)
            for ox in 0 ..< outWidth {
                let x0 = ox * width / outWidth
                let x1 = max(x0 + 1, (ox + 1) * width / outWidth)
                var sum: Float = 0
                for y in y0 ..< y1 {
                    let row = y * width
                    for x in x0 ..< x1 {
                        sum += plane[row + x]
                    }
                }
                output[oy * outWidth + ox] = sum / Float((y1 - y0) * (x1 - x0))
            }
        }
        return output
    }

    @concurrent
    func score(
        image: CGImage,
        subjectMask: CGImage,
        normalizedAFPoint: CGPoint?,
        iso: Int?,
    ) async throws -> SubjectMaskFocusEvidence? {
        Logger.process.debugMessageOnly(
            "SubjectMaskFocusScorer.score(): starting subject-detail scoring at \(image.width)x\(image.height)",
        )
        try Task.checkCancellation()
        let sourceWidth = image.width
        let sourceHeight = image.height
        guard sourceWidth > 0, sourceHeight > 0 else { return nil }

        let sourcePixelCount = sourceWidth * sourceHeight
        guard let imagePixels = Self.rgbaPixels(image, width: sourceWidth, height: sourceHeight) else {
            return nil
        }
        var sourceLuminance = [Float](repeating: 0, count: sourcePixelCount)
        for index in 0 ..< sourcePixelCount {
            if index & 0x3FFFF == 0 {
                try Task.checkCancellation()
            }
            let offset = index * 4
            sourceLuminance[index] = (
                Float(imagePixels[offset]) * 0.2126
                    + Float(imagePixels[offset + 1]) * 0.7152
                    + Float(imagePixels[offset + 2]) * 0.0722,
            ) / 255
        }
        try Task.checkCancellation()

        let foreground = try SubjectMaskForeground.decode(subjectMask, width: sourceWidth, height: sourceHeight)
        guard foreground.foregroundCount > 0 else { throw SubjectMaskDecodingError.emptyForeground }
        let maskAlpha = foreground.pixels

        // Measure at the working resolution; AF containment and foreground stats keep
        // the full-resolution mask.
        let working = Self.workingSize(width: sourceWidth, height: sourceHeight, iso: iso)
        let width = working.width
        let height = working.height
        let pixelCount = width * height
        let luminance = Self.areaAverage(sourceLuminance, width: sourceWidth, height: sourceHeight, to: width, height)
        let workingMask = Self.areaAverage(
            maskAlpha.map(Float.init), width: sourceWidth, height: sourceHeight, to: width, height,
        )
        try Task.checkCancellation()

        var subjectSamples: [Float] = []
        subjectSamples.reserveCapacity(pixelCount / 3)
        var globalSamples: [Float] = []
        globalSamples.reserveCapacity(pixelCount)
        var patchSamples = Array(
            repeating: [Float](),
            count: Self.patchColumns * Self.patchRows,
        )
        var patchMaskCounts = [Int](
            repeating: 0,
            count: Self.patchColumns * Self.patchRows,
        )

        let border = max(2, min(width, height) / 250)
        var maskedCount = 0
        for y in border ..< max(border, height - border) {
            if y & 0x3F == 0 {
                try Task.checkCancellation()
            }
            for x in border ..< max(border, width - border) {
                let index = y * width + x
                let edgeEnergy = abs(
                    luminance[index] * 4
                        - luminance[index - 1]
                        - luminance[index + 1]
                        - luminance[index - width]
                        - luminance[index + width],
                )
                guard edgeEnergy.isFinite else { continue }
                globalSamples.append(edgeEnergy)
                guard workingMask[index] > 16 else { continue }

                maskedCount += 1
                subjectSamples.append(edgeEnergy)
                let column = min(Self.patchColumns - 1, x * Self.patchColumns / width)
                let row = min(Self.patchRows - 1, y * Self.patchRows / height)
                let patchIndex = row * Self.patchColumns + column
                patchSamples[patchIndex].append(edgeEnergy)
                patchMaskCounts[patchIndex] += 1
            }
        }

        guard subjectSamples.count >= 64 else { throw SubjectMaskDecodingError.insufficientUsablePixels }
        let coverage = Float(maskedCount) / Float(pixelCount)
        let broad = SharpnessMetrics.robustTailScore(subjectSamples)
        let fine = SharpnessMetrics.microContrast(subjectSamples)
        let patchArea = max(1, pixelCount / patchSamples.count)
        let minimumPatchSamples = max(64, Int(Float(patchArea) * 0.08))
        let local = patchSamples.enumerated().compactMap { index, samples -> Float? in
            guard patchMaskCounts[index] >= minimumPatchSamples, let robust = SharpnessMetrics.robustTailScore(samples) else { return nil }
            return robust + SharpnessMetrics.microContrast(samples) * 0.35
        }.max()

        guard broad != nil || local != nil else { return nil }
        var finalScore = (broad ?? 0) * 0.40
            + (local ?? broad ?? 0) * 0.40
            + fine * 0.20
        let global = SharpnessMetrics.robustTailScore(globalSamples) ?? 0
        let backgroundDominance = global > max(finalScore * 1.45, finalScore + 0.04)
        if backgroundDominance {
            finalScore *= 0.82
        }

        let evidence = SubjectMaskFocusEvidence(
            scorerVersion: Self.semanticsVersion,
            foregroundCount: foreground.foregroundCount,
            totalPixelCount: sourcePixelCount,
            usableForegroundCount: maskedCount,
            interiorPixelCount: globalSamples.count,
            borderPixels: border,
            foregroundBounds: foreground.bounds,
            suspectNearFullOccupancy: foreground.suspectNearFullOccupancy,
            finalScore: finalScore,
            broadSubjectScore: broad,
            localDetailScore: local,
            fineDetailScore: fine,
            maskCoverage: coverage,
            autofocusInsideMask: normalizedAFPoint.map {
                Self.containsAFPoint($0, maskAlpha: maskAlpha, width: sourceWidth, height: sourceHeight)
            },
            usableLocalPatch: local != nil,
            backgroundDominancePenaltyApplied: backgroundDominance,
        )
        Logger.process.debugMessageOnly(
            "SubjectMaskFocusScorer.score(): finished with score \(evidence.finalScore)",
        )
        return evidence
    }

    private nonisolated static func rgbaPixels(
        _ image: CGImage,
        width: Int,
        height: Int,
    ) -> [UInt8]? {
        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        guard let context = CGContext(
            data: &pixels,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue,
        ) else { return nil }
        context.interpolationQuality = .none
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        return pixels
    }

    private nonisolated static func containsAFPoint(
        _ point: CGPoint,
        maskAlpha: [UInt8],
        width: Int,
        height: Int,
    ) -> Bool {
        guard point.x.isFinite, point.y.isFinite else { return false }
        let x = min(width - 1, max(0, Int(point.x * CGFloat(width))))
        let y = min(height - 1, max(0, Int(point.y * CGFloat(height))))
        return maskAlpha[y * width + x] > 16
    }
}
