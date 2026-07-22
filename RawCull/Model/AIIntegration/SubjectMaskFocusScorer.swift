import CoreGraphics
import Foundation
import OSLog
import PhotoAnalysisKit

nonisolated struct SubjectMaskFocusEvidence: Equatable, Sendable {
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
    func score(
        image: CGImage,
        subjectMask: CGImage,
        normalizedAFPoint: CGPoint?,
    ) async throws -> SubjectMaskFocusEvidence?
}

/// RawCull-owned subject-detail scorer. PhotoAIKit acquires and evaluates the
/// mask; this type measures focus evidence inside that mask without choosing a
/// winner or mutating culling state.
nonisolated struct SubjectMaskFocusScorer: SubjectMaskFocusScoring, Sendable {
    private static let patchColumns = 6
    private static let patchRows = 6

    @concurrent
    func score(
        image: CGImage,
        subjectMask: CGImage,
        normalizedAFPoint: CGPoint?,
    ) async throws -> SubjectMaskFocusEvidence? {
        Logger.process.debugMessageOnly(
            "SubjectMaskFocusScorer.score(): starting subject-detail scoring at \(image.width)x\(image.height)",
        )
        try Task.checkCancellation()
        let width = image.width
        let height = image.height
        guard width > 0, height > 0 else { return nil }

        let pixelCount = width * height
        guard let imagePixels = Self.rgbaPixels(image, width: width, height: height) else {
            return nil
        }
        var luminance = [Float](repeating: 0, count: pixelCount)
        for index in 0 ..< pixelCount {
            if index & 0x3FFFF == 0 { try Task.checkCancellation() }
            let offset = index * 4
            luminance[index] = (
                Float(imagePixels[offset]) * 0.2126
                    + Float(imagePixels[offset + 1]) * 0.7152
                    + Float(imagePixels[offset + 2]) * 0.0722
            ) / 255
        }
        try Task.checkCancellation()

        guard let maskAlpha = Self.maskAlpha(
            subjectMask,
            width: width,
            height: height,
        ) else { return nil }

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
            if y & 0x3F == 0 { try Task.checkCancellation() }
            for x in border ..< max(border, width - border) {
                let index = y * width + x
                let edgeEnergy = abs(
                    luminance[index] * 4
                        - luminance[index - 1]
                        - luminance[index + 1]
                        - luminance[index - width]
                        - luminance[index + width]
                )
                guard edgeEnergy.isFinite else { continue }
                globalSamples.append(edgeEnergy)
                guard maskAlpha[index] > 16 else { continue }

                maskedCount += 1
                subjectSamples.append(edgeEnergy)
                let column = min(Self.patchColumns - 1, x * Self.patchColumns / width)
                let row = min(Self.patchRows - 1, y * Self.patchRows / height)
                let patchIndex = row * Self.patchColumns + column
                patchSamples[patchIndex].append(edgeEnergy)
                patchMaskCounts[patchIndex] += 1
            }
        }

        guard !subjectSamples.isEmpty else { return nil }
        let coverage = Float(maskedCount) / Float(pixelCount)
        let broad = SharpnessMetrics.robustTailScore(subjectSamples)
        let fine = SharpnessMetrics.microContrast(subjectSamples)
        let patchArea = max(1, pixelCount / patchSamples.count)
        let minimumPatchSamples = max(64, Int(Float(patchArea) * 0.08))
        let local = patchSamples.enumerated().compactMap { index, samples -> Float? in
            guard patchMaskCounts[index] >= minimumPatchSamples else { return nil }
            guard let robust = SharpnessMetrics.robustTailScore(samples) else { return nil }
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
            finalScore: finalScore,
            broadSubjectScore: broad,
            localDetailScore: local,
            fineDetailScore: fine,
            maskCoverage: coverage,
            autofocusInsideMask: normalizedAFPoint.map {
                Self.containsAFPoint($0, maskAlpha: maskAlpha, width: width, height: height)
            },
            usableLocalPatch: local != nil,
            backgroundDominancePenaltyApplied: backgroundDominance,
        )
        Logger.process.debugMessageOnly(
            "SubjectMaskFocusScorer.score(): finished with score \(evidence.finalScore)",
        )
        return evidence
    }

    private nonisolated static func maskAlpha(
        _ mask: CGImage,
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
        context.interpolationQuality = .high
        context.draw(mask, in: CGRect(x: 0, y: 0, width: width, height: height))
        return stride(from: 3, to: pixels.count, by: 4).map { pixels[$0] }
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
