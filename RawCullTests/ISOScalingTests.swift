//
//  ISOScalingTests.swift
//  RawCullVerifyTests
//

import CoreGraphics
import Foundation
import PhotoAnalysisKit
@testable import RawCull
import RawCullCore
import Testing

@Suite("FocusMaskModel.isoScalingFactor")
struct ISOScalingTests {
    @Test(.tags(.smoke))
    func `below 800 is flat at 1 point 0`() {
        #expect(SharpnessMetrics.isoScalingFactor(iso: 100) == 1.0)
        #expect(SharpnessMetrics.isoScalingFactor(iso: 400) == 1.0)
        #expect(SharpnessMetrics.isoScalingFactor(iso: 799) == 1.0)
    }

    @Test(.tags(.smoke))
    func `mid range ramps to 1 point 6 at 3200`() {
        #expect(SharpnessMetrics.isoScalingFactor(iso: 800) == 1.0)
        let at2000 = SharpnessMetrics.isoScalingFactor(iso: 2000)
        #expect(abs(at2000 - 1.3) < 1e-4, "expected 1.3 at ISO 2000, got \(at2000)")
        let at3200 = SharpnessMetrics.isoScalingFactor(iso: 3200)
        #expect(abs(at3200 - 1.6) < 1e-4, "expected 1.6 at ISO 3200, got \(at3200)")
    }

    @Test(.tags(.smoke))
    func `high range caps at 2 point 2`() {
        #expect(SharpnessMetrics.isoScalingFactor(iso: 6400) > 1.6)
        #expect(SharpnessMetrics.isoScalingFactor(iso: 12800) == 2.2)
        #expect(SharpnessMetrics.isoScalingFactor(iso: 51200) == 2.2)
    }

    @Test(.tags(.smoke))
    func `monotonically non decreasing across range`() {
        let iso = [100, 200, 400, 800, 1600, 2000, 3200, 6400, 12800, 25600]
        let factors = iso.map { SharpnessMetrics.isoScalingFactor(iso: $0) }
        for i in 1 ..< factors.count {
            #expect(factors[i] >= factors[i - 1], "regression at ISO \(iso[i])")
        }
    }

    @Test(.tags(.smoke))
    func `high ISO is less aggressive than old sqrt formula`() {
        // Regression guard: the previous sqrt(ISO/400) clamped to 3.0 produced 3.0 at
        // ISO 3600+, over-blurring real detail on A1-series bodies. The new curve must
        // stay well under 3.0 at ISO 6400.
        #expect(SharpnessMetrics.isoScalingFactor(iso: 6400) < 2.0)
    }
}
