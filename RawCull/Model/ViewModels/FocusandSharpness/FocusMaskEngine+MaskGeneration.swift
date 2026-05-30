import Accelerate
import AppKit
import CoreImage
import CoreImage.CIFilterBuiltins

extension FocusMaskEngine {
    nonisolated func generateFocusMask(
        from cgImage: CGImage,
        scale: CGFloat,
        config: FocusDetectorConfig,
        afPoint: CGPoint? = nil,
        evidence: FocusEvidence? = nil,
    ) async -> CGImage? {
        let context = self.context

        return await Task.detached(priority: .userInitiated) {
            let salientRegion: CGRect? = if config.isolateMaskToSubject {
                Self.detectSaliencyAndClassify(
                    for: cgImage,
                    classify: false,
                ).region
            } else {
                nil
            }

            return Self.buildFocusMask(
                from: CIImage(cgImage: cgImage),
                scale: scale,
                salientRegion: salientRegion,
                afPoint: afPoint,
                evidenceRegion: evidence?.winningRegion,
                evidence: evidence,
                context: context,
                config: config,
            ).image
        }.value
    }

    nonisolated func generateFocusMaskWithBreakdown(
        from cgImage: CGImage,
        scale: CGFloat,
        config: FocusDetectorConfig,
        afPoint: CGPoint? = nil,
    ) async -> (mask: CGImage?, saliency: SaliencyInfo?, breakdown: SharpnessBreakdown?) {
        let context = self.context

        return await Task.detached(priority: .userInitiated) {
            let ciImage = CIImage(cgImage: cgImage)
            let (region, saliencyInfo) = Self.detectSaliencyAndClassify(
                for: cgImage,
                classify: config.enableSubjectClassification,
            )
            var breakdown = Self.computeSharpnessBreakdown(
                from: ciImage,
                salientRegion: region,
                saliencyInfo: saliencyInfo,
                afPoint: afPoint,
                context: context,
                config: config,
            )
            let maskResult = Self.buildFocusMask(
                from: ciImage,
                scale: scale,
                salientRegion: region,
                afPoint: afPoint,
                evidenceRegion: breakdown?.focusEvidence?.winningRegion,
                evidence: breakdown?.focusEvidence,
                context: context,
                config: config,
            )
            breakdown?.focusMaskRegionSource = maskResult.diagnostics.regionSource
            breakdown?.focusMaskVisualThreshold = maskResult.diagnostics.visualThreshold
            if let evidence = maskResult.evidence {
                breakdown?.focusEvidence = evidence
            }
            return (maskResult.image, saliencyInfo, breakdown)
        }.value
    }

    private nonisolated static func buildFocusMask(
        from inputImage: CIImage,
        scale: CGFloat,
        salientRegion: CGRect?,
        afPoint: CGPoint?,
        evidenceRegion: FocusEvidenceRegion?,
        evidence: FocusEvidence?,
        context: CIContext,
        config: FocusDetectorConfig,
    ) -> FocusMaskRenderResult {
        let emptyDiagnostics = FocusMaskDiagnostics(regionSource: .none, visualThreshold: nil)
        let scaledImage = inputImage.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
        guard let rawLaplacian = Self.buildAmplifiedLaplacian(from: scaledImage, config: config) else {
            return FocusMaskRenderResult(image: nil, diagnostics: emptyDiagnostics, evidence: evidence)
        }

        let boostedLaplacian: CIImage
        if config.borderInsetFraction > 0 {
            let ext = scaledImage.extent
            let borderX = ext.width * CGFloat(config.borderInsetFraction)
            let borderY = ext.height * CGFloat(config.borderInsetFraction)
            let innerRect = ext.insetBy(dx: borderX, dy: borderY)
            let blackBg = CIImage(color: .black).cropped(to: ext)
            boostedLaplacian = rawLaplacian.cropped(to: innerRect).composited(over: blackBg)
        } else {
            boostedLaplacian = rawLaplacian
        }

        if config.showRawLaplacian {
            let selection = Self.focusMaskRegionSelection(
                extent: scaledImage.extent,
                salientRegion: config.isolateMaskToSubject ? salientRegion : nil,
                afPoint: config.isolateMaskToSubject ? afPoint : nil,
                afRegionRadius: config.afRegionRadius,
            )
            let cropped = boostedLaplacian.cropped(to: scaledImage.extent)
            return FocusMaskRenderResult(
                image: context.createCGImage(cropped, from: cropped.extent),
                diagnostics: FocusMaskDiagnostics(regionSource: selection.source, visualThreshold: nil),
                evidence: evidence,
            )
        }

        let selection = if config.isolateMaskToSubject {
            Self.focusMaskRegionSelection(
                extent: scaledImage.extent,
                salientRegion: salientRegion,
                afPoint: afPoint,
                afRegionRadius: config.afRegionRadius,
            )
        } else {
            FocusMaskRegionSelection(saliencyRect: scaledImage.extent, afRect: nil)
        }
        let afCenterRect = Self.pixelRect(
            from: Self.afUnitRegion(afPoint: afPoint, radius: config.afCenterRegionRadius),
            in: scaledImage.extent,
        )
        let afNeighborhoodRect = Self.pixelRect(
            from: Self.afUnitRegion(afPoint: afPoint, radius: config.afNeighborhoodRegionRadius),
            in: scaledImage.extent,
        )

        let requestedEvidenceRegion = evidenceRegion ?? .none
        let visualEvidenceRegion: FocusEvidenceRegion = switch requestedEvidenceRegion {
        case .afCenter where afCenterRect != nil:
            .afCenter

        case .afNeighborhood where afNeighborhoodRect != nil:
            .afNeighborhood

        case .afPoint where selection.afRect != nil:
            .afPoint

        case .saliency where selection.saliencyRect != nil:
            .saliency

        case .mixed where selection.afRect != nil || selection.saliencyRect != nil:
            .mixed

        case .global:
            .global

        default:
            switch (selection.afRect, selection.saliencyRect) {
            case (.some, _): .afPoint
            case (nil, .some): .saliency
            default: .global
            }
        }

        let fineLaplacian: CIImage?
        if selection.afRect != nil || afCenterRect != nil || afNeighborhoodRect != nil {
            var fineConfig = config
            fineConfig.preBlurRadius = max(0.35, config.preBlurRadius * 0.52)
            fineLaplacian = Self.buildAmplifiedLaplacian(from: scaledImage, config: fineConfig) ?? boostedLaplacian
        } else {
            fineLaplacian = nil
        }

        let afPixelCenter = Self.afPixelCenter(afPoint: afPoint, in: scaledImage.extent)
        func afWeightedSource(for rect: CGRect) -> CIImage {
            let source = fineLaplacian ?? boostedLaplacian
            guard let afPixelCenter,
                  let weighted = Self.centerWeightedLaplacian(
                      source,
                      center: afPixelCenter,
                      rect: rect,
                      extent: scaledImage.extent,
                  )
            else { return source }
            return weighted
        }

        let searchRegions: [(CGRect, CIImage)] = switch visualEvidenceRegion {
        case .afCenter:
            if let afCenterRect {
                [(afCenterRect, afWeightedSource(for: afCenterRect))]
            } else { [] }

        case .afNeighborhood:
            if let afNeighborhoodRect {
                [(afNeighborhoodRect, afWeightedSource(for: afNeighborhoodRect))]
            } else { [] }

        case .afPoint:
            if let afRect = selection.afRect {
                [(afRect, afWeightedSource(for: afRect))]
            } else { [] }

        case .saliency:
            if let saliencyRect = selection.saliencyRect {
                [(saliencyRect, boostedLaplacian)]
            } else { [] }

        case .mixed:
            [
                selection.afRect.map { ($0, afWeightedSource(for: $0)) },
                selection.saliencyRect.map { ($0, boostedLaplacian) }
            ].compactMap { $0 }

        case .global, .none:
            [(scaledImage.extent, boostedLaplacian)]
        }

        var rankings = searchRegions
            .flatMap { region, source in
                Self.patchRankings(
                    in: region,
                    sourceImage: source,
                    extent: scaledImage.extent,
                    afPoint: afPoint,
                    visualRegion: visualEvidenceRegion,
                    context: context,
                )
            }
        if let afPixelCenter {
            let afPatchWidth = scaledImage.extent.width * 0.06
            let afPatchHeight = scaledImage.extent.height * 0.06
            let afPatchRect = CGRect(
                x: afPixelCenter.x - afPatchWidth * 0.5,
                y: afPixelCenter.y - afPatchHeight * 0.5,
                width: afPatchWidth,
                height: afPatchHeight,
            ).intersection(scaledImage.extent)
            rankings.append(Self.patchRanking(
                for: afPatchRect,
                searchRegion: scaledImage.extent,
                sourceImage: fineLaplacian ?? boostedLaplacian,
                extent: scaledImage.extent,
                afPoint: afPoint,
                visualRegion: visualEvidenceRegion,
                context: context,
            ))
        }
        let selectedPatches = Self.selectEvidencePatches(
            from: rankings,
            visualRegion: visualEvidenceRegion,
        )
        let overlayStyle: FocusEvidenceOverlayStyle = visualEvidenceRegion == .global ? .globalDetail : .subjectHeat
        let masks = selectedPatches.compactMap {
            Self.heatPatch(
                for: $0.normalizedRect,
                extent: scaledImage.extent,
                style: overlayStyle,
            )
        }
        let patchMask: CIImage = switch masks.count {
        case 0:
            CIImage(color: .clear).cropped(to: scaledImage.extent)

        case 1:
            masks[0]

        default:
            masks.dropFirst().reduce(masks[0]) { partial, next in
                Self.maximumComposite(next, over: partial).cropped(to: scaledImage.extent)
            }
        }

        let feathered: CIImage
        if config.featherRadius > 0 {
            let featherBlur = CIFilter.gaussianBlur()
            featherBlur.inputImage = patchMask
            featherBlur.radius = config.featherRadius
            feathered = featherBlur.outputImage ?? patchMask
        } else {
            feathered = patchMask
        }
        let croppedMask = feathered.cropped(to: scaledImage.extent)
        return FocusMaskRenderResult(
            image: context.createCGImage(croppedMask, from: croppedMask.extent),
            diagnostics: FocusMaskDiagnostics(regionSource: selection.source, visualThreshold: nil),
            evidence: Self.focusEvidenceDiagnostics(
                from: evidence,
                visualRegion: visualEvidenceRegion,
                selectedPatches: selectedPatches,
                rankings: rankings,
                overlayStyle: overlayStyle,
                afPoint: afPoint,
            ),
        )
    }

    nonisolated static func focusMaskRegionSelection(
        extent: CGRect,
        salientRegion: CGRect?,
        afPoint: CGPoint?,
        afRegionRadius: Float,
    ) -> FocusMaskRegionSelection {
        let unitBounds = CGRect(x: 0, y: 0, width: 1, height: 1)
        let saliencyUnitRect: CGRect? = if let salientRegion, !salientRegion.isNull, !salientRegion.isEmpty {
            salientRegion.intersection(unitBounds)
        } else {
            nil
        }

        let afUnitRect: CGRect? = {
            guard let afPoint, afRegionRadius > 0 else { return nil }
            let r = CGFloat(afRegionRadius)
            let visionY = 1.0 - afPoint.y
            let afRegion = CGRect(
                x: afPoint.x - r,
                y: visionY - r,
                width: r * 2,
                height: r * 2,
            )
            let intersection = afRegion.intersection(unitBounds)
            return intersection.isNull || intersection.isEmpty ? nil : intersection
        }()

        func pixelRect(from unitRegion: CGRect?) -> CGRect? {
            guard let unitRegion, !unitRegion.isNull, !unitRegion.isEmpty else { return nil }
            let rect = CGRect(
                x: extent.minX + unitRegion.minX * extent.width,
                y: extent.minY + unitRegion.minY * extent.height,
                width: unitRegion.width * extent.width,
                height: unitRegion.height * extent.height,
            ).integral.intersection(extent)
            return rect.isNull || rect.isEmpty ? nil : rect
        }

        return FocusMaskRegionSelection(
            saliencyRect: pixelRect(from: saliencyUnitRect),
            afRect: pixelRect(from: afUnitRect),
        )
    }

    nonisolated static func afUnitRegion(afPoint: CGPoint?, radius: Float) -> CGRect? {
        guard let afPoint, radius > 0 else { return nil }
        let unitBounds = CGRect(x: 0, y: 0, width: 1, height: 1)
        let r = CGFloat(radius)
        let visionY = 1.0 - afPoint.y
        let region = CGRect(
            x: afPoint.x - r,
            y: visionY - r,
            width: r * 2,
            height: r * 2,
        ).intersection(unitBounds)
        return region.isNull || region.isEmpty ? nil : region
    }

    nonisolated static func pixelRect(from unitRegion: CGRect?, in extent: CGRect) -> CGRect? {
        guard let unitRegion, !unitRegion.isNull, !unitRegion.isEmpty else { return nil }
        let rect = CGRect(
            x: extent.minX + unitRegion.minX * extent.width,
            y: extent.minY + unitRegion.minY * extent.height,
            width: unitRegion.width * extent.width,
            height: unitRegion.height * extent.height,
        ).integral.intersection(extent)
        return rect.isNull || rect.isEmpty ? nil : rect
    }

    nonisolated static func afPixelCenter(afPoint: CGPoint?, in extent: CGRect) -> CGPoint? {
        guard let afPoint else { return nil }
        return CGPoint(
            x: extent.minX + afPoint.x * extent.width,
            y: extent.minY + (1.0 - afPoint.y) * extent.height,
        )
    }

    nonisolated static func adaptiveVisualThreshold(
        _ samples: [Float],
        fallback: Float,
        percentile: Float,
        floorMultiplier: Float,
        capAtFallback: Bool,
    ) -> Float {
        let floor = max(fallback * floorMultiplier, 0.01)
        let finite = samples.filter { $0.isFinite && $0 > 0 }
        guard !finite.isEmpty else {
            return min(floor, 0.95)
        }

        var sorted = finite
        vDSP.sort(&sorted, sortOrder: .ascending)
        let p = min(max(percentile, 0), 1)
        let index = min(max(Int(Float(sorted.count - 1) * p), 0), sorted.count - 1)
        let adaptive = capAtFallback ? min(sorted[index], fallback) : sorted[index]
        return min(max(adaptive, floor), 0.95)
    }

    nonisolated static func maskCoverage(_ samples: [Float], threshold: Float) -> Float {
        let finite = samples.filter(\.isFinite)
        guard !finite.isEmpty, threshold.isFinite else { return 0 }
        let covered = finite.reduce(0) { partial, value in
            partial + (value >= threshold ? 1 : 0)
        }
        return Float(covered) / Float(finite.count)
    }

    nonisolated static func relaxedVisualThreshold(
        _ samples: [Float],
        currentThreshold: Float,
        minimumCoverage: Float,
    ) -> (threshold: Float, coverage: Float, relaxed: Bool) {
        let finite = samples.filter { $0.isFinite && $0 > 0 }
        let currentCoverage = maskCoverage(samples, threshold: currentThreshold)
        let targetCoverage = min(max(minimumCoverage, 0), 1)
        guard targetCoverage > 0, currentCoverage < targetCoverage, !finite.isEmpty else {
            return (currentThreshold, currentCoverage, false)
        }

        var sorted = finite
        vDSP.sort(&sorted, sortOrder: .ascending)
        let coveredCount = max(1, Int(ceil(Float(sorted.count) * targetCoverage)))
        let index = min(max(sorted.count - coveredCount, 0), sorted.count - 1)
        let relaxedThreshold = min(currentThreshold, sorted[index])
        let relaxedCoverage = maskCoverage(samples, threshold: relaxedThreshold)
        return (relaxedThreshold, relaxedCoverage, relaxedThreshold < currentThreshold)
    }

    nonisolated static func selectEvidencePatches(
        from rankings: [FocusPatchRanking],
        visualRegion: FocusEvidenceRegion,
    ) -> [FocusPatchRanking] {
        let viable = rankings
            .filter { $0.compositeScore.isFinite && $0.compositeScore > 0 }
            .sorted { $0.compositeScore > $1.compositeScore }
        guard !viable.isEmpty else { return [] }

        var ordered = viable
        if visualRegion.isAFAnchored,
           let nearest = viable.min(by: { ($0.distanceToAF ?? .infinity) < ($1.distanceToAF ?? .infinity) }),
           let strongest = viable.first,
           strongest != nearest,
           strongest.compositeScore < nearest.compositeScore * 1.15 {
            ordered.removeAll { $0 == nearest }
            ordered.insert(nearest, at: 0)
        }

        var selected: [FocusPatchRanking] = []
        for candidate in ordered {
            guard selected.allSatisfy({ overlapRatio(candidate.normalizedRect, $0.normalizedRect) < 0.55 }) else {
                continue
            }
            selected.append(candidate)
            if selected.count == 3 { break }
        }
        return selected
    }

    private nonisolated static func patchRankings(
        in region: CGRect,
        sourceImage: CIImage,
        extent: CGRect,
        afPoint: CGPoint?,
        visualRegion: FocusEvidenceRegion,
        context: CIContext,
    ) -> [FocusPatchRanking] {
        let boundedRegion = region.integral.intersection(extent)
        guard !boundedRegion.isNull, !boundedRegion.isEmpty else { return [] }

        let patchWidth = min(max(boundedRegion.width * 0.34, extent.width * 0.035), extent.width * 0.14)
        let patchHeight = min(max(boundedRegion.height * 0.34, extent.height * 0.035), extent.height * 0.14)
        let stepX = max(1, patchWidth * 0.50)
        let stepY = max(1, patchHeight * 0.50)
        var rects: [CGRect] = []

        var y = boundedRegion.minY
        while y + patchHeight <= boundedRegion.maxY + 0.5 {
            var x = boundedRegion.minX
            while x + patchWidth <= boundedRegion.maxX + 0.5 {
                rects.append(CGRect(x: x, y: y, width: patchWidth, height: patchHeight))
                x += stepX
            }
            y += stepY
        }

        if let afPixel = afPixelCenter(afPoint: afPoint, in: extent) {
            let centered = CGRect(
                x: afPixel.x - patchWidth * 0.5,
                y: afPixel.y - patchHeight * 0.5,
                width: patchWidth,
                height: patchHeight,
            ).intersection(boundedRegion)
            if centered.width >= patchWidth * 0.75, centered.height >= patchHeight * 0.75 {
                rects.append(centered)
            }
        }

        return rects.map {
            patchRanking(
                for: $0,
                searchRegion: boundedRegion,
                sourceImage: sourceImage,
                extent: extent,
                afPoint: afPoint,
                visualRegion: visualRegion,
                context: context,
            )
        }
    }

    private nonisolated static func patchRanking(
        for rect: CGRect,
        searchRegion: CGRect,
        sourceImage: CIImage,
        extent: CGRect,
        afPoint: CGPoint?,
        visualRegion: FocusEvidenceRegion,
        context: CIContext,
    ) -> FocusPatchRanking {
        let grid = redSampleGrid(in: rect, from: sourceImage, context: context)
        let samples = grid.samples
        let robust = robustTailScore(samples) ?? 0
        let micro = microContrast(samples)
        let threshold = adaptiveVisualThreshold(
            samples,
            fallback: 0.46,
            percentile: 0.88,
            floorMultiplier: 0.32,
            capAtFallback: true,
        )
        let coverage = maskCoverage(samples, threshold: threshold)
        let inset = rect.insetBy(dx: rect.width * 0.18, dy: rect.height * 0.18)
        let innerMean = sampleMean(redSamples(in: inset, from: sourceImage, context: context))
        let allMean = sampleMean(samples)
        let silhouette = max(0, min(1, (allMean - innerMean) / max(allMean, 1e-6)))
        let normalizedRect = normalizedRect(rect, in: extent)
        let centroid = CGPoint(x: normalizedRect.midX, y: normalizedRect.midY)
        let distance = afPoint.map { normalizedDistance(from: centroid, to: $0) }
        let afProximity = distance.map { max(0, 1 - $0 / 0.20) } ?? 0
        let touchesSearchBorder =
            abs(rect.minX - searchRegion.minX) < 1 ||
            abs(rect.maxX - searchRegion.maxX) < 1 ||
            abs(rect.minY - searchRegion.minY) < 1 ||
            abs(rect.maxY - searchRegion.maxY) < 1
        let interiorBonus: Float = touchesSearchBorder ? 0 : 0.03
        let silhouettePenalty: Float = visualRegion.isAFAnchored ? 0.18 : 0.45
        let shape = patchShapeEvidence(samples: samples, width: grid.width, height: grid.height)
        let eyeHeadAdjustment = eyeHeadHeuristicAdjustment(
            ringDetailScore: shape.ringDetailScore,
            compactDetailScore: shape.compactDetailScore,
            linearEdgePenalty: shape.linearEdgePenalty,
            centroid: centroid,
            afPoint: afPoint,
            visualRegion: visualRegion,
        )
        let composite = max(
            0,
            robust + micro * 0.35 + coverage * 0.08 + afProximity * 0.12 + interiorBonus
                - silhouette * silhouettePenalty + eyeHeadAdjustment.adjustment,
        )

        return FocusPatchRanking(
            normalizedRect: normalizedRect,
            robustTailScore: robust,
            microContrast: micro,
            coverage: coverage,
            distanceToAF: distance,
            silhouetteFraction: silhouette,
            ringDetailScore: shape.ringDetailScore,
            compactDetailScore: shape.compactDetailScore,
            linearEdgePenalty: shape.linearEdgePenalty,
            belowAFPenalty: eyeHeadAdjustment.belowAFPenalty,
            eyeHeadHeuristicAdjustment: eyeHeadAdjustment.adjustment,
            compositeScore: composite,
            containsAFPoint: afPoint.map(normalizedRect.contains) ?? false,
        )
    }

    nonisolated static func eyeHeadHeuristicAdjustment(
        ringDetailScore: Float,
        compactDetailScore: Float,
        linearEdgePenalty: Float,
        centroid: CGPoint,
        afPoint: CGPoint?,
        visualRegion: FocusEvidenceRegion,
    ) -> (adjustment: Float, belowAFPenalty: Float) {
        let ring = min(max(ringDetailScore, 0), 1)
        let compact = min(max(compactDetailScore, 0), 1)
        let linear = min(max(linearEdgePenalty, 0), 1)
        let belowAFPenalty: Float
        if visualRegion.isAFAnchored, let afPoint {
            let belowAFDistance = max(Float(centroid.y - afPoint.y) - 0.025, 0)
            belowAFPenalty = min(belowAFDistance / 0.15, 1) * 0.18
        } else {
            belowAFPenalty = 0
        }
        return (
            adjustment: ring * 0.10 + compact * 0.08 - linear * 0.10 - belowAFPenalty,
            belowAFPenalty: belowAFPenalty,
        )
    }

    nonisolated static func focusEvidenceDiagnostics(
        from evidence: FocusEvidence?,
        visualRegion: FocusEvidenceRegion,
        selectedPatches: [FocusPatchRanking],
        rankings: [FocusPatchRanking],
        overlayStyle: FocusEvidenceOverlayStyle,
        afPoint: CGPoint?,
    ) -> FocusEvidence {
        var result = evidence ?? FocusEvidence(
            winningRegion: visualRegion,
            globalScore: nil,
            saliencyScore: nil,
            afPointScore: nil,
        )
        let visualizedRect = selectedPatches.map(\.normalizedRect).reduce(nil as CGRect?) { partial, rect in
            partial.map { $0.union(rect) } ?? rect
        }
        let centroid = visualizedRect.map { CGPoint(x: $0.midX, y: $0.midY) }
        let afDistance = centroid.flatMap { center in afPoint.map { normalizedDistance(from: center, to: $0) } }
        let sortedRankings = rankings.sorted { $0.compositeScore > $1.compositeScore }
        let dominance: Float? = if let first = sortedRankings.first?.compositeScore {
            first / max(sortedRankings.dropFirst().first?.compositeScore ?? first, 1e-6)
        } else {
            nil
        }
        let confidence = focusEvidenceConfidence(
            visualRegion: visualRegion,
            patches: selectedPatches,
            afDistance: afDistance,
            dominance: dominance,
        )

        result.effectiveVisualThreshold = nil
        result.maskCoverage = selectedPatches.map(\.coverage).max()
        result.relaxedForVisibility = false
        result.visualizedRegion = visualRegion
        result.visualizedRect = visualizedRect
        result.visualizedCentroid = centroid
        result.afDistanceFromCentroid = afDistance
        result.patchRankings = sortedRankings
        result.overlayStyle = overlayStyle
        result.focusEvidenceConfidence = confidence.value
        result.focusEvidenceConfidenceReason = confidence.reason
        result.spatialAlignmentScore = afDistance.map { max(0, 1 - $0 / 0.05) }
        result.localPatchDominance = dominance
        result.silhouettePenaltyApplied = selectedPatches.contains { $0.silhouetteFraction > 0.12 }
        return result
    }

    nonisolated static func focusEvidenceConfidence(
        visualRegion: FocusEvidenceRegion,
        patches: [FocusPatchRanking],
        afDistance: Float?,
        dominance: Float?,
    ) -> (value: FocusEvidenceConfidence, reason: String) {
        guard let best = patches.first, best.compositeScore > 0 else {
            return (.low, "No viable local focus patch")
        }
        if visualRegion.isAFAnchored, let afDistance {
            if afDistance <= 0.05 {
                return (.high, "AF-local patch is spatially aligned")
            }
            return (.low, "AF-local patch is more than 5% from the AF marker")
        }
        if visualRegion == .global {
            return best.compositeScore >= 0.10
                ? (.medium, "Detail is measurable but global-only")
                : (.low, "Global detail is weak")
        }
        if best.silhouetteFraction < 0.20, (dominance ?? 1) >= 1.08 {
            return (.high, "Interior subject patch clearly dominates")
        }
        return (.medium, "Subject detail is usable but not strongly localized")
    }

    private nonisolated static func heatPatch(
        for normalizedRect: CGRect,
        extent: CGRect,
        style: FocusEvidenceOverlayStyle,
    ) -> CIImage? {
        let rect = CGRect(
            x: extent.minX + normalizedRect.minX * extent.width,
            y: extent.minY + (1.0 - normalizedRect.maxY) * extent.height,
            width: normalizedRect.width * extent.width,
            height: normalizedRect.height * extent.height,
        ).integral.intersection(extent)
        guard !rect.isEmpty else { return nil }
        let gradient = CIFilter.radialGradient()
        gradient.center = CGPoint(x: rect.midX, y: rect.midY)
        gradient.radius0 = Float(min(rect.width, rect.height) * 0.18)
        gradient.radius1 = Float(min(rect.width, rect.height) * 0.58)
        switch style {
        case .subjectHeat:
            gradient.color0 = CIColor(red: 1.0, green: 0.12, blue: 0.02, alpha: 0.88)
            gradient.color1 = CIColor(red: 1.0, green: 0.42, blue: 0.02, alpha: 0)

        case .globalDetail:
            gradient.color0 = CIColor(red: 0.82, green: 0.52, blue: 0.18, alpha: 0.42)
            gradient.color1 = CIColor(red: 0.70, green: 0.48, blue: 0.20, alpha: 0)
        }
        return gradient.outputImage?.cropped(to: rect).composited(over: CIImage(color: .clear).cropped(to: extent))
    }

    private nonisolated static func normalizedRect(_ rect: CGRect, in extent: CGRect) -> CGRect {
        CGRect(
            x: (rect.minX - extent.minX) / extent.width,
            y: 1.0 - (rect.maxY - extent.minY) / extent.height,
            width: rect.width / extent.width,
            height: rect.height / extent.height,
        )
    }

    private nonisolated static func normalizedDistance(from lhs: CGPoint, to rhs: CGPoint) -> Float {
        Float(hypot(lhs.x - rhs.x, lhs.y - rhs.y))
    }

    private nonisolated static func sampleMean(_ samples: [Float]) -> Float {
        guard !samples.isEmpty else { return 0 }
        return samples.reduce(0, +) / Float(samples.count)
    }

    private nonisolated static func overlapRatio(_ lhs: CGRect, _ rhs: CGRect) -> CGFloat {
        let intersection = lhs.intersection(rhs)
        guard !intersection.isNull, !intersection.isEmpty else { return 0 }
        return (intersection.width * intersection.height) / min(lhs.width * lhs.height, rhs.width * rhs.height)
    }

    private struct PatchSampleGrid {
        let samples: [Float]
        let width: Int
        let height: Int
    }

    private struct PatchShapeEvidence {
        let ringDetailScore: Float
        let compactDetailScore: Float
        let linearEdgePenalty: Float
    }

    private nonisolated static func patchShapeEvidence(
        samples: [Float],
        width: Int,
        height: Int,
    ) -> PatchShapeEvidence {
        guard width > 2, height > 2, samples.count == width * height else {
            return PatchShapeEvidence(ringDetailScore: 0, compactDetailScore: 0, linearEdgePenalty: 0)
        }

        var centerSum: Float = 0
        var centerCount = 0
        var ringSum: Float = 0
        var ringCount = 0
        var outerSum: Float = 0
        var outerCount = 0
        var weightSum: Float = 0
        var weightedX: Float = 0
        var weightedY: Float = 0

        for row in 0 ..< height {
            for col in 0 ..< width {
                let value = max(samples[row * width + col], 0)
                let x = (Float(col) + 0.5) / Float(width) - 0.5
                let y = (Float(row) + 0.5) / Float(height) - 0.5
                let radius = hypot(x, y)
                switch radius {
                case ..<0.16:
                    centerSum += value
                    centerCount += 1

                case ..<0.34:
                    ringSum += value
                    ringCount += 1

                default:
                    outerSum += value
                    outerCount += 1
                }
                weightSum += value
                weightedX += value * x
                weightedY += value * y
            }
        }

        guard weightSum > 1e-6 else {
            return PatchShapeEvidence(ringDetailScore: 0, compactDetailScore: 0, linearEdgePenalty: 0)
        }

        let centerMean = centerSum / Float(max(centerCount, 1))
        let ringMean = ringSum / Float(max(ringCount, 1))
        let outerMean = outerSum / Float(max(outerCount, 1))
        let ringDetail = min(max(ringMean / max(ringMean + outerMean, 1e-6), 0), 1)
        let compactDetail = min(max((centerMean + ringMean) / max(centerMean + ringMean + outerMean, 1e-6), 0), 1)

        let meanX = weightedX / weightSum
        let meanY = weightedY / weightSum
        var covarianceXX: Float = 0
        var covarianceYY: Float = 0
        var covarianceXY: Float = 0
        for row in 0 ..< height {
            for col in 0 ..< width {
                let value = max(samples[row * width + col], 0)
                let x = (Float(col) + 0.5) / Float(width) - 0.5 - meanX
                let y = (Float(row) + 0.5) / Float(height) - 0.5 - meanY
                covarianceXX += value * x * x
                covarianceYY += value * y * y
                covarianceXY += value * x * y
            }
        }
        covarianceXX /= weightSum
        covarianceYY /= weightSum
        covarianceXY /= weightSum
        let trace = covarianceXX + covarianceYY
        let discriminant = sqrt(max((covarianceXX - covarianceYY) * (covarianceXX - covarianceYY) + 4 * covarianceXY * covarianceXY, 0))
        let linearPenalty = trace > 1e-6 ? min(max(discriminant / trace, 0), 1) : 0
        return PatchShapeEvidence(
            ringDetailScore: ringDetail,
            compactDetailScore: compactDetail,
            linearEdgePenalty: linearPenalty,
        )
    }

    private nonisolated static func redSamples(in rect: CGRect, from image: CIImage, context: CIContext) -> [Float] {
        redSampleGrid(in: rect, from: image, context: context).samples
    }

    private nonisolated static func redSampleGrid(in rect: CGRect, from image: CIImage, context: CIContext) -> PatchSampleGrid {
        let bounds = rect.integral.intersection(image.extent)
        guard !bounds.isNull, !bounds.isEmpty else { return PatchSampleGrid(samples: [], width: 0, height: 0) }

        let width = Int(bounds.width)
        let height = Int(bounds.height)
        guard width > 0, height > 0 else { return PatchSampleGrid(samples: [], width: 0, height: 0) }

        var rgba = [Float](repeating: 0, count: width * height * 4)
        context.render(
            image,
            toBitmap: &rgba,
            rowBytes: width * 16,
            bounds: bounds,
            format: .RGBAf,
            colorSpace: nil,
        )
        let samples = stride(from: 0, to: rgba.count, by: 4).map { idx in
            let value = rgba[idx]
            return value.isFinite ? value : 0
        }
        return PatchSampleGrid(samples: samples, width: width, height: height)
    }

    private nonisolated static func centerWeightedLaplacian(
        _ image: CIImage,
        center: CGPoint,
        rect: CGRect,
        extent: CGRect,
    ) -> CIImage? {
        let outerRadius = max(min(rect.width, rect.height) * 0.52, 1)
        let innerRadius = max(outerRadius * 0.18, 1)
        let radial = CIFilter.radialGradient()
        radial.center = center
        radial.radius0 = Float(innerRadius)
        radial.radius1 = Float(outerRadius)
        radial.color0 = CIColor(red: 1, green: 1, blue: 1, alpha: 1)
        radial.color1 = CIColor(red: 0, green: 0, blue: 0, alpha: 1)
        guard let mask = radial.outputImage?.cropped(to: extent),
              let multiply = CIFilter(name: "CIMultiplyCompositing")
        else { return nil }
        multiply.setValue(mask, forKey: kCIInputImageKey)
        multiply.setValue(image, forKey: kCIInputBackgroundImageKey)
        return multiply.outputImage?.cropped(to: extent)
    }

    private nonisolated static func maximumComposite(_ image: CIImage, over background: CIImage) -> CIImage {
        if let maxFilter = CIFilter(name: "CIMaximumCompositing") {
            maxFilter.setValue(image, forKey: kCIInputImageKey)
            maxFilter.setValue(background, forKey: kCIInputBackgroundImageKey)
            return maxFilter.outputImage ?? image.composited(over: background)
        }
        return image.composited(over: background)
    }
}
