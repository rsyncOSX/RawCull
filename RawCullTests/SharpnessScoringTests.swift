//
//  SharpnessScoringTests.swift
//  RawCullTests
//
//  Diagnostic test for the sharpness scoring pipeline using full-size thumbnails.
//  Uses thumbnailMaxPixelSize: 4320 (the full embedded JPEG preview resolution).
//  Prints per-file detail and a ranked summary table.
//
//  No assertions — console output only.
//
//  ┌─────────────────────────────────────────────────────────┐
//  │  HOW TO USE                                             │
//  │  Set `catalogPath` to a directory containing ARW files, │
//  │  then run the test. Compare scores against the same     │
//  │  files in ARWBodyCompatibilityTests (512 px path).      │
//  └─────────────────────────────────────────────────────────┘

import Foundation
import ImageIO
@testable import RawCull
import Testing

private let catalogPath = "/Users/thomas/ARWtestfiles"

/// Max pixel dimension for the full embedded JPEG preview in Sony A1 ARW files.
private let thumbnailMaxPx = 4320

private func arwURLs(in path: String) -> [URL] {
    guard !path.isEmpty else { return [] }
    let dir = URL(fileURLWithPath: path, isDirectory: true)
    guard let contents = try? FileManager.default.contentsOfDirectory(
        at: dir, includingPropertiesForKeys: nil, options: .skipsHiddenFiles,
    ) else { return [] }
    return contents
        .filter { $0.pathExtension.lowercased() == "arw" }
        .sorted { $0.lastPathComponent < $1.lastPathComponent }
}

/// Decodes the embedded thumbnail and returns its pixel dimensions.
/// Uses the same CGImageSource options as `FocusMaskModel.decodeThumbnail`.
private func decodeThumbnailSize(url: URL, maxPx: Int) -> (width: Int, height: Int)? {
    let options: [CFString: Any] = [
        kCGImageSourceCreateThumbnailFromImageIfAbsent: false,
        kCGImageSourceCreateThumbnailFromImageAlways: false,
        kCGImageSourceCreateThumbnailWithTransform: true,
        kCGImageSourceThumbnailMaxPixelSize: maxPx,
        kCGImageSourceShouldCacheImmediately: true
    ]
    guard let src = CGImageSourceCreateWithURL(url as CFURL, nil),
          let img = CGImageSourceCreateThumbnailAtIndex(src, 0, options as CFDictionary)
    else { return nil }
    return (img.width, img.height)
}

private struct ScoringResult {
    let filename: String
    let camera: String
    let score: Float?
    let saliencyDetected: Bool
    let saliencyLabel: String?
}

// MARK: - Test

struct SharpnessScoringTests {
    @Test(.tags(.integration))
    @MainActor
    func `ARW sharpness scoring diagnostic`() async {
        let urls = arwURLs(in: catalogPath)
        guard !urls.isEmpty else {
            print("\n⚠️  SharpnessScoringTests: no ARW files found at \(catalogPath)")
            return
        }

        let D = String(repeating: "=", count: 64)
        let d = String(repeating: "─", count: 64)
        print("\n\(D)")
        print("SHARPNESS SCORING DIAGNOSTIC — FULL-SIZE THUMBNAIL")
        print("Catalog:    \(catalogPath)")
        print("Thumbnail:  max \(thumbnailMaxPx) px  (full embedded JPEG preview)")
        print("Files:      \(urls.count)")
        print(D)

        let model = FocusMaskModel()
        var results: [ScoringResult] = []

        for (idx, url) in urls.enumerated() {
            let name = url.lastPathComponent
            print("\n\(d)")
            print("FILE [\(idx + 1)/\(urls.count)]: \(name)")
            print(d)

            // ── EXIF ──────────────────────────────────────────────────────────
            let cgSrc = CGImageSourceCreateWithURL(url as CFURL, nil)
            let props = cgSrc.flatMap {
                CGImageSourceCopyPropertiesAtIndex($0, 0, nil) as? [CFString: Any]
            }
            let exif = props?[kCGImagePropertyExifDictionary] as? [CFString: Any]
            let tiff = props?[kCGImagePropertyTIFFDictionary] as? [CFString: Any]

            let camera = tiff?[kCGImagePropertyTIFFModel] as? String ?? "unknown"
            let rawISO = (exif?[kCGImagePropertyExifISOSpeedRatings] as? [Int])?.first
            let fNum = exif?[kCGImagePropertyExifFNumber] as? NSNumber
            let fLen = exif?[kCGImagePropertyExifFocalLength] as? NSNumber
            let isoVal = rawISO ?? 400

            // ── Thumbnail dimensions ──────────────────────────────────────────
            let thumbSize = decodeThumbnailSize(url: url, maxPx: thumbnailMaxPx)

            // ── Config + blur breakdown ───────────────────────────────────────
            var cfg = FocusDetectorConfig()
            cfg.iso = isoVal

            let isoFactor = FocusMaskModel.isoScalingFactor(iso: isoVal)
            let imageWidth = Float(thumbSize?.width ?? thumbnailMaxPx)
            let resFactor = max(1.0, min(sqrt(max(imageWidth, 512.0) / 512.0), 3.0))
            let blurDamp = cfg.apertureHint.blurDamp
            let effective = min(cfg.preBlurRadius * isoFactor * resFactor * blurDamp, 100.0)

            // ── Score ─────────────────────────────────────────────────────────
            let (score, saliency) = await model.computeSharpnessScore(
                fromRawURL: url, config: cfg, thumbnailMaxPixelSize: thumbnailMaxPx,
            )

            // ── Print per-file section ────────────────────────────────────────
            print("\n── SHARPNESS SCORE " + String(repeating: "─", count: 45))
            print("  Camera:        \(camera)")

            var exposureLine = "  ISO:           "
            if let iso = rawISO {
                exposureLine += "ISO \(iso)"
            } else {
                exposureLine += "(unknown, using 400)"
            }
            if let fn = fNum?.doubleValue {
                exposureLine += String(format: "   aperture: ƒ/%.1f", fn)
            }
            if let fl = fLen?.doubleValue {
                exposureLine += String(format: "   focal: %.0fmm", fl)
            }
            print(exposureLine)

            if let (w, h) = thumbSize {
                print(String(format: "  Thumbnail:     %d × %d px  (decoded at max %d)",
                             w, h, thumbnailMaxPx))
            } else {
                print("  Thumbnail:     [FAILED to decode at max \(thumbnailMaxPx) px]")
            }

            print(String(format: "  preBlurRadius: %.2f (base) × ISO[%d]=%.2f × res √(%.0f/512)=%.2f × damp[%.2f]  →  effective %.2f",
                         cfg.preBlurRadius, isoVal, isoFactor, imageWidth, resFactor, blurDamp, effective))
            print(String(format: "  energyMultiplier: %.2f   threshold: %.2f   salientWeight: %.2f",
                         cfg.energyMultiplier, cfg.threshold, cfg.salientWeight))

            if let s = score {
                print(String(format: "  Score:         %.4f", s))
            } else {
                print("  Score:         [FAILED — thumbnail decode or scoring failed]")
            }

            let saliencyDetected = saliency != nil
            let saliencyLabel: String? = saliency?.subjectLabel
            if saliencyDetected {
                if let lbl = saliencyLabel {
                    print("  Saliency:      \(lbl)")
                } else {
                    print("  Saliency:      detected (no subject label)")
                }
            } else {
                print("  Saliency:      none")
            }

            results.append(ScoringResult(
                filename: name,
                camera: camera,
                score: score,
                saliencyDetected: saliencyDetected,
                saliencyLabel: saliencyLabel,
            ))
        }

        // ── Summary table (ranked sharpest first) ────────────────────────────
        print("\n\(D)")
        print("SCORING SUMMARY — sharpest first  (thumbnail max \(thumbnailMaxPx) px)")
        print(D)

        func pad(_ s: String, _ width: Int) -> String {
            s.count >= width ? s : s + String(repeating: " ", count: width - s.count)
        }

        let ranked = results.sorted {
            switch ($0.score, $1.score) {
            case let (a?, b?): a > b
            case (_?, nil): true
            default: false
            }
        }

        print("\(pad("Rank", 5)) \(pad("File", 35)) \(pad("Score", 8)) \(pad("Subject", 22)) Camera")
        print(String(repeating: "─", count: 82))

        var scored = 0
        var saliencyCount = 0
        for (i, r) in ranked.enumerated() {
            let scoreStr = r.score.map { String(format: "%.4f", $0) } ?? "FAILED"
            let subjectStr = r.saliencyLabel ?? "—"
            let rankStr = "\(i + 1)"
            print("\(pad(rankStr, 5)) \(pad(String(r.filename.prefix(35)), 35)) \(pad(scoreStr, 8)) \(pad(String(subjectStr.prefix(22)), 22)) \(r.camera)")
            if r.score != nil { scored += 1 }
            if r.saliencyDetected { saliencyCount += 1 }
        }

        print(String(repeating: "─", count: 82))
        print("Scored: \(scored)/\(results.count)  |  Saliency detected: \(saliencyCount)/\(results.count)")
        print(D)
    }

    // MARK: - Unit tests

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
}

// MARK: - Numeric helper unit tests

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
