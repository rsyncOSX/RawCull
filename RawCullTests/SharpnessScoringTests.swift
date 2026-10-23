//
//  SharpnessScoringTests.swift
//  RawCullVerifyTests
//

import CoreGraphics
import Foundation
import PhotoAnalysisKit
@testable import RawCull
import RawCullCore
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
    @MainActor
    func `sharpness label maps threshold boundaries`() {
        #expect(SharpnessLabel(score: 0.85, maxScore: 1.0) == .sharp)
        #expect(SharpnessLabel(score: 0.65, maxScore: 1.0) == .good)
        #expect(SharpnessLabel(score: 0.35, maxScore: 1.0) == .check)
        #expect(SharpnessLabel(score: 0.349, maxScore: 1.0) == .soft)
    }

    @Test(.tags(.smoke))
    @MainActor
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
        let wildlife = SharpnessPhotoType.birdsWildlife.packagePreset.applying(to: base)
        let portrait = SharpnessPhotoType.portrait.packagePreset.applying(to: base)
        let landscape = SharpnessPhotoType.landscape.packagePreset.applying(to: base)
        let action = SharpnessPhotoType.generalAction.packagePreset.applying(to: base)

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
        #expect(model.effectiveThumbnailMaxPixelSize == 2048)
        #expect(model.effectiveFocusConfig.fineDetailBlendWeight == 0.45)
        #expect(model.effectiveFocusConfig.enableSubjectClassification)

        model.thumbnailMaxPixelSize = 512
        #expect(model.effectiveThumbnailMaxPixelSize == 1024)

        model.thumbnailMaxPixelSize = 1536
        #expect(model.effectiveThumbnailMaxPixelSize == 1536)
    }

    @Test(.tags(.smoke))
    @MainActor
    func `scoring signature uses package analysis descriptor`() throws {
        let model = SharpnessScoringModel()
        model.photoType = .portrait
        model.scoringQuality = .balanced
        model.scoringSource = .rawDemosaic
        model.thumbnailMaxPixelSize = 1536

        let signature = model.scoringSignature
        let descriptor = try #require(signature.analysisDescriptor)

        #expect(
            descriptor
                == PhotoAnalyzer.sharpnessDescriptor(
                    for: model.effectiveFocusConfig,
                ),
        )
        #expect(signature.scoringSource == .rawDemosaic)
        #expect(signature.thumbnailMaxPixelSize == 1536)
    }

    @Test(.tags(.smoke))
    @MainActor
    func `legacy scoring signature decodes as stale`() throws {
        let legacy = """
        {
          "algorithmVersion": 4,
          "isoScalingPolicyVersion": 1,
          "apertureHintPolicyVersion": 1,
          "scoringPhotoType": "auto",
          "scoringQuality": "fast",
          "scoringSource": "embeddedPreview",
          "thumbnailMaxPixelSize": 512,
          "preBlurRadius": 1.92,
          "borderInsetFraction": 0.04,
          "salientWeight": 0.75,
          "subjectSizeFactor": 0.1,
          "silhouettePenaltyStrength": 0.55,
          "afRegionRadius": 0.12,
          "fineDetailBlendWeight": 0.0,
          "stableScoringEnergyMultiplier": 7.62
        }
        """

        let decoded = try JSONDecoder().decode(
            SharpnessScoringSignature.self,
            from: Data(legacy.utf8),
        )
        let current = SharpnessScoringModel().scoringSignature

        #expect(decoded.analysisDescriptor == nil)
        #expect(decoded.scoringSource == .embeddedPreview)
        #expect(decoded.thumbnailMaxPixelSize == 512)
        #expect(decoded != current)
    }

    @Test(.tags(.smoke))
    func `AF ranking uses center detail without background or saliency fallback`() {
        let breakdown = RawCull.SharpnessBreakdown(
            finalScore: 0.95, globalScore: 1.0, subjectScore: 0.9,
            afPointScore: 0.8, blurGateSigma: 0.03,
            subjectLabel: nil, subjectConfidence: nil, focusFailureKind: .none,
            focusEvidence: FocusEvidence(
                winningRegion: .saliency, afCenterScore: 0.12, afNeighborhoodScore: 0.85,
            ),
        )
        let center = CGPoint(x: 0.5, y: 0.5)
        #expect(SharpnessScoringModel.afPointScore(from: breakdown, normalizedAFPoint: center) == 0.12)
        #expect(SharpnessScoringModel.afPointScore(from: breakdown, normalizedAFPoint: nil) == nil)
        #expect(SharpnessScoringModel.afPointScore(from: breakdown, normalizedAFPoint: CGPoint(x: -0.1, y: 0.5)) == nil)
        #expect(SharpnessScoringModel.afPointScore(from: nil, normalizedAFPoint: center) == nil)
    }

    @Test(.tags(.smoke), arguments: [Float.zero, Float.nan, Float.infinity])
    func `AF ranking treats absent detail and invalid measurements as unknown`(score: Float) {
        let breakdown = RawCull.SharpnessBreakdown(
            finalScore: 0.95, globalScore: 1, subjectScore: 0.9,
            afPointScore: 0.8, blurGateSigma: 0.03,
            subjectLabel: nil, subjectConfidence: nil, focusFailureKind: .none,
            focusEvidence: FocusEvidence(winningRegion: .afCenter, afCenterScore: score),
        )
        #expect(SharpnessScoringModel.afPointScore(
            from: breakdown, normalizedAFPoint: CGPoint(x: 0.5, y: 0.5),
        ) == nil)
    }

    @Test(.tags(.smoke))
    @MainActor
    func `AF sorting preserves ties and places unknown measurements last`() {
        let model = SharpnessScoringModel()
        let files = (0 ..< 5).map { _ in makeSharpnessTestFile() }
        model.scores = [files[0].id: 1.0, files[3].id: 0.01]
        model.afPointScores = [files[1].id: 0.3, files[2].id: 0.3, files[3].id: 0.7]
        #expect(model.sortedByAFPointSharpness(files).map(\.id) == [
            files[3].id, files[1].id, files[2].id, files[0].id, files[4].id,
        ])
    }

    @Test(.tags(.smoke))
    @MainActor
    func `legacy scores cannot enable AF sorting and AF measurements survive hydration`() {
        let model = SharpnessScoringModel()
        let file = makeSharpnessTestFile(afPoint: CGPoint(x: 0.5, y: 0.5))
        model.applyPreloadedScores([file], preloadedScores: [file.id: 0.8], preloadedSaliency: [:])
        #expect(model.scores[file.id] == 0.8)
        #expect(model.afPointScores.isEmpty)
        #expect(!model.sortBySharpness)
        model.applyPreloadedScores(
            [file], preloadedScores: [file.id: 0.8], preloadedSaliency: [:],
            preloadedAFPointScores: [file.id: 0.2, UUID(): 0.9],
        )
        #expect(model.afPointScores == [file.id: 0.2])
        #expect(model.sortBySharpness)
        model.cancelScoring()
        #expect(model.afPointScores.isEmpty)
    }

    @Test(.tags(.smoke))
    @MainActor
    func `batch AF scoring rejects sharp background around a textureless focus point`() async throws {
        let sharpCenter = try #require(makeAFDetailTestImage(sharpCenter: true))
        let sharpBackground = try #require(makeAFDetailTestImage(sharpCenter: false))
        let focused = makeSharpnessTestFile(afPoint: CGPoint(x: 0.5, y: 0.5))
        let background = makeSharpnessTestFile(afPoint: CGPoint(x: 0.5, y: 0.5))
        let noAF = makeSharpnessTestFile()
        let adapter = RawCullPhotoAnalysisAdapter(inputLoaderOverride: { file, _, _ in
            PhotoAnalysisInput(
                image: file.url == background.url ? sharpBackground : sharpCenter,
                iso: file.iso, normalizedAFPoint: file.normalizedAFPoint,
            )
        })
        let model = SharpnessScoringModel(analysisAdapterOverride: adapter)
        await model.scoreFiles([background, noAF, focused])
        #expect(try #require(model.afPointScores[focused.id]) > 0)
        #expect(model.afPointScores[background.id] == nil)
        #expect(model.afPointScores[noAF.id] == nil)
        #expect(model.scores[background.id] != nil)
        #expect(model.sortedByAFPointSharpness([background, noAF, focused]).first?.id == focused.id)
    }

    @Test(.tags(.smoke))
    @MainActor
    func `loading cached burst AF evidence preserves best frame scores`() async throws {
        let image = try #require(makeAFDetailTestImage(sharpCenter: true))
        let focused = makeSharpnessTestFile(afPoint: CGPoint(x: 0.5, y: 0.5))
        let other = makeSharpnessTestFile()
        let adapter = RawCullPhotoAnalysisAdapter(inputLoaderOverride: { file, _, _ in
            PhotoAnalysisInput(image: image, iso: file.iso, normalizedAFPoint: file.normalizedAFPoint)
        })
        let model = SharpnessScoringModel(analysisAdapterOverride: adapter)
        let original: [UUID: Float] = [focused.id: 0.2, other.id: 0.8]
        model.applyPreloadedScores([focused, other], preloadedScores: original, preloadedSaliency: [:])

        await model.loadMissingAFPointScores(for: [focused, other])

        #expect(model.scores == original)
        #expect(model.sortBySharpness == false)
        #expect(try #require(model.afPointScores[focused.id]) > 0)
        #expect(model.afPointScores[other.id] == nil)
        #expect(model.sortedByAFPointSharpness([other, focused]).first?.id == focused.id)
    }

    @Test(.tags(.threadSafety), .timeLimit(.minutes(1)))
    @MainActor
    func `concurrent scoreFiles call awaits in flight scoring`() async throws {
        let gate = SharpnessScoringGate()
        let completion = SharpnessScoringCompletionProbe()
        let image = try #require(makeSharpnessTestImage())
        let adapter = RawCullPhotoAnalysisAdapter(
            inputLoaderOverride: { file, _, _ in
                await gate.markStarted()
                await gate.waitUntilReleased()
                return PhotoAnalysisInput(
                    image: image,
                    iso: file.iso,
                    aperture: file.aperture,
                    normalizedAFPoint: file.normalizedAFPoint,
                )
            },
        )
        let model = SharpnessScoringModel(analysisAdapterOverride: adapter)
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
        #expect(model.scores[files[0].id] != nil)
        #expect(model.breakdowns[files[0].id] != nil)
        #expect(model.sortBySharpness)
        #expect(model.scoringProgress == 0)
        #expect(model.scoringTotal == 0)
    }
}

// MARK: - Numeric helper unit tests

private func makeSharpnessTestFile(afPoint: CGPoint? = nil) -> FileItem {
    let url = URL(fileURLWithPath: NSTemporaryDirectory())
        .appendingPathComponent("rawcull-sharpness-\(UUID().uuidString)")
        .appendingPathExtension("arw")

    return FileItem(
        url: url,
        name: url.lastPathComponent,
        size: 1,
        dateModified: Date(),
        exifData: nil,
        afFocusNormalized: afPoint,
    )
}

private func makeSharpnessTestImage(size: Int = 128) -> CGImage? {
    guard let colorSpace = CGColorSpace(name: CGColorSpace.sRGB),
          let context = CGContext(
              data: nil,
              width: size,
              height: size,
              bitsPerComponent: 8,
              bytesPerRow: size * 4,
              space: colorSpace,
              bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue,
          )
    else { return nil }

    context.setFillColor(gray: 0.08, alpha: 1)
    context.fill(CGRect(x: 0, y: 0, width: size, height: size))
    context.setFillColor(gray: 0.92, alpha: 1)
    let tile = 8
    for y in stride(from: 0, to: size, by: tile) {
        for x in stride(from: 0, to: size, by: tile)
            where (x / tile + y / tile).isMultiple(of: 2)
        {
            context.fill(CGRect(x: x, y: y, width: tile, height: tile))
        }
    }
    return context.makeImage()
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
        if startedCount >= count {
            return
        }
        await withCheckedContinuation { continuation in
            startedWaiters.append((count, continuation))
        }
    }

    func waitUntilReleased() async {
        if released {
            return
        }
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

private func makeAFDetailTestImage(sharpCenter: Bool) -> CGImage? {
    let size = 512
    guard let context = CGContext(
        data: nil, width: size, height: size, bitsPerComponent: 8,
        bytesPerRow: size * 4, space: CGColorSpaceCreateDeviceRGB(),
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue,
    ) else { return nil }
    context.setFillColor(gray: 0.5, alpha: 1)
    context.fill(CGRect(x: 0, y: 0, width: size, height: size))
    let center = CGRect(x: 192, y: 192, width: 128, height: 128)
    for y in stride(from: 0, to: size, by: 4) {
        for x in stride(from: 0, to: size, by: 4) {
            guard center.contains(CGPoint(x: x, y: y)) == sharpCenter else { continue }
            context.setFillColor(gray: (x / 4 + y / 4).isMultiple(of: 2) ? 0.08 : 0.92, alpha: 1)
            context.fill(CGRect(x: x, y: y, width: 4, height: 4))
        }
    }
    return context.makeImage()
}
