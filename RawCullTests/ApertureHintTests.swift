//
//  ApertureHintTests.swift
//  RawCullVerifyTests
//

import CoreGraphics
import Foundation
import PhotoAnalysisKit
@testable import RawCull
import RawCullCore
import Testing

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

