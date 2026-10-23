//
//  FocusNumericHelperTests.swift
//  RawCullVerifyTests
//

import CoreGraphics
import Foundation
import PhotoAnalysisKit
@testable import RawCull
import RawCullCore
import Testing

@Suite("FocusMaskModel numeric helpers")
struct FocusNumericHelperTests {
    // MARK: robustTailScore

    @Test(.tags(.smoke))
    func `robust tail score empty returns nil`() {
        #expect(SharpnessMetrics.robustTailScore([]) == nil)
    }

    @Test(.tags(.smoke))
    func `robust tail score uniform returns zero`() throws {
        // All values identical → p20 == p90 == p97, so spread is zero.
        let samples = [Float](repeating: 0.5, count: 1000)
        let score = SharpnessMetrics.robustTailScore(samples)
        #expect(score != nil)
        #expect(try #require(score) < 1e-5)
    }

    @Test(.tags(.smoke))
    func `robust tail score dense edges full density factor`() throws {
        // Linearly spaced 0…1: p20=0.20, p90=0.90, p97=0.97.
        // Band (p90…p97) contains 7% of values → density 0.07 > minDensity 0.06 → factor = 1.0.
        let n = 1000
        let samples = (0 ..< n).map { Float($0) / Float(n - 1) }
        let score = SharpnessMetrics.robustTailScore(samples)
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
        let score = SharpnessMetrics.robustTailScore(samples)
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
        let denseScore = SharpnessMetrics.robustTailScore(dense)
        let sparseScore = SharpnessMetrics.robustTailScore(sparse)
        #expect(denseScore != nil)
        #expect(sparseScore != nil)
        #expect(try #require(denseScore) > #require(sparseScore))
    }

    // MARK: microContrast

    @Test(.tags(.smoke))
    func `micro contrast empty returns zero`() {
        #expect(SharpnessMetrics.microContrast([]) == 0.0)
    }

    @Test(.tags(.smoke))
    func `micro contrast uniform returns zero`() {
        let samples = [Float](repeating: 0.5, count: 500)
        #expect(SharpnessMetrics.microContrast(samples) < 1e-5)
    }

    @Test(.tags(.smoke))
    func `micro contrast alternating known variance`() {
        // Values alternating 0 and 1: mean = 0.5, variance = 0.25, std-dev = 0.5.
        let samples: [Float] = (0 ..< 1000).map { $0 % 2 == 0 ? 0.0 : 1.0 }
        let result = SharpnessMetrics.microContrast(samples)
        #expect(abs(result - 0.5) < 0.01)
    }

    @Test(.tags(.smoke))
    func `micro contrast ignores non finite`() {
        // Mix of valid values and NaN/Inf — should not crash, should equal uniform result.
        var samples = [Float](repeating: 0.5, count: 100)
        samples.append(Float.nan)
        samples.append(Float.infinity)
        #expect(SharpnessMetrics.microContrast(samples) < 1e-5)
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
        let a = try #require(SharpnessMetrics.robustTailScore(base))
        let b = try #require(SharpnessMetrics.robustTailScore(scaled))
        // Allow 1% slack for percentile-index rounding noise.
        #expect(abs(b / a - 10) < 0.1)
    }

    // MARK: - Failure classification

    @Test(.tags(.smoke))
    func `focus failure classifier flags motion blur when all regions are weak`() {
        let result = SharpnessMetrics.classifyFocusFailure(
            globalScore: 0.03,
            subjectScore: 0.04,
            afPointScore: 0.05,
            blurGateSigma: 0.004,
        )
        #expect(result == .motionBlur)
    }

    @Test(.tags(.smoke))
    func `focus failure classifier flags missed focus when subject trails frame`() {
        let result = SharpnessMetrics.classifyFocusFailure(
            globalScore: 0.30,
            subjectScore: 0.10,
            afPointScore: 0.11,
            blurGateSigma: 0.03,
        )
        #expect(result == .missedFocus)
    }

    @Test(.tags(.smoke))
    func `focus failure classifier stays neutral for strong subject`() {
        let result = SharpnessMetrics.classifyFocusFailure(
            globalScore: 0.24,
            subjectScore: 0.22,
            afPointScore: 0.26,
            blurGateSigma: 0.03,
        )
        #expect(result == .none)
    }
}

