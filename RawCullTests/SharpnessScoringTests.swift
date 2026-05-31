//
//  SharpnessScoringTests.swift
//  RawCullTests
//

import CoreGraphics
import Foundation
@testable import RawCull
import Testing

struct SharpnessScoringTests {
    /// Regression test: with exactly 2 scores the p90 index formula `Int(1 * 0.90) = 0`
    /// used to return the *minimum* score as the anchor, making both images display as 100.
    /// After the fix, small sets (< 10) use the observed maximum instead.
    @Test(.tags(.smoke))
    @MainActor
    func `max score small set uses maximum not minimum`() {
        let model = SharpnessScoringModel()
        // Inject two scores that mirror the failing real-world case.
        let sharpID = UUID()
        let softID = UUID()
        model.scores = [sharpID: 0.1834, softID: 0.1676]

        let max = model.maxScore
        #expect(max == 0.1834, "maxScore should be the observed maximum for N=2, not the minimum")

        // The soft image normalised score must be strictly below 100.
        let softNormalised = Int((0.1676 / max) * 100)
        #expect(softNormalised < 100, "Soft (out-of-focus) image must not score 100 when a sharper image exists")
    }

    /// Regression test: a single file scoring exactly 0.0 must not produce maxScore == 0.0,
    /// which would cause NaN/Inf in consumers that compute score / maxScore.
    @Test(.tags(.smoke))
    @MainActor
    func `max score single zero score has 1e-6 floor`() {
        let model = SharpnessScoringModel()
        model.scores = [UUID(): 0.0]
        #expect(model.maxScore >= 1e-6, "maxScore must never be 0.0 — consumers divide by it")
    }

    /// Sanity check: with ≥ 10 scores the p90 path is still used (index > 0).
    @Test(.tags(.smoke))
    @MainActor
    func `max score large set uses P 90`() {
        let model = SharpnessScoringModel()
        // 10 evenly-spaced scores from 0.10 to 1.00.
        model.scores = Dictionary(uniqueKeysWithValues: (1 ... 10).map { i in
            (UUID(), Float(i) * 0.10)
        })
        // p90 for 10 sorted values: k = Int(9 * 0.90) = 8 → sorted[8] = 0.90
        #expect(abs(model.maxScore - 0.90) < 0.001,
                "p90 anchor for 10 evenly-spaced scores should be 0.90")
    }

    @Test(.tags(.smoke))
    func `sharpness label maps threshold boundaries`() {
        #expect(SharpnessLabel(score: 0.85, maxScore: 1.0) == .sharp)
        #expect(SharpnessLabel(score: 0.65, maxScore: 1.0) == .good)
        #expect(SharpnessLabel(score: 0.35, maxScore: 1.0) == .check)
        #expect(SharpnessLabel(score: 0.349, maxScore: 1.0) == .soft)
    }

    @Test(.tags(.smoke))
    func `sharpness label clamps and handles invalid denominator`() {
        #expect(SharpnessLabel(score: 1.4, maxScore: 1.0) == .sharp)
        #expect(SharpnessLabel(score: 0.5, maxScore: 0.0) == .soft)
        #expect(SharpnessLabel(score: 0.5, maxScore: .nan) == .soft)
    }

    @Test(.tags(.smoke))
    @MainActor
    func `auto photo type preserves current focus config`() {
        let model = SharpnessScoringModel()
        model.photoType = .auto

        #expect(model.effectiveFocusConfig == model.focusMaskModel.config)
        #expect(model.focusMaskModel.config == .birdsInFlight)
    }

    @Test(.tags(.smoke))
    @MainActor
    func `photo type presets map to expected scoring emphasis`() {
        let base = FocusDetectorConfig.birdsInFlight
        let wildlife = SharpnessPhotoType.birdsWildlife.applying(to: base)
        let portrait = SharpnessPhotoType.portrait.applying(to: base)
        let landscape = SharpnessPhotoType.landscape.applying(to: base)
        let action = SharpnessPhotoType.generalAction.applying(to: base)

        #expect(wildlife.afRegionRadius == 0.06)
        #expect(wildlife.explicitSalientWeightOverride == 0.85)
        #expect(wildlife.subjectSizeFactor == 0.05)
        #expect(wildlife.isolateMaskToSubject)

        #expect(portrait.explicitSalientWeightOverride == 0.80)
        #expect(portrait.silhouettePenaltyStrength < wildlife.silhouettePenaltyStrength)
        #expect(portrait.afRegionRadius > wildlife.afRegionRadius)
        #expect(portrait.isolateMaskToSubject)

        #expect(landscape.explicitSalientWeightOverride == 0.35)
        #expect(landscape.subjectSizeFactor == 0.0)
        #expect(landscape.afRegionRadius == 0.0)
        #expect(!landscape.isolateMaskToSubject)

        #expect(action.explicitSalientWeightOverride == 0.65)
        #expect(action.afRegionRadius > wildlife.afRegionRadius)
        #expect(action.afRegionRadius < portrait.afRegionRadius)
        #expect(action.isolateMaskToSubject)
    }

    @Test(.tags(.smoke))
    @MainActor
    func `scoring quality maps to compute cost and precision config`() {
        let model = SharpnessScoringModel()
        model.thumbnailMaxPixelSize = 512

        model.scoringQuality = .fast
        #expect(model.effectiveThumbnailMaxPixelSize == 512)
        #expect(model.effectiveFocusConfig.fineDetailBlendWeight == 0)

        model.scoringQuality = .balanced
        #expect(model.effectiveThumbnailMaxPixelSize == 768)
        #expect(model.effectiveFocusConfig.fineDetailBlendWeight == 0.25)

        model.scoringQuality = .highPrecision
        model.thumbnailMaxPixelSize = 0
        #expect(model.effectiveThumbnailMaxPixelSize == 0)
        #expect(model.effectiveFocusConfig.fineDetailBlendWeight == 0.45)
        #expect(model.effectiveFocusConfig.enableSubjectClassification)

        model.thumbnailMaxPixelSize = 1536
        #expect(model.effectiveThumbnailMaxPixelSize == 1536)
    }

    @Test(.tags(.smoke))
    @MainActor
    func `RAW demosaic scoring source caps concurrency and keeps embedded default`() {
        let model = SharpnessScoringModel()

        #expect(model.scoringSource == .embeddedPreview)
        #expect(model.effectiveMaxConcurrentScoringTasks == model.scoringQuality.maxConcurrentScoringTasks)

        model.scoringSource = .rawDemosaic
        model.scoringQuality = .highPrecision

        #expect(model.effectiveMaxConcurrentScoringTasks == 2)
    }

    @Test(.tags(.threadSafety), .timeLimit(.minutes(1)))
    @MainActor
    func `concurrent scoreFiles call awaits in flight scoring`() async throws {
        let gate = SharpnessScoringGate()
        let completion = SharpnessScoringCompletionProbe()
        let model = SharpnessScoringModel { _, _, _, _ in
            await gate.markStarted()
            await gate.waitUntilReleased()
            return (
                score: 0.75,
                saliency: SaliencyInfo(subjectLabel: "bird", subjectConfidence: 0.8),
                breakdown: SharpnessBreakdown(
                    finalScore: 0.75,
                    globalScore: 0.65,
                    subjectScore: 0.75,
                    afPointScore: 0.80,
                    blurGateSigma: 0.03,
                    subjectLabel: "bird",
                    subjectConfidence: 0.8,
                    focusFailureKind: .none,
                ),
            )
        }
        let files = [makeSharpnessTestFile()]

        let first = Task { await model.scoreFiles(files) }
        try await gate.waitForStartedCount(1)

        let second = Task {
            await model.scoreFiles(files)
            await completion.markCompleted(
                sortBySharpness: model.sortBySharpness,
                scoringTotal: model.scoringTotal,
            )
        }

        try await Task.sleep(for: .milliseconds(50))
        #expect(await completion.isCompleted == false)

        await gate.release()
        await first.value
        await second.value

        #expect(await completion.isCompleted)
        #expect(await completion.completedAfterSort)
        #expect(await completion.completedAfterProgressReset)
        #expect(model.scores[files[0].id] == 0.75)
        #expect(model.saliencyInfo[files[0].id]?.subjectLabel == "bird")
        #expect(model.breakdowns[files[0].id]?.subjectScore == 0.75)
        #expect(model.sortBySharpness)
        #expect(model.scoringProgress == 0)
        #expect(model.scoringTotal == 0)
    }
}

// MARK: - Numeric helper unit tests

private func makeSharpnessTestFile() -> FileItem {
    let url = URL(fileURLWithPath: NSTemporaryDirectory())
        .appendingPathComponent("rawcull-sharpness-\(UUID().uuidString)")
        .appendingPathExtension("arw")

    return FileItem(
        url: url,
        name: url.lastPathComponent,
        size: 1,
        dateModified: Date(),
        exifData: nil,
        afFocusNormalized: nil,
    )
}

private actor SharpnessScoringGate {
    private var startedCount = 0
    private var released = false
    private var startedWaiters: [(Int, CheckedContinuation<Void, Never>)] = []
    private var releaseWaiters: [CheckedContinuation<Void, Never>] = []

    func markStarted() {
        startedCount += 1
        var remainingWaiters: [(Int, CheckedContinuation<Void, Never>)] = []
        for waiter in startedWaiters {
            if startedCount >= waiter.0 {
                waiter.1.resume()
            } else {
                remainingWaiters.append(waiter)
            }
        }
        startedWaiters = remainingWaiters
    }

    func waitForStartedCount(_ count: Int) async throws {
        if startedCount >= count { return }
        await withCheckedContinuation { continuation in
            startedWaiters.append((count, continuation))
        }
    }

    func waitUntilReleased() async {
        if released { return }
        await withCheckedContinuation { continuation in
            releaseWaiters.append(continuation)
        }
    }

    func release() {
        released = true
        let waiters = releaseWaiters
        releaseWaiters.removeAll()
        waiters.forEach { $0.resume() }
    }
}

private actor SharpnessScoringCompletionProbe {
    private var completed = false
    private var observedSortBySharpness = false
    private var observedScoringTotal = Int.max

    var isCompleted: Bool {
        completed
    }

    var completedAfterSort: Bool {
        observedSortBySharpness
    }

    var completedAfterProgressReset: Bool {
        observedScoringTotal == 0
    }

    func markCompleted(sortBySharpness: Bool, scoringTotal: Int) {
        completed = true
        observedSortBySharpness = sortBySharpness
        observedScoringTotal = scoringTotal
    }
}

@Suite("FocusMaskModel numeric helpers")
struct FocusNumericHelperTests {
    // MARK: robustTailScore

    @Test(.tags(.smoke))
    func `robust tail score empty returns nil`() {
        #expect(FocusMaskModel.robustTailScore([]) == nil)
    }

    @Test(.tags(.smoke))
    func `robust tail score uniform returns zero`() throws {
        // All values identical → p20 == p90 == p97, so spread is zero.
        let samples = [Float](repeating: 0.5, count: 1000)
        let score = FocusMaskModel.robustTailScore(samples)
        #expect(score != nil)
        #expect(try #require(score) < 1e-5)
    }

    @Test(.tags(.smoke))
    func `robust tail score dense edges full density factor`() throws {
        // Linearly spaced 0…1: p20=0.20, p90=0.90, p97=0.97.
        // Band (p90…p97) contains 7% of values → density 0.07 > minDensity 0.06 → factor = 1.0.
        let n = 1000
        let samples = (0 ..< n).map { Float($0) / Float(n - 1) }
        let score = FocusMaskModel.robustTailScore(samples)
        #expect(score != nil)
        // Band mean of values in [0.90, 0.97] minus p20 (≈0.20) should be ≈ 0.735 * 1.0
        #expect(try #require(score) > 0.70)
        #expect(try #require(score) < 0.80)
    }

    @Test(.tags(.smoke))
    func `robust tail score sparse edges scores low`() throws {
        // 94.5% zeros + 5.5% ones: p90 = 0.0, so the band [0.0, 1.0] captures all
        // 1000 values. bandMean = 55 / 1000 = 0.055 → low score for sparse-edge image.
        let n = 1000
        let highCount = 55
        var samples = [Float](repeating: 0.0, count: n - highCount)
        samples += [Float](repeating: 1.0, count: highCount)
        let score = FocusMaskModel.robustTailScore(samples)
        #expect(score != nil)
        #expect(try #require(score) < 0.10)
        #expect(try #require(score) > 0.01)
    }

    @Test(.tags(.smoke))
    func `robust tail score dense edges scores higher than sparse`() throws {
        // A uniform 0…1 distribution (dense edges) should score higher than
        // the near-zero distribution above (sparse edges).
        let n = 1000
        let dense = (0 ..< n).map { Float($0) / Float(n - 1) }
        var sparse = [Float](repeating: 0.0, count: 950)
        sparse += [Float](repeating: 1.0, count: 50)
        let denseScore = FocusMaskModel.robustTailScore(dense)
        let sparseScore = FocusMaskModel.robustTailScore(sparse)
        #expect(denseScore != nil)
        #expect(sparseScore != nil)
        #expect(try #require(denseScore) > sparseScore!)
    }

    // MARK: microContrast

    @Test(.tags(.smoke))
    func `micro contrast empty returns zero`() {
        #expect(FocusMaskModel.microContrast([]) == 0.0)
    }

    @Test(.tags(.smoke))
    func `micro contrast uniform returns zero`() {
        let samples = [Float](repeating: 0.5, count: 500)
        #expect(FocusMaskModel.microContrast(samples) < 1e-5)
    }

    @Test(.tags(.smoke))
    func `micro contrast alternating known variance`() {
        // Values alternating 0 and 1: mean = 0.5, variance = 0.25, std-dev = 0.5.
        let samples: [Float] = (0 ..< 1000).map { $0 % 2 == 0 ? 0.0 : 1.0 }
        let result = FocusMaskModel.microContrast(samples)
        #expect(abs(result - 0.5) < 0.01)
    }

    @Test(.tags(.smoke))
    func `micro contrast ignores non finite`() {
        // Mix of valid values and NaN/Inf — should not crash, should equal uniform result.
        var samples = [Float](repeating: 0.5, count: 100)
        samples.append(Float.nan)
        samples.append(Float.infinity)
        #expect(FocusMaskModel.microContrast(samples) < 1e-5)
    }

    // MARK: focus mask region selection

    @Test(.tags(.smoke))
    func `focus mask region selection uses saliency only when AF is absent`() {
        let extent = CGRect(x: 0, y: 0, width: 1000, height: 500)
        let selection = FocusMaskEngine.focusMaskRegionSelection(
            extent: extent,
            salientRegion: CGRect(x: 0.20, y: 0.30, width: 0.40, height: 0.20),
            afPoint: nil,
            afRegionRadius: 0.06,
        )

        #expect(selection.source == .saliency)
        #expect(selection.saliencyRect == CGRect(x: 200, y: 150, width: 400, height: 100))
        #expect(selection.afRect == nil)
    }

    @Test(.tags(.smoke))
    func `focus mask region selection uses AF only when saliency is absent`() {
        let extent = CGRect(x: 0, y: 0, width: 1000, height: 500)
        let selection = FocusMaskEngine.focusMaskRegionSelection(
            extent: extent,
            salientRegion: nil,
            afPoint: CGPoint(x: 0.30, y: 0.40),
            afRegionRadius: 0.05,
        )

        #expect(selection.source == .afPoint)
        #expect(selection.saliencyRect == nil)
        #expect(selection.afRect?.contains(CGPoint(x: 300, y: 300)) == true)
        #expect(abs((selection.afRect?.width ?? 0) - 100) <= 2)
        #expect(abs((selection.afRect?.height ?? 0) - 50) <= 2)
    }

    @Test(.tags(.smoke))
    func `focus mask region selection keeps AF when saliency misses focus point`() {
        let extent = CGRect(x: 0, y: 0, width: 1000, height: 500)
        let selection = FocusMaskEngine.focusMaskRegionSelection(
            extent: extent,
            salientRegion: CGRect(x: 0.65, y: 0.20, width: 0.20, height: 0.20),
            afPoint: CGPoint(x: 0.25, y: 0.65),
            afRegionRadius: 0.04,
        )

        #expect(selection.source == .saliencyAndAF)
        #expect(selection.saliencyRect == CGRect(x: 650, y: 100, width: 200, height: 100))
        #expect(selection.afRect == CGRect(x: 210, y: 155, width: 80, height: 40))
    }

    // MARK: adaptive visual threshold

    @Test(.tags(.smoke))
    func `adaptive AF threshold keeps low contrast local detail reachable`() {
        let samples = [Float](repeating: 0.04, count: 900) + [Float](repeating: 0.18, count: 100)
        let threshold = FocusMaskEngine.adaptiveVisualThreshold(
            samples,
            fallback: 0.46,
            percentile: 0.82,
            floorMultiplier: 0.32,
            capAtFallback: true,
        )

        #expect(threshold < 0.18)
        #expect(threshold >= 0.14)
    }

    @Test(.tags(.smoke))
    func `adaptive saliency threshold rises for broad high contrast edges`() {
        let samples = [Float](repeating: 0.12, count: 850) + [Float](repeating: 0.82, count: 150)
        let threshold = FocusMaskEngine.adaptiveVisualThreshold(
            samples,
            fallback: 0.46,
            percentile: 0.95,
            floorMultiplier: 1.0,
            capAtFallback: false,
        )

        #expect(threshold > 0.46)
    }

    @Test(.tags(.smoke))
    func `adaptive AF threshold is capped so strong body edges do not hide AF detail`() {
        let samples = [Float](repeating: 0.20, count: 500) + [Float](repeating: 0.90, count: 500)
        let threshold = FocusMaskEngine.adaptiveVisualThreshold(
            samples,
            fallback: 0.46,
            percentile: 0.82,
            floorMultiplier: 0.32,
            capAtFallback: true,
        )

        #expect(threshold == 0.46)
    }

    // MARK: focus evidence selection and visibility

    @Test(.tags(.smoke))
    func `focus evidence selection prefers AF when strongest`() {
        let region = FocusMaskEngine.focusEvidenceRegion(
            globalScore: 0.24,
            saliencyScore: 0.31,
            afPointScore: 0.42,
            afRegionRadius: 0.06,
        )

        #expect(region == .afPoint)
    }

    @Test(.tags(.smoke))
    func `focus evidence selection prefers AF center when eye patch is strongest`() {
        let region = FocusMaskEngine.focusEvidenceRegion(
            globalScore: 0.28,
            saliencyScore: 0.34,
            afPointScore: 0.30,
            afCenterScore: 0.36,
            afNeighborhoodScore: 0.32,
            afRegionRadius: 0.06,
        )

        #expect(region == .afCenter)
    }

    @Test(.tags(.smoke))
    func `focus evidence selection uses AF neighborhood when center is weak`() {
        let region = FocusMaskEngine.focusEvidenceRegion(
            globalScore: 0.28,
            saliencyScore: 0.35,
            afPointScore: 0.31,
            afCenterScore: 0.12,
            afNeighborhoodScore: 0.33,
            afRegionRadius: 0.06,
        )

        #expect(region == .afNeighborhood)
    }

    @Test(.tags(.smoke))
    func `focus evidence selection keeps wildlife AF when nearly strongest`() {
        let region = FocusMaskEngine.focusEvidenceRegion(
            globalScore: 0.20,
            saliencyScore: 0.40,
            afPointScore: 0.35,
            afRegionRadius: 0.06,
        )

        #expect(region == .afPoint)
    }

    @Test(.tags(.smoke))
    func `focus evidence selection uses saliency when AF is absent`() {
        let region = FocusMaskEngine.focusEvidenceRegion(
            globalScore: 0.22,
            saliencyScore: 0.38,
            afPointScore: nil,
            afRegionRadius: 0.06,
        )

        #expect(region == .saliency)
    }

    @Test(.tags(.smoke))
    func `focus evidence selection keeps saliency when AF local scores are weak`() {
        let region = FocusMaskEngine.focusEvidenceRegion(
            globalScore: 0.24,
            saliencyScore: 0.42,
            afPointScore: 0.22,
            afCenterScore: 0.08,
            afNeighborhoodScore: 0.16,
            afRegionRadius: 0.06,
        )

        #expect(region == .saliency)
    }

    @Test(.tags(.smoke))
    func `focus evidence selection falls back to global without subject evidence`() {
        let region = FocusMaskEngine.focusEvidenceRegion(
            globalScore: 0.30,
            saliencyScore: nil,
            afPointScore: nil,
            afRegionRadius: 0.06,
        )

        #expect(region == .global)
    }

    @Test(.tags(.smoke))
    func `AF local rect stays constrained around focus point`() throws {
        let extent = CGRect(x: 0, y: 0, width: 1000, height: 500)
        let centerUnit = try #require(FocusMaskEngine.afUnitRegion(
            afPoint: CGPoint(x: 0.30, y: 0.40),
            radius: 0.025,
        ))
        let neighborhoodUnit = try #require(FocusMaskEngine.afUnitRegion(
            afPoint: CGPoint(x: 0.30, y: 0.40),
            radius: 0.075,
        ))
        let center = try #require(FocusMaskEngine.pixelRect(from: centerUnit, in: extent))
        let neighborhood = try #require(FocusMaskEngine.pixelRect(from: neighborhoodUnit, in: extent))

        #expect(center.width < neighborhood.width)
        #expect(center.height < neighborhood.height)
        #expect(neighborhood.contains(center))
        #expect(center.contains(CGPoint(x: 300, y: 300)))
    }

    @Test(.tags(.smoke))
    func `AF pixel center matches overlay normalized coordinates`() throws {
        let extent = CGRect(x: 0, y: 0, width: 1000, height: 500)
        let center = try #require(FocusMaskEngine.afPixelCenter(
            afPoint: CGPoint(x: 0.30, y: 0.40),
            in: extent,
        ))

        #expect(center == CGPoint(x: 300, y: 300))
    }

    // MARK: - Scale invariance of robustTailScore

    /// Fix verification: p90–p97 band mean is linearly proportional to a uniform
    /// positive scaling of inputs. Guards against regressions that would make the
    /// score absolute-scale dependent without calibration.
    @Test(.tags(.smoke))
    func `robust tail score is scale proportional`() throws {
        let n = 1000
        let base = (0 ..< n).map { Float($0) / Float(n - 1) }
        let scaled = base.map { $0 * 10 }
        let a = try #require(FocusMaskModel.robustTailScore(base))
        let b = try #require(FocusMaskModel.robustTailScore(scaled))
        // Allow 1% slack for percentile-index rounding noise.
        #expect(abs(b / a - 10) < 0.1)
    }

    // MARK: - Failure classification

    @Test(.tags(.smoke))
    func `focus failure classifier flags motion blur when all regions are weak`() {
        let result = FocusMaskModel.classifyFocusFailure(
            globalScore: 0.03,
            subjectScore: 0.04,
            afPointScore: 0.05,
            blurGateSigma: 0.004,
        )
        #expect(result == .motionBlur)
    }

    @Test(.tags(.smoke))
    func `focus failure classifier flags missed focus when subject trails frame`() {
        let result = FocusMaskModel.classifyFocusFailure(
            globalScore: 0.30,
            subjectScore: 0.10,
            afPointScore: 0.11,
            blurGateSigma: 0.03,
        )
        #expect(result == .missedFocus)
    }

    @Test(.tags(.smoke))
    func `focus failure classifier stays neutral for strong subject`() {
        let result = FocusMaskModel.classifyFocusFailure(
            globalScore: 0.24,
            subjectScore: 0.22,
            afPointScore: 0.26,
            blurGateSigma: 0.03,
        )
        #expect(result == .none)
    }
}

@Suite("Focus evidence patch overlay")
struct FocusEvidencePatchOverlayTests {
    @Test(.tags(.smoke))
    func `AF centered patch wins over slightly stronger distant patch`() throws {
        let near = patch(x: 0.47, y: 0.47, score: 1.0, distance: 0.01, containsAF: true)
        let distant = patch(x: 0.47, y: 0.62, score: 1.14, distance: 0.16)

        let selected = FocusMaskEngine.selectEvidencePatches(from: [distant, near], visualRegion: .afCenter)

        #expect(try #require(selected.first) == near)
    }

    @Test(.tags(.smoke))
    func `AF distant patch wins when detail exceeds override`() throws {
        let near = patch(x: 0.47, y: 0.47, score: 1.0, distance: 0.01, containsAF: true)
        let distant = patch(x: 0.47, y: 0.62, score: 1.16, distance: 0.16)

        let selected = FocusMaskEngine.selectEvidencePatches(from: [distant, near], visualRegion: .afCenter)

        #expect(try #require(selected.first) == distant)
    }

    @Test(.tags(.smoke))
    func `saliency interior patch beats silhouette border`() throws {
        let interior = patch(x: 0.45, y: 0.45, score: 0.72, silhouette: 0.04)
        let border = patch(x: 0.10, y: 0.10, score: 0.58, silhouette: 0.70)

        let selected = FocusMaskEngine.selectEvidencePatches(from: [border, interior], visualRegion: .saliency)

        #expect(try #require(selected.first) == interior)
    }

    @Test(.tags(.smoke))
    func `global evidence uses medium confidence when measurable`() {
        let result = FocusMaskEngine.focusEvidenceConfidence(
            visualRegion: .global,
            patches: [patch(x: 0.45, y: 0.45, score: 0.20)],
            afDistance: nil,
            dominance: 1.2,
        )

        #expect(result.value == .medium)
    }

    @Test(.tags(.smoke))
    func `no viable patch is low confidence`() {
        let result = FocusMaskEngine.focusEvidenceConfidence(
            visualRegion: .afCenter,
            patches: [],
            afDistance: nil,
            dominance: nil,
        )

        #expect(result.value == .low)
    }

    @Test(.tags(.smoke))
    func `diagnostics report visualized patch and AF distance`() throws {
        let selected = patch(x: 0.47, y: 0.47, score: 0.8, distance: 0.0, containsAF: true)
        let evidence = FocusMaskEngine.focusEvidenceDiagnostics(
            from: nil,
            visualRegion: .afCenter,
            selectedPatches: [selected],
            rankings: [selected],
            overlayStyle: .subjectHeat,
            afPoint: CGPoint(x: 0.50, y: 0.50),
        )

        #expect(evidence.visualizedRegion == .afCenter)
        #expect(evidence.visualizedRect == selected.normalizedRect)
        #expect(evidence.visualizedCentroid == CGPoint(x: 0.50, y: 0.50))
        #expect(try #require(evidence.afDistanceFromCentroid) < 0.001)
        #expect(evidence.patchRankings == [selected])
        #expect(evidence.overlayStyle == .subjectHeat)
        #expect(evidence.focusEvidenceConfidence == .high)
    }

    @Test(.tags(.smoke))
    func `eye head heuristic rewards compact ring detail over linear edge`() {
        let eye = FocusMaskEngine.eyeHeadHeuristicAdjustment(
            ringDetailScore: 0.85,
            compactDetailScore: 0.80,
            linearEdgePenalty: 0.10,
            centroid: CGPoint(x: 0.50, y: 0.50),
            afPoint: CGPoint(x: 0.50, y: 0.50),
            visualRegion: .afCenter,
        )
        let beak = FocusMaskEngine.eyeHeadHeuristicAdjustment(
            ringDetailScore: 0.20,
            compactDetailScore: 0.25,
            linearEdgePenalty: 0.90,
            centroid: CGPoint(x: 0.50, y: 0.50),
            afPoint: CGPoint(x: 0.50, y: 0.50),
            visualRegion: .afCenter,
        )

        #expect(eye.adjustment > 0)
        #expect(beak.adjustment < 0)
        #expect(eye.adjustment > beak.adjustment)
    }

    @Test(.tags(.smoke))
    func `AF anchored heuristic penalizes lower patch beyond head window`() {
        let aligned = FocusMaskEngine.eyeHeadHeuristicAdjustment(
            ringDetailScore: 0.50,
            compactDetailScore: 0.50,
            linearEdgePenalty: 0.10,
            centroid: CGPoint(x: 0.50, y: 0.51),
            afPoint: CGPoint(x: 0.50, y: 0.50),
            visualRegion: .afCenter,
        )
        let lower = FocusMaskEngine.eyeHeadHeuristicAdjustment(
            ringDetailScore: 0.50,
            compactDetailScore: 0.50,
            linearEdgePenalty: 0.10,
            centroid: CGPoint(x: 0.50, y: 0.65),
            afPoint: CGPoint(x: 0.50, y: 0.50),
            visualRegion: .afCenter,
        )

        #expect(aligned.belowAFPenalty == 0)
        #expect(lower.belowAFPenalty > 0)
        #expect(lower.adjustment < aligned.adjustment)
    }

    @Test(.tags(.smoke))
    func `saliency heuristic does not invent below AF penalty`() {
        let result = FocusMaskEngine.eyeHeadHeuristicAdjustment(
            ringDetailScore: 0.50,
            compactDetailScore: 0.50,
            linearEdgePenalty: 0.10,
            centroid: CGPoint(x: 0.50, y: 0.75),
            afPoint: CGPoint(x: 0.50, y: 0.50),
            visualRegion: .saliency,
        )

        #expect(result.belowAFPenalty == 0)
    }

    private func patch(
        x: CGFloat,
        y: CGFloat,
        score: Float,
        distance: Float? = nil,
        silhouette: Float = 0,
        containsAF: Bool = false,
    ) -> FocusPatchRanking {
        FocusPatchRanking(
            normalizedRect: CGRect(x: x, y: y, width: 0.06, height: 0.06),
            robustTailScore: score,
            microContrast: 0.2,
            coverage: 0.15,
            distanceToAF: distance,
            silhouetteFraction: silhouette,
            compositeScore: score,
            containsAFPoint: containsAF,
        )
    }
}

// MARK: - Aperture hint

@Suite("FocusDetectorConfig.ApertureHint")
struct ApertureHintTests {
    @Test(.tags(.smoke))
    func `nil aperture maps to mid`() {
        #expect(FocusDetectorConfig.ApertureHint.from(aperture: nil) == .mid)
    }

    @Test(.tags(.smoke))
    func `wide boundary is inclusive at 5 point 6`() {
        #expect(FocusDetectorConfig.ApertureHint.from(aperture: 2.8) == .wide)
        #expect(FocusDetectorConfig.ApertureHint.from(aperture: 4.0) == .wide)
        #expect(FocusDetectorConfig.ApertureHint.from(aperture: 5.6) == .wide)
        #expect(FocusDetectorConfig.ApertureHint.from(aperture: 6.3) == .mid)
    }

    @Test(.tags(.smoke))
    func `landscape boundary is inclusive at f 8`() {
        #expect(FocusDetectorConfig.ApertureHint.from(aperture: 7.1) == .mid)
        #expect(FocusDetectorConfig.ApertureHint.from(aperture: 8.0) == .landscape)
        #expect(FocusDetectorConfig.ApertureHint.from(aperture: 11.0) == .landscape)
        #expect(FocusDetectorConfig.ApertureHint.from(aperture: 22.0) == .landscape)
    }

    @Test(.tags(.smoke))
    func `blur gate span is positive for every hint`() {
        for hint in [FocusDetectorConfig.ApertureHint.wide, .mid, .landscape] {
            #expect(hint.blurGateHigh > hint.blurGateLow,
                    "gate span must be positive so the soft ramp is well-defined")
        }
    }

    @Test(.tags(.smoke))
    func `landscape has widest gate window and lowest threshold`() {
        // Landscape should be the most permissive at the low end so deep-DoF scenes
        // with legitimately low-contrast subjects aren't demoted.
        #expect(FocusDetectorConfig.ApertureHint.landscape.blurGateLow <
            FocusDetectorConfig.ApertureHint.mid.blurGateLow)
        #expect(FocusDetectorConfig.ApertureHint.mid.blurGateLow <
            FocusDetectorConfig.ApertureHint.wide.blurGateLow)
    }

    @Test(.tags(.smoke))
    func `only landscape overrides salient weight and damps blur`() {
        #expect(FocusDetectorConfig.ApertureHint.wide.salientWeightOverride == nil)
        #expect(FocusDetectorConfig.ApertureHint.mid.salientWeightOverride == nil)
        #expect(FocusDetectorConfig.ApertureHint.landscape.salientWeightOverride == 0.55)

        #expect(FocusDetectorConfig.ApertureHint.wide.blurDamp == 1.0)
        #expect(FocusDetectorConfig.ApertureHint.mid.blurDamp == 1.0)
        #expect(FocusDetectorConfig.ApertureHint.landscape.blurDamp == 0.8)
    }
}

// MARK: - ISO scaling piecewise

@Suite("FocusMaskModel.isoScalingFactor")
struct ISOScalingTests {
    @Test(.tags(.smoke))
    func `below 800 is flat at 1 point 0`() {
        #expect(FocusMaskModel.isoScalingFactor(iso: 100) == 1.0)
        #expect(FocusMaskModel.isoScalingFactor(iso: 400) == 1.0)
        #expect(FocusMaskModel.isoScalingFactor(iso: 799) == 1.0)
    }

    @Test(.tags(.smoke))
    func `mid range ramps to 1 point 6 at 3200`() {
        #expect(FocusMaskModel.isoScalingFactor(iso: 800) == 1.0)
        let at2000 = FocusMaskModel.isoScalingFactor(iso: 2000)
        #expect(abs(at2000 - 1.3) < 1e-4, "expected 1.3 at ISO 2000, got \(at2000)")
        let at3200 = FocusMaskModel.isoScalingFactor(iso: 3200)
        #expect(abs(at3200 - 1.6) < 1e-4, "expected 1.6 at ISO 3200, got \(at3200)")
    }

    @Test(.tags(.smoke))
    func `high range caps at 2 point 2`() {
        #expect(FocusMaskModel.isoScalingFactor(iso: 6400) > 1.6)
        #expect(FocusMaskModel.isoScalingFactor(iso: 12800) == 2.2)
        #expect(FocusMaskModel.isoScalingFactor(iso: 51200) == 2.2)
    }

    @Test(.tags(.smoke))
    func `monotonically non decreasing across range`() {
        let iso = [100, 200, 400, 800, 1600, 2000, 3200, 6400, 12800, 25600]
        let factors = iso.map { FocusMaskModel.isoScalingFactor(iso: $0) }
        for i in 1 ..< factors.count {
            #expect(factors[i] >= factors[i - 1], "regression at ISO \(iso[i])")
        }
    }

    @Test(.tags(.smoke))
    func `high ISO is less aggressive than old sqrt formula`() {
        // Regression guard: the previous sqrt(ISO/400) clamped to 3.0 produced 3.0 at
        // ISO 3600+, over-blurring real detail on A1-series bodies. The new curve must
        // stay well under 3.0 at ISO 6400.
        #expect(FocusMaskModel.isoScalingFactor(iso: 6400) < 2.0)
    }
}
