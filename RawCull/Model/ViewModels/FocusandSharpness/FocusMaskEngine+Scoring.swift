import Accelerate
import AppKit
import CoreImage
import CoreImage.CIFilterBuiltins
import ImageIO
import OSLog
import RawCullCore
import RawParserKit
import Vision

private nonisolated let _focusMagnitudeKernel: CIKernel? = {
    guard let url = Bundle.main.url(forResource: "default", withExtension: "metallib"),
          let data = try? Data(contentsOf: url)
    else { return nil }

    do {
        return try CIKernel(functionName: "focusLaplacian", fromMetalLibraryData: data)
    } catch {
        Logger.process.debugMessageOnly("FocusDetector: Failed to load kernel: \(error)")
        return nil
    }
}()

extension FocusMaskEngine {
    nonisolated func computeSharpnessScore(
        fromRawURL url: URL,
        config: FocusDetectorConfig,
        thumbnailMaxPixelSize: Int = 512,
        afPoint: CGPoint? = nil,
        scoringSource: SharpnessScoringSource = .embeddedPreview,
    ) async -> (score: Float?, saliency: SaliencyInfo?, breakdown: SharpnessBreakdown?) {
        await Self.runCancellableWorker { [context] in
            guard !Task.isCancelled else { return (nil, nil, nil) }
            guard let cgImage = Self.decodeScoringImage(
                at: url,
                maxPixelSize: thumbnailMaxPixelSize,
                scoringSource: scoringSource,
                context: context,
            ) else { return (nil, nil, nil) }

            guard !Task.isCancelled else { return (nil, nil, nil) }
            let saliency = Self.detectSaliencyAndClassify(
                for: cgImage, classify: config.enableSubjectClassification,
            )
            guard !Task.isCancelled else { return (nil, nil, nil) }
            var breakdown = Self.computeSharpnessBreakdown(
                from: CIImage(cgImage: cgImage),
                saliencyDetection: saliency,
                afPoint: afPoint,
                context: context,
                config: config,
            )
            breakdown?.scoringSource = scoringSource
            return (breakdown?.finalScore, saliency.saliencyInfo, breakdown)
        } ?? (nil, nil, nil)
    }

    // MARK: - Decode helpers

    nonisolated static func decodeScoringImage(
        at url: URL,
        maxPixelSize: Int,
        scoringSource: SharpnessScoringSource,
        context: CIContext,
    ) -> CGImage? {
        guard !Task.isCancelled else { return nil }
        let boundedMaxPixelSize = maxPixelSize > 0
            ? min(maxPixelSize, SharpnessScoringSizeOption.maximumPixelSize)
            : SharpnessScoringSizeOption.maximumPixelSize
        let decoded: CGImage? = switch scoringSource {
        case .embeddedPreview:
            extractSonyEmbeddedPreview(at: url, maxPixelSize: boundedMaxPixelSize)
                ?? decodeThumbnail(at: url, maxPixelSize: boundedMaxPixelSize)

        case .rawDemosaic:
            decodeDemosaicedRawThumbnail(at: url, maxPixelSize: boundedMaxPixelSize, context: context)
        }
        guard !Task.isCancelled else { return nil }
        return decoded.flatMap(normalizeToSRGB)
    }

    private nonisolated static func decodeThumbnail(at url: URL, maxPixelSize: Int) -> CGImage? {
        let srcOptions: [CFString: Any] = [kCGImageSourceShouldCache: false]
        guard let source = CGImageSourceCreateWithURL(url as CFURL, srcOptions as CFDictionary) else { return nil }

        var thumbOptions: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageIfAbsent: false,
            kCGImageSourceCreateThumbnailFromImageAlways: false,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true
        ]
        if maxPixelSize > 0 {
            thumbOptions[kCGImageSourceThumbnailMaxPixelSize] = maxPixelSize
        }
        return CGImageSourceCreateThumbnailAtIndex(source, 0, thumbOptions as CFDictionary)
    }

    private nonisolated static func decodeDemosaicedRawThumbnail(
        at url: URL,
        maxPixelSize: Int,
        context: CIContext,
    ) -> CGImage? {
        guard let rawFilter = CIRAWFilter(imageURL: url) else { return nil }

        rawFilter.sharpnessAmount = 0.0
        rawFilter.detailAmount = 0.6
        rawFilter.contrastAmount = 1.0
        rawFilter.exposure = 0.0

        guard var image = rawFilter.outputImage else { return nil }
        if maxPixelSize > 0 {
            let maxDimension = max(image.extent.width, image.extent.height)
            if maxDimension > CGFloat(maxPixelSize), maxDimension > 0 {
                let scale = CGFloat(maxPixelSize) / maxDimension
                image = image.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
            }
        }

        return context.createCGImage(image, from: image.extent)
    }

    /// Binary fallback for ARW 6.0 (RA16) files from newer Sony bodies
    /// (A7V, A7R VI / ILCE-7RM6) where CGImageSourceCreateThumbnailAtIndex
    /// returns nil. Reads the embedded JPEG directly from the file bytes via
    /// SonyMakerNoteParser, bypassing the RA16 decoder entirely. Sony-only:
    /// other vendors (e.g. Nikon NEF) don't need this path and would hit a
    /// TIFF structure the Sony parser doesn't understand.
    private nonisolated static func extractSonyEmbeddedPreview(at url: URL, maxPixelSize: Int) -> CGImage? {
        guard RawFormatRegistry.format(for: url) is SonyRawFormat.Type else { return nil }
        guard let locations = SonyMakerNoteParser.embeddedJPEGLocations(from: url),
              let loc = locations.preview ?? locations.thumbnail ?? locations.fullJPEG,
              let data = SonyMakerNoteParser.readEmbeddedJPEGData(at: loc, from: url),
              let src = CGImageSourceCreateWithData(data as CFData, nil)
        else { return nil }

        let raw: CGImage?
        if maxPixelSize > 0 {
            let options: [CFString: Any] = [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceThumbnailMaxPixelSize: maxPixelSize,
                kCGImageSourceShouldCacheImmediately: true
            ]
            raw = CGImageSourceCreateThumbnailAtIndex(src, 0, options as CFDictionary)
        } else {
            raw = CGImageSourceCreateImageAtIndex(
                src,
                0,
                [kCGImageSourceShouldCacheImmediately: true] as CFDictionary,
            )
        }

        return raw
    }

    /// Re-renders a CGImage through an 8-bit sRGB RGBA CGContext so that the Metal
    /// pipeline always receives a predictable pixel format, regardless of the
    /// source JPEG's color space or bit depth.
    nonisolated static func normalizeToSRGB(_ image: CGImage) -> CGImage? {
        guard let srgb = CGColorSpace(name: CGColorSpace.sRGB) else { return image }
        let bitmapInfo = CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue)
        guard let ctx = CGContext(
            data: nil,
            width: image.width, height: image.height,
            bitsPerComponent: 8, bytesPerRow: 0,
            space: srgb, bitmapInfo: bitmapInfo.rawValue,
        ) else { return image }
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        return ctx.makeImage() ?? image
    }

    // MARK: - Saliency

    nonisolated static func detectSaliencyAndClassify(for cgImage: CGImage, classify: Bool) -> SaliencyDetection {
        guard !Task.isCancelled else { return SaliencyDetection(candidates: [], saliencyInfo: nil) }
        let saliencyRequest = VNGenerateAttentionBasedSaliencyImageRequest()
        let classifyRequest = VNClassifyImageRequest()
        let requests: [VNRequest] = classify ? [saliencyRequest, classifyRequest] : [saliencyRequest]
        let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
        try? handler.perform(requests)
        guard !Task.isCancelled else { return SaliencyDetection(candidates: [], saliencyInfo: nil) }

        guard let observation = saliencyRequest.results?.first,
              let objects = observation.salientObjects,
              !objects.isEmpty else { return SaliencyDetection(candidates: [], saliencyInfo: nil) }

        let maxConfidence = objects.map(\.confidence).max() ?? 0
        let label = Self.bestClassificationLabel(from: classifyRequest.results ?? [])
        var candidates = [SaliencyCandidate]()
        for object in objects {
            let candidate = SaliencyCandidate(normalizedRect: object.boundingBox, confidence: object.confidence)
            let area = candidate.normalizedRect.width * candidate.normalizedRect.height
            if area > 0.03 || candidate.confidence >= 0.9 {
                candidates.append(candidate)
            }
        }
        candidates.sort { $0.confidence > $1.confidence }
        return SaliencyDetection(
            candidates: candidates,
            saliencyInfo: candidates.isEmpty ? nil : SaliencyInfo(subjectLabel: label, subjectConfidence: maxConfidence),
        )
    }

    nonisolated static func selectSaliencyCandidate(
        _ candidates: [SaliencyCandidate],
        afPoint: CGPoint?,
        detailScores: [CGRect: Float] = [:],
    ) -> SaliencySelection {
        guard !candidates.isEmpty else {
            return SaliencySelection(candidateCount: 0, winningRegion: nil, reason: nil)
        }

        let visionAFPoint = afPoint.map { CGPoint(x: $0.x, y: 1.0 - $0.y) }
        func metrics(for candidate: SaliencyCandidate) -> (
            candidate: SaliencyCandidate,
            overlapsAF: Bool,
            distanceToAF: CGFloat,
            detail: Float,
            area: CGFloat,
        ) {
            let rect = candidate.normalizedRect
            let center = CGPoint(x: rect.midX, y: rect.midY)
            let distance = visionAFPoint.map { hypot(center.x - $0.x, center.y - $0.y) } ?? .infinity
            return (
                candidate,
                visionAFPoint.map(rect.contains) ?? false,
                distance,
                detailScores[rect] ?? 0,
                rect.width * rect.height,
            )
        }

        let ranked = candidates.map(metrics).sorted { lhs, rhs in
            if lhs.overlapsAF != rhs.overlapsAF { return lhs.overlapsAF }
            if visionAFPoint != nil, lhs.distanceToAF != rhs.distanceToAF { return lhs.distanceToAF < rhs.distanceToAF }
            if lhs.candidate.confidence != rhs.candidate.confidence { return lhs.candidate.confidence > rhs.candidate.confidence }
            if lhs.detail != rhs.detail { return lhs.detail > rhs.detail }
            if lhs.area != rhs.area { return lhs.area > rhs.area }
            let l = lhs.candidate.normalizedRect
            let r = rhs.candidate.normalizedRect
            return l.minX == r.minX ? l.minY < r.minY : l.minX < r.minX
        }
        let winner = ranked[0]
        let reason = if winner.overlapsAF {
            "AF overlap"
        } else if visionAFPoint != nil {
            "Nearest to AF point"
        } else if winner.candidate.confidence > 0 {
            "Highest saliency confidence"
        } else if winner.detail > 0 {
            "Strongest interior detail"
        } else {
            "Largest viable salient object"
        }
        return SaliencySelection(
            candidateCount: candidates.count,
            winningRegion: winner.candidate.normalizedRect,
            reason: reason,
        )
    }

    private nonisolated static func bestClassificationLabel(from observations: [VNClassificationObservation]) -> String? {
        guard !observations.isEmpty else { return nil }

        let subjectKeywords = [
            "bird", "raptor", "fowl", "waterfowl", "wildlife",
            "animal", "mammal", "vertebrate", "creature", "predator",
            "reptile", "amphibian", "insect", "spider",
            "dog", "cat", "horse", "deer", "bear", "fox", "wolf",
            "lion", "tiger", "elephant", "monkey", "ape",
            "person", "people", "human", "face", "portrait"
        ]

        let environmentTokens = [
            "structure", "plant", "grass", "tree", "forest", "wood",
            "nature", "outdoor", "indoor", "landscape", "sky", "water",
            "ground", "soil", "rock", "stone", "darkness", "light",
            "photography", "scene", "background", "texture", "pattern"
        ]

        for obs in observations where obs.confidence >= 0.06 {
            let id = obs.identifier.lowercased()
            if subjectKeywords.contains(where: { id.contains($0) }) {
                return obs.identifier.replacingOccurrences(of: "_", with: " ")
            }
        }

        for obs in observations where obs.confidence >= 0.15 {
            let id = obs.identifier.lowercased()
            if !environmentTokens.contains(where: { id.contains($0) }) {
                return obs.identifier.replacingOccurrences(of: "_", with: " ")
            }
        }

        return nil
    }

    // MARK: - Numeric helpers

    /// p90–p97 band mean relative to the p20 noise floor, penalized when fewer
    /// than 6% of pixels land in the band (sparse edges → likely out-of-focus).
    nonisolated static func robustTailScore(_ samples: [Float]) -> Float? {
        guard !samples.isEmpty else { return nil }
        // Note: with n == 1, p20 == p90 == p97 == the single element.
        // The p97 <= p90 branch fires and returns max(0, p90 - p20) == 0.0 (not nil).
        // Callers cannot distinguish "single pixel that scored zero" from "empty" by the return alone.
        var a = samples
        let n = a.count

        // Accelerate SIMD sort: O(n log n), no worst-case O(n²) for equal-value inputs.
        // The previous quickselect with median-of-one pivot was O(n²) when the Laplacian
        // output is heavily zero-biased (blurry/out-of-focus images at high ISO).
        vDSP.sort(&a, sortOrder: .ascending)

        func p(_ frac: Float) -> Float {
            a[min(max(Int(Float(n - 1) * frac), 0), n - 1)]
        }

        let p20 = p(0.20)
        let p90 = p(0.90)
        let p97 = p(0.97)

        if p97 <= p90 { return max(0, p90 - p20) }

        var sum: Float = 0
        var cnt = 0
        for v in samples where v >= p90 && v <= p97 {
            sum += max(0, v - p20)
            cnt += 1
        }
        guard cnt > 0 else { return max(0, p90 - p20) }

        let bandMean = sum / Float(cnt)
        let densityFactor = min(1.0, (Float(cnt) / Float(n)) / 0.06)

        return bandMean * densityFactor
    }

    /// Standard deviation of Laplacian sample values.
    /// Near zero for blurry/smooth regions; higher for real textured detail.
    nonisolated static func microContrast(_ samples: [Float]) -> Float {
        guard !samples.isEmpty else { return 0 }
        var sum: Float = 0
        var sum2: Float = 0
        var n: Float = 0
        for v in samples where v.isFinite {
            sum += v
            sum2 += v * v
            n += 1
        }
        guard n > 1 else { return 0 }
        let mean = sum / n
        return sqrt(max(0, (sum2 / n) - mean * mean))
    }

    // MARK: - Scalar scoring

    /// Produces a single scalar sharpness score for an image.
    ///
    /// Pipeline:
    /// 1. `buildAmplifiedLaplacian` → Gaussian pre-blur + Metal Laplacian + gain.
    /// 2. Render to an RGBAf bitmap so each pixel's edge energy is a `Float` in `.r`.
    /// 3. Collect three sample sets:
    ///    * **full**: all pixels inside the border inset (Gaussian edge artefacts excluded).
    ///    * **salient**: pixels inside the Vision attention bounding box (if any).
    ///    * **AF**: pixels inside a square of half-size `afRegionRadius`
    ///      centered on the camera's AF point (if any).
    /// 4. Each set is reduced to a scalar via `robustTailScore` (p90–p97 band mean).
    /// 5. Blend:  `score = (1 − w)·full + w·subject`,  where
    ///    `subject = 0.6·AF + 0.4·saliency` (whichever are present) and
    ///    `w = config.explicitSalientWeightOverride ?? apertureHint override ?? config.salientWeight`.
    /// 6. Penalties/bonuses on top of the blend:
    ///    * silhouette penalty if >62 % of subject energy sits in its outer 12 % rim;
    ///    * subject-size bonus `(1 + area · subjectSizeFactor)` for saliency-only;
    ///    * soft aperture-aware blur gate `0.20…1.0` driven by subject micro-contrast σ.
    private struct SharpnessAnalysis {
        let finalScore: Float
        let fullScore: Float?
        let salientScore: Float?
        let afScore: Float?
        let afCenterScore: Float?
        let afNeighborhoodScore: Float?
        let afLocalPatchScore: Float?
        let subjectInteriorPatchScore: Float?
        let localDetailScore: Float?
        let subjectMicro: Float
        let evidenceRegion: FocusEvidenceRegion
        let saliencySelection: SaliencySelection
    }

    private nonisolated static let motionBlurScoreThreshold: Float = 0.08
    private nonisolated static let motionBlurSigmaThreshold: Float = 0.012
    private nonisolated static let missedFocusMinimumGlobalScore: Float = 0.12
    private nonisolated static let missedFocusSubjectRatio: Float = 0.55

    nonisolated static func computeSharpnessBreakdown(
        from inputImage: CIImage,
        saliencyDetection: SaliencyDetection,
        afPoint: CGPoint?,
        context: CIContext,
        config: FocusDetectorConfig,
    ) -> SharpnessBreakdown? {
        guard let analysis = computeSharpnessAnalysis(
            from: inputImage,
            saliencyDetection: saliencyDetection,
            afPoint: afPoint,
            context: context,
            config: config,
        ) else { return nil }

        return SharpnessBreakdown(
            finalScore: analysis.finalScore,
            globalScore: analysis.fullScore,
            subjectScore: analysis.salientScore,
            afPointScore: analysis.afScore,
            blurGateSigma: analysis.subjectMicro,
            subjectLabel: saliencyDetection.saliencyInfo?.subjectLabel,
            subjectConfidence: saliencyDetection.saliencyInfo?.subjectConfidence,
            focusFailureKind: classifyFocusFailure(
                globalScore: analysis.fullScore,
                subjectScore: analysis.salientScore,
                afPointScore: analysis.afScore,
                blurGateSigma: analysis.subjectMicro,
            ),
            focusEvidence: FocusEvidence(
                winningRegion: analysis.evidenceRegion,
                afCenterScore: analysis.afCenterScore,
                afNeighborhoodScore: analysis.afNeighborhoodScore,
                scoringAFLocalPatchScore: analysis.afLocalPatchScore,
                scoringSubjectInteriorPatchScore: analysis.subjectInteriorPatchScore,
                scoringLocalDetailScore: analysis.localDetailScore,
                saliencyCandidateCount: analysis.saliencySelection.candidateCount,
                winningSaliencyRect: analysis.saliencySelection.winningRegion,
                saliencySelectionReason: analysis.saliencySelection.reason,
            ),
        )
    }

    nonisolated static func conservativeSubjectScore(
        broadSubjectScore: Float?,
        afLocalPatchScore: Float?,
        subjectInteriorPatchScore: Float?,
    ) -> (score: Float?, localDetailScore: Float?) {
        let localDetailScore: Float? = switch (afLocalPatchScore, subjectInteriorPatchScore) {
        case let (af?, subject?): af * 0.6 + subject * 0.4
        case let (af?, nil): af
        case let (nil, subject?): subject
        default: nil
        }
        let score: Float? = switch (broadSubjectScore, localDetailScore) {
        case let (broad?, local?): broad * 0.75 + local * 0.25
        case let (broad?, nil): broad
        case let (nil, local?): local
        default: nil
        }
        return (score, localDetailScore)
    }

    nonisolated static func classifyFocusFailure(
        globalScore: Float?,
        subjectScore: Float?,
        afPointScore: Float?,
        blurGateSigma: Float,
    ) -> FocusFailureKind {
        let subject = subjectScore ?? afPointScore
        let afOrSubject = afPointScore ?? subjectScore

        if (globalScore ?? 0) < motionBlurScoreThreshold,
           (subject ?? 0) < motionBlurScoreThreshold,
           (afOrSubject ?? 0) < motionBlurScoreThreshold,
           blurGateSigma < motionBlurSigmaThreshold {
            return .motionBlur
        }

        if let globalScore,
           let subject,
           globalScore >= missedFocusMinimumGlobalScore,
           subject / max(globalScore, 1e-6) < missedFocusSubjectRatio {
            return .missedFocus
        }

        return .none
    }

    nonisolated static func focusEvidenceRegion(
        globalScore: Float?,
        saliencyScore: Float?,
        afPointScore: Float?,
        afCenterScore: Float? = nil,
        afNeighborhoodScore: Float? = nil,
        afRegionRadius: Float,
    ) -> FocusEvidenceRegion {
        let validGlobal = globalScore.flatMap { $0.isFinite ? $0 : nil }
        let validSaliency = saliencyScore.flatMap { $0.isFinite ? $0 : nil }
        let validAF = afPointScore.flatMap { $0.isFinite ? $0 : nil }
        let validAFCenter = afCenterScore.flatMap { $0.isFinite ? $0 : nil }
        let validAFNeighborhood = afNeighborhoodScore.flatMap { $0.isFinite ? $0 : nil }

        guard validGlobal != nil || validSaliency != nil || validAF != nil || validAFCenter != nil || validAFNeighborhood != nil else {
            return .none
        }

        let strongestNonLocal = max(validGlobal ?? 0, validSaliency ?? 0, validAF ?? 0)
        if let center = validAFCenter, center >= strongestNonLocal * 0.82 {
            return .afCenter
        }

        if let neighborhood = validAFNeighborhood, neighborhood >= strongestNonLocal * 0.88 {
            return .afNeighborhood
        }

        if let af = validAF {
            let strongestOther = max(validGlobal ?? 0, validSaliency ?? 0)
            let wildlifeSizedAF = afRegionRadius > 0 && afRegionRadius <= 0.08
            if wildlifeSizedAF, af >= strongestOther * 0.85 {
                return .afPoint
            }

            if let saliency = validSaliency {
                let maxSubject = max(af, saliency)
                let minSubject = min(af, saliency)
                if maxSubject > 0, minSubject / maxSubject >= 0.92 {
                    return .mixed
                }
            }
        }

        let candidates: [(FocusEvidenceRegion, Float)] = [
            (.afCenter, validAFCenter ?? -.infinity),
            (.afNeighborhood, validAFNeighborhood ?? -.infinity),
            (.afPoint, validAF ?? -.infinity),
            (.saliency, validSaliency ?? -.infinity),
            (.global, validGlobal ?? -.infinity)
        ]
        return candidates.max(by: { $0.1 < $1.1 })?.0 ?? .none
    }

    private nonisolated static func computeSharpnessAnalysis(
        from inputImage: CIImage,
        saliencyDetection: SaliencyDetection,
        afPoint: CGPoint?,
        context: CIContext,
        config: FocusDetectorConfig,
    ) -> SharpnessAnalysis? {
        guard !Task.isCancelled else { return nil }
        guard let boosted = buildScoringLaplacian(from: inputImage, config: config) else { return nil }

        let extent = boosted.extent
        let width = Int(extent.width)
        let height = Int(extent.height)
        guard width > 0, height > 0 else { return nil }

        let pixelCount = width * height
        var rgba = [Float](repeating: 0, count: pixelCount * 4)
        context.render(
            boosted,
            toBitmap: &rgba,
            rowBytes: width * 16,
            bounds: extent,
            format: .RGBAf,
            colorSpace: nil,
        )
        guard !Task.isCancelled else { return nil }

        @inline(__always)
        func redAt(_ idx: Int) -> Float {
            rgba[idx * 4]
        }

        // Exclude outer border to avoid Gaussian edge artifacts
        let borderCols = max(0, Int(Float(width) * config.borderInsetFraction))
        let borderRows = max(0, Int(Float(height) * config.borderInsetFraction))
        let innerW = max(0, width - 2 * borderCols)
        let innerH = max(0, height - 2 * borderRows)

        var full = [Float]()
        full.reserveCapacity(innerW * innerH)
        for row in borderRows ..< (height - borderRows) {
            if row & 0x3F == 0, Task.isCancelled { return nil }
            let base = row * width
            for col in borderCols ..< (width - borderCols) {
                let v = redAt(base + col)
                if v.isFinite { full.append(v) }
            }
        }

        // Single-pass region analysis: pixel samples + silhouette fraction together.
        struct RegionAnalysis {
            let samples: [Float]
            let borderFraction: Float // border energy / total; high => silhouette-dominated
        }

        func analyzeRegion(_ region: CGRect) -> RegionAnalysis {
            let colStart = max(0, Int(region.minX * CGFloat(width)))
            let colEnd = min(width, Int(region.maxX * CGFloat(width)))
            // Vision uses y=0 at the visual bottom; CIImage(cgImage:) flips to top-left
            // origin, so context.render fills row 0 at the visual top. Invert y so we
            // sample the region Vision identified. Removing this flip silently scores
            // the wrong area.
            let rowStart = max(0, Int((1.0 - region.maxY) * CGFloat(height)))
            let rowEnd = min(height, Int((1.0 - region.minY) * CGFloat(height)))

            guard colEnd > colStart, rowEnd > rowStart else {
                return RegionAnalysis(samples: [], borderFraction: 1.0)
            }

            let rw = colEnd - colStart
            let rh = rowEnd - rowStart
            let b = max(1, Int(0.12 * Float(min(rw, rh))))

            var samples = [Float]()
            samples.reserveCapacity(rw * rh)
            var borderSum: Float = 0
            var borderCnt = 0
            var innerSum: Float = 0
            var innerCnt = 0

            for row in rowStart ..< rowEnd {
                if row & 0x3F == 0, Task.isCancelled { return RegionAnalysis(samples: [], borderFraction: 1.0) }
                let base = row * width
                for col in colStart ..< colEnd {
                    let v = redAt(base + col)
                    guard v.isFinite else { continue }
                    samples.append(v)

                    let isBorder =
                        (col - colStart) < b || (colEnd - 1 - col) < b ||
                        (row - rowStart) < b || (rowEnd - 1 - row) < b

                    if isBorder {
                        borderSum += v
                        borderCnt += 1
                    } else {
                        innerSum += v
                        innerCnt += 1
                    }
                }
            }

            let borderFraction: Float
            if borderCnt > 0, innerCnt > 0 {
                let bm = borderSum / Float(borderCnt)
                let im = innerSum / Float(innerCnt)
                borderFraction = bm / max(bm + im, 1e-6)
            } else {
                borderFraction = 1.0
            }

            return RegionAnalysis(samples: samples, borderFraction: borderFraction)
        }

        let fullScore = Self.robustTailScore(full)

        var salientAnalyses: [CGRect: RegionAnalysis] = [:]
        var salientDetailScores: [CGRect: Float] = [:]
        for candidate in saliencyDetection.candidates {
            guard !Task.isCancelled else { return nil }
            let analysis = analyzeRegion(candidate.normalizedRect)
            salientAnalyses[candidate.normalizedRect] = analysis
            if analysis.samples.count >= 64 {
                salientDetailScores[candidate.normalizedRect] = Self.robustTailScore(analysis.samples)
            }
        }
        let saliencySelection = Self.selectSaliencyCandidate(
            saliencyDetection.candidates,
            afPoint: afPoint,
            detailScores: salientDetailScores,
        )
        let salientRegion = saliencySelection.winningRegion
        let salientAnalysis = salientRegion.flatMap { salientAnalyses[$0] }
        let salientScore = salientRegion.flatMap { salientDetailScores[$0] }

        // AF-point subject score
        var afAnalysis: RegionAnalysis?
        var afScore: Float?
        var afCenterScore: Float?
        var afNeighborhoodScore: Float?
        var afRegionUsed: CGRect?
        if let afRegion = Self.afUnitRegion(afPoint: afPoint, radius: config.afRegionRadius) {
            let a = analyzeRegion(afRegion)
            if a.samples.count >= 64 {
                afScore = Self.robustTailScore(a.samples)
                afRegionUsed = afRegion
                afAnalysis = a
            }
        }

        if let afCenterRegion = Self.afUnitRegion(afPoint: afPoint, radius: config.afCenterRegionRadius) {
            let a = analyzeRegion(afCenterRegion)
            if a.samples.count >= 16 {
                afCenterScore = Self.robustTailScore(a.samples)
            }
        }

        if let afNeighborhoodRegion = Self.afUnitRegion(afPoint: afPoint, radius: config.afNeighborhoodRegionRadius) {
            let a = analyzeRegion(afNeighborhoodRegion)
            if a.samples.count >= 64 {
                afNeighborhoodScore = Self.robustTailScore(a.samples)
            }
        }

        func bestLocalPatchScore(in unitRegion: CGRect?, visualRegion: FocusEvidenceRegion) -> Float? {
            guard !Task.isCancelled,
                  let rect = Self.pixelRect(from: unitRegion, in: extent)
            else { return nil }
            return Self.selectEvidencePatches(
                from: Self.patchRankings(
                    in: rect,
                    sourceImage: boosted,
                    extent: extent,
                    afPoint: afPoint,
                    visualRegion: visualRegion,
                    context: context,
                ),
                visualRegion: visualRegion,
            ).first?.robustTailScore
        }
        let afLocalPatchScore = bestLocalPatchScore(
            in: Self.afUnitRegion(afPoint: afPoint, radius: config.afNeighborhoodRegionRadius),
            visualRegion: .afNeighborhood,
        )
        let subjectInteriorPatchScore = bestLocalPatchScore(in: salientRegion, visualRegion: .saliency)

        // AF and saliency both signal "where the subject is" but with different confidence
        // characteristics: AF is camera-provided ground truth for where focus was attempted;
        // Vision saliency is a perceptual model. Blending keeps both signals in the mix
        // rather than AF silently overriding saliency (the earlier `afScore ?? salientScore`
        // behaviour), which occasionally mis-ranked when the AF point landed on a secondary
        // subject while Vision correctly identified the main one.
        let broadSubjectScore: Float? = switch (afScore, salientScore) {
        case let (a?, s?): a * 0.6 + s * 0.4
        case let (a?, nil): a
        case let (nil, s?): s
        default: nil
        }
        let localBlend = Self.conservativeSubjectScore(
            broadSubjectScore: broadSubjectScore,
            afLocalPatchScore: afLocalPatchScore,
            subjectInteriorPatchScore: subjectInteriorPatchScore,
        )
        let effectiveSubjectScore = localBlend.score
        // Prefer AF analysis for micro-contrast / silhouette because the AF region is
        // usually tighter than the Vision salient union.
        let effectiveAnalysis = afAnalysis ?? salientAnalysis

        // Soft blur gate: subject-region σ below blurGateLow → multiplier 0.20,
        // above blurGateHigh → 1.0, linearly ramped in between. Replaces an earlier
        // hard σ<0.014 → ×0.12 cliff that false-positived on low-contrast subjects
        // (white bird against white sky, fog, plain-backdrop portraits).
        let subjectMicro = effectiveAnalysis.map { Self.microContrast($0.samples) } ?? 0
        let hint = config.apertureHint
        let blurAttenuation: Float
        if let ea = effectiveAnalysis, ea.samples.count >= 64 {
            let lo = hint.blurGateLow
            let hi = hint.blurGateHigh
            let span = max(hi - lo, 1e-6)
            let t = min(max((subjectMicro - lo) / span, 0), 1)
            blurAttenuation = 0.20 + t * 0.80
        } else {
            blurAttenuation = 1.0
        }

        // Landscape (deep DoF) pulls the salient weight down so the full-frame score
        // is not dominated by the Vision salient region on scenes where the whole
        // frame carries real in-focus detail.
        let salientWeight = config.explicitSalientWeightOverride ?? hint.salientWeightOverride ?? config.salientWeight

        let base: Float?
        switch (fullScore, effectiveSubjectScore) {
        case let (f?, s?):
            var blended = f * (1.0 - salientWeight) + s * salientWeight

            // Silhouette penalty: if >62% of the subject-region edge energy sits in its
            // outer 12% border, we're measuring the silhouette rim rather than subject
            // detail (common on backlit wildlife). Reduce the score by up to 55%.
            if let ea = effectiveAnalysis, config.silhouettePenaltyStrength > 0 {
                let frac = ea.borderFraction
                let silhouetteT: Float = 0.62
                if frac > silhouetteT {
                    let over = min(1.0, (frac - silhouetteT) / (1.0 - silhouetteT))
                    blended *= 1.0 - config.silhouettePenaltyStrength * over
                }
            }

            // Subject-size bonus only for Vision saliency (not AF): when the AF point is
            // present we already have a high-confidence subject locus, so the
            // subject-area nudge would double-count.
            if afRegionUsed == nil, let region = salientRegion {
                let area = Float(region.width * region.height)
                blended *= 1.0 + area * config.subjectSizeFactor
            }

            base = blended

        case let (f?, nil):
            // Full-frame score but no subject locus: cube-of-(1-salientWeight) penalizes
            // heavily because for a wildlife-first app, "no detectable subject" usually
            // means the Vision saliency pass failed on a messy / low-contrast frame. The
            // landscape hint softens this via the reduced salientWeight override.
            let p = 1.0 - salientWeight
            base = f * p * p * p

        case let (nil, s?):
            base = s

        default:
            base = nil
        }

        guard let baseScore = base else { return nil }
        return SharpnessAnalysis(
            finalScore: baseScore * blurAttenuation,
            fullScore: fullScore,
            salientScore: salientScore,
            afScore: afScore,
            afCenterScore: afCenterScore,
            afNeighborhoodScore: afNeighborhoodScore,
            afLocalPatchScore: afLocalPatchScore,
            subjectInteriorPatchScore: subjectInteriorPatchScore,
            localDetailScore: localBlend.localDetailScore,
            subjectMicro: subjectMicro,
            evidenceRegion: Self.focusEvidenceRegion(
                globalScore: fullScore,
                saliencyScore: salientScore,
                afPointScore: afScore,
                afCenterScore: afCenterScore,
                afNeighborhoodScore: afNeighborhoodScore,
                afRegionRadius: config.afRegionRadius,
            ),
            saliencySelection: saliencySelection,
        )
    }

    /// ISO→blur multiplier. Piecewise-linear: flat below ISO 800 (A1 / A1 II base is
    /// clean at low ISO), gentle rise 1.0→1.6 through ISO 3200, then a shallow tail to a
    /// cap of 2.2 at ~ISO 9600+. Replaces an earlier `sqrt(iso/400)` clamped to 3.0, which
    /// over-blurred real fine detail at ISO 6400+ on Sony A1-series bodies where noise is
    /// still well-controlled. The robust p90–p97 tail mean in `robustTailScore` already
    /// tolerates sparse noise, so the previous aggressive cap wasn't needed.
    nonisolated static func isoScalingFactor(iso: Int) -> Float {
        let i = Float(max(iso, 100))
        switch i {
        case ..<800:
            return 1.0

        case 800 ..< 3200:
            return 1.0 + (i - 800) / 2400 * 0.6

        default:
            return min(1.6 + (i - 3200) / 6400 * 0.6, 2.2)
        }
    }

    /// Edge-energy pipeline shared by both the mask overlay and the scalar score:
    /// 1. Gaussian pre-blur, radius = `preBlurRadius · isoFactor · resFactor · blurDamp`.
    ///    * `isoFactor` ∈ [1.0, 2.2] — see `isoScalingFactor(iso:)`.
    ///    * `resFactor = clamp(sqrt(max(width, 512) / 512), 1, 3)` — longer sides get
    ///      proportionally more blur so edge detail is sampled at a comparable scale
    ///      regardless of thumbnail resolution.
    ///    * `blurDamp` is 0.8 for landscape apertures (deep DoF scenes), 1.0 otherwise.
    ///    * Capped at 100 px to avoid pathological radii from malformed input.
    /// 2. Metal `focusLaplacian` kernel → per-pixel 2nd-derivative energy.
    /// 3. `CIColorMatrix` scales R/G/B by `energyMultiplier`.
    nonisolated static func resolutionScalingFactor(for extent: CGRect) -> Float {
        let longestSide = Float(max(extent.width, extent.height))
        return max(1.0, min(sqrt(max(longestSide, 512.0) / 512.0), 3.0))
    }

    nonisolated static func buildAmplifiedLaplacian(from image: CIImage, config: FocusDetectorConfig) -> CIImage? {
        guard !Task.isCancelled else { return nil }
        let isoFactor = Self.isoScalingFactor(iso: config.iso)
        let resFactor = Self.resolutionScalingFactor(for: image.extent)
        // Landscape (deep DoF) damps the combined ISO × resolution blur so the whole-
        // frame edge energy isn't smoothed away before the Laplacian fires.
        let blurDamp = config.apertureHint.blurDamp
        let effectiveRadius = min(config.preBlurRadius * isoFactor * resFactor * blurDamp, 100.0)

        let preBlur = CIFilter.gaussianBlur()
        preBlur.inputImage = image
        preBlur.radius = effectiveRadius
        guard let smoothed = preBlur.outputImage else { return nil }
        guard !Task.isCancelled else { return nil }

        guard let kernel = _focusMagnitudeKernel else { return nil }
        guard let laplacianOutput = kernel.apply(
            extent: smoothed.extent.insetBy(dx: 1, dy: 1),
            roiCallback: { _, rect in rect.insetBy(dx: -2, dy: -2) },
            arguments: [smoothed],
        ) else { return nil }
        guard !Task.isCancelled else { return nil }

        let boost = CIFilter.colorMatrix()
        boost.inputImage = laplacianOutput
        boost.rVector = CIVector(x: CGFloat(config.energyMultiplier), y: 0, z: 0, w: 0)
        boost.gVector = CIVector(x: 0, y: CGFloat(config.energyMultiplier), z: 0, w: 0)
        boost.bVector = CIVector(x: 0, y: 0, z: CGFloat(config.energyMultiplier), w: 0)
        boost.aVector = CIVector(x: 0, y: 0, z: 0, w: 1)
        return boost.outputImage
    }

    /// Scoring-only Laplacian. Slower quality modes blend the normal blur scale
    /// with a finer pass so small feathers, eyes, and eyelashes survive the
    /// noise-reduction pre-blur instead of being averaged away.
    private nonisolated static func buildScoringLaplacian(from image: CIImage, config: FocusDetectorConfig) -> CIImage? {
        var scoringConfig = config
        scoringConfig.energyMultiplier = SharpnessScoringSignature.stableScoringEnergyMultiplier
        guard let primary = buildAmplifiedLaplacian(from: image, config: scoringConfig) else { return nil }
        let w = min(max(config.fineDetailBlendWeight, 0), 0.65)
        guard w > 0 else { return primary }

        var fineConfig = scoringConfig
        fineConfig.preBlurRadius = max(0.35, scoringConfig.preBlurRadius * 0.58)
        guard let fine = buildAmplifiedLaplacian(from: image, config: fineConfig) else { return primary }

        func scaled(_ input: CIImage, by amount: Float) -> CIImage? {
            let scale = CIFilter.colorMatrix()
            scale.inputImage = input
            scale.rVector = CIVector(x: CGFloat(amount), y: 0, z: 0, w: 0)
            scale.gVector = CIVector(x: 0, y: CGFloat(amount), z: 0, w: 0)
            scale.bVector = CIVector(x: 0, y: 0, z: CGFloat(amount), w: 0)
            scale.aVector = CIVector(x: 0, y: 0, z: 0, w: 1)
            return scale.outputImage
        }

        guard let primaryWeighted = scaled(primary, by: 1.0 - w),
              let fineWeighted = scaled(fine, by: w),
              let add = CIFilter(name: "CIAdditionCompositing")
        else {
            #if DEBUG
                Logger.process.debugMessageOnly("buildScoringLaplacian: CIAdditionCompositing unavailable, using primary Laplacian only")
            #endif
            return primary
        }

        add.setValue(fineWeighted, forKey: kCIInputImageKey)
        add.setValue(primaryWeighted, forKey: kCIInputBackgroundImageKey)
        return add.outputImage?.cropped(to: primary.extent) ?? primary
    }
}
