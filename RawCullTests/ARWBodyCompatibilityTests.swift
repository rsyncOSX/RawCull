//
//  ARWBodyCompatibilityTests.swift
//  RawCullTests
//
//  Diagnostic test for ARW compatibility across Sony camera bodies.
//  For each file in the catalog it prints every piece of data RawCull
//  extracts: EXIF, a verbose TIFF IFD walk for the focus point, sharpness
//  score with ISO-adaptation breakdown, and saliency / subject detection.
//
//  No assertions — console output only.
//
//  ┌─────────────────────────────────────────────────────────┐
//  │  HOW TO USE                                             │
//  │  Set `catalogPath` to a directory containing ARW files  │
//  │  from the Sony bodies you want to validate, then run    │
//  │  the test.  Files are processed in filename order.      │
//  └─────────────────────────────────────────────────────────┘

import Foundation
import ImageIO
@testable import RawCull
import Testing
import Vision

/// Set this to the folder containing your multi-body ARW test files.
private let catalogPath = "/Users/thomas/ARWtestfiles"

// MARK: - Tag

extension Tag {
    @Tag static var integration: Self
}

// MARK: - Private helpers

private func arwURLs(in path: String) -> [URL] {
    guard !path.isEmpty else { return [] }
    let dir = URL(fileURLWithPath: path, isDirectory: true)
    guard let contents = try? FileManager.default.contentsOfDirectory(
        at: dir, includingPropertiesForKeys: nil, options: .skipsHiddenFiles
    ) else { return [] }
    return contents
        .filter { $0.pathExtension.lowercased() == "arw" }
        .sorted { $0.lastPathComponent < $1.lastPathComponent }
}

private func decodeThumbnail(from url: URL, maxPx: Int) -> CGImage? {
    let options: [CFString: Any] = [
        kCGImageSourceCreateThumbnailFromImageIfAbsent: true,
        kCGImageSourceCreateThumbnailFromImageAlways: false,
        kCGImageSourceCreateThumbnailWithTransform: true,
        kCGImageSourceThumbnailMaxPixelSize: maxPx,
        kCGImageSourceShouldCacheImmediately: true,
    ]
    guard let src = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
    return CGImageSourceCreateThumbnailAtIndex(src, 0, options as CFDictionary)
}

private struct SaliencyDetail {
    let boundingBox: CGRect?
    let area: Float
    let maxConfidence: Float
    let subjectLabel: String?
}

/// Mirrors `FocusMaskModel.detectSaliencyAndClassify` +
/// `FocusMaskModel.bestClassificationLabel`, but also exposes the bounding
/// box and confidence that are not returned by `computeSharpnessScore`.
private func runSaliencyDetail(cgImage: CGImage) -> SaliencyDetail {
    let saliencyReq = VNGenerateAttentionBasedSaliencyImageRequest()
    let classifyReq = VNClassifyImageRequest()
    let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
    try? handler.perform([saliencyReq, classifyReq])

    guard let obs = saliencyReq.results?.first,
          let objects = obs.salientObjects, !objects.isEmpty
    else { return SaliencyDetail(boundingBox: nil, area: 0, maxConfidence: 0, subjectLabel: nil) }

    let union = objects.reduce(CGRect.null) { $0.union($1.boundingBox) }
    let maxConf = objects.map(\.confidence).max() ?? 0
    let area = Float(union.width * union.height)
    guard area > 0.03 || maxConf >= 0.9 else {
        return SaliencyDetail(boundingBox: nil, area: 0, maxConfidence: maxConf, subjectLabel: nil)
    }

    // Subject label — two-pass logic mirrors FocusMaskModel.bestClassificationLabel
    let subjectKw = ["bird", "raptor", "fowl", "waterfowl", "wildlife",
                     "animal", "mammal", "vertebrate", "creature", "predator",
                     "reptile", "amphibian", "insect", "spider",
                     "dog", "cat", "horse", "deer", "bear", "fox", "wolf",
                     "lion", "tiger", "elephant", "monkey", "ape",
                     "person", "people", "human", "face", "portrait"]
    let envKw = ["structure", "plant", "grass", "tree", "forest", "wood",
                 "nature", "outdoor", "indoor", "landscape", "sky", "water",
                 "ground", "soil", "rock", "stone", "darkness", "light",
                 "photography", "scene", "background", "texture", "pattern"]
    let observations = classifyReq.results ?? []
    var label: String?

    // Pass 1: subject keywords at low confidence threshold
    for o in observations where o.confidence >= 0.06 {
        let id = o.identifier.lowercased()
        if subjectKw.contains(where: { id.contains($0) }) {
            label = o.identifier.replacingOccurrences(of: "_", with: " ")
            break
        }
    }
    // Pass 2: anything that is not a pure environment label
    if label == nil {
        for o in observations where o.confidence >= 0.15 {
            let id = o.identifier.lowercased()
            if !envKw.contains(where: { id.contains($0) }) {
                label = o.identifier.replacingOccurrences(of: "_", with: " ")
                break
            }
        }
    }

    return SaliencyDetail(boundingBox: union, area: area, maxConfidence: maxConf, subjectLabel: label)
}

private func sizeClassForTest(width: Int, height: Int, camera: String) -> String {
    let mp = Double(width * height) / 1_000_000
    let upper = camera.uppercased()
    let (lThresh, mThresh): (Double, Double)
    if upper.contains("ILCE-7RM")      { (lThresh, mThresh) = (50, 22) }
    else if upper.contains("ILCE-1")   { (lThresh, mThresh) = (40, 18) }
    else if upper.contains("ILCE-9")   { (lThresh, mThresh) = (20, 10) }
    else if upper.contains("ILCE-7")   { (lThresh, mThresh) = (28, 14) }
    else                               { (lThresh, mThresh) = (25, 10) }
    if mp >= lThresh { return "L" }
    if mp >= mThresh { return "M" }
    return "S"
}

// Per-file result used to build the summary table
private struct BodyFileResult {
    let camera: String
    let exifOK: Bool
    let focusOK: Bool
    let sharpnessOK: Bool
    let saliencyFound: Bool
}

// MARK: - Test

struct ARWBodyCompatibilityTests {

    @Test(.tags(.integration))
    @MainActor
    func `ARW body compatibility diagnostic`() async {
        let urls = arwURLs(in: catalogPath)
        guard !urls.isEmpty else {
            print("\n⚠️  ARWBodyCompatibilityTests: set catalogPath in ARWBodyCompatibilityTests.swift")
            return
        }

        let D = String(repeating: "=", count: 64)
        let d = String(repeating: "─", count: 64)
        print("\n\(D)")
        print("SCANNING CATALOG: \(catalogPath)")
        print("Files found: \(urls.count)")
        print(D)

        let model = FocusMaskModel()
        var results: [BodyFileResult] = []

        for (idx, url) in urls.enumerated() {
            let name = url.lastPathComponent
            let resKeys: [URLResourceKey] = [.fileSizeKey, .contentModificationDateKey]
            let res = try? url.resourceValues(forKeys: Set(resKeys))
            let sizeStr = ByteCountFormatter.string(
                fromByteCount: Int64(res?.fileSize ?? 0), countStyle: .file)
            let dateStr: String = res?.contentModificationDate
                .map { ISO8601DateFormatter().string(from: $0) } ?? "(unknown)"

            print("\n\(D)")
            print("FILE [\(idx + 1)/\(urls.count)]: \(name)   \(sizeStr)   \(dateStr)")
            print(D)

            // ── EXIF ────────────────────────────────────────────────────────
            print("\n── EXIF " + String(repeating: "─", count: 57))

            guard let src = CGImageSourceCreateWithURL(url as CFURL, nil),
                  let props = CGImageSourceCopyPropertiesAtIndex(src, 0, nil) as? [CFString: Any],
                  let exif = props[kCGImagePropertyExifDictionary] as? [CFString: Any],
                  let tiff = props[kCGImagePropertyTIFFDictionary] as? [CFString: Any]
            else {
                print("  [EXIF: FAILED — CGImageSourceCopyPropertiesAtIndex returned nothing]")
                results.append(BodyFileResult(camera: "unknown", exifOK: false,
                                             focusOK: false, sharpnessOK: false, saliencyFound: false))
                continue
            }

            let camera  = tiff[kCGImagePropertyTIFFModel] as? String ?? "unknown"
            let lens    = exif[kCGImagePropertyExifLensModel] as? String
            let fNum    = exif[kCGImagePropertyExifFNumber] as? NSNumber
            let rawISO  = (exif[kCGImagePropertyExifISOSpeedRatings] as? [Int])?.first
            let fLen    = exif[kCGImagePropertyExifFocalLength] as? NSNumber
            let expT    = exif[kCGImagePropertyExifExposureTime] as? NSNumber

            print("  Camera:        \(camera)")
            print("  Lens:          \(lens ?? "(nil)")")
            if let v = expT?.doubleValue {
                let ss = v >= 1 ? String(format: "%.1f\"", v) : String(format: "1/%.0f", 1 / v)
                print("  Shutter:       \(ss)")
            }
            if let fn = fNum?.doubleValue {
                print(String(format: "  Aperture:      ƒ/%.1f   (raw: %.1f)", fn, fn))
            }
            if let fl = fLen?.doubleValue {
                print(String(format: "  Focal length:  %.1fmm", fl))
            }
            if let iso = rawISO {
                print("  ISO:           ISO \(iso)   (raw: \(iso))")
            }

            // Pixel dimensions + size class
            let pixelWidth  = props[kCGImagePropertyPixelWidth]  as? Int
            let pixelHeight = props[kCGImagePropertyPixelHeight] as? Int
            if let w = pixelWidth, let h = pixelHeight {
                let mp = Double(w * h) / 1_000_000
                let sc = sizeClassForTest(width: w, height: h, camera: camera)
                print(String(format: "  Dimensions:    %d × %d  (%.1f MP)  → Size class: %@", w, h, mp, sc))
            }

            // RAW compression type
            if let compVal = tiff[kCGImagePropertyTIFFCompression] as? Int {
                let label: String
                switch compVal {
                case 1:     label = "Uncompressed"
                case 6:     label = "Compressed"           // newer Sony bodies (A1, A7R V…)
                case 7:     label = "Lossless Compressed"  // newer Sony bodies (A1, A7R V…)
                case 32767: label = "Compressed"           // older Sony bodies
                case 32770: label = "Lossless Compressed"  // older Sony bodies
                default:    label = "Unknown (\(compVal))"
                }
                print("  RAW file type: \(label)   (TIFF compression tag: \(compVal))")
            }

            // ── Focus point TIFF walk ────────────────────────────────────────
            print("\n── FOCUS POINT (SonyMakerNote) " + String(repeating: "─", count: 34))

            var focusOK = false
            if let diag = SonyMakerNoteParser.tiffDiagnostics(from: url) {
                print(String(format: "  TIFF header:      %@   IFD0 at offset %d",
                             diag.isLittleEndian ? "LE (little-endian)" : "BE (big-endian)",
                             diag.ifd0Offset))
                print("  IFD0:             \(diag.ifd0EntryCount) entries")
                if let exifOff = diag.exifIFDOffset {
                    print(String(format: "    tag 0x8769 (ExifIFD) → offset %d", exifOff))
                    print("  ExifIFD:          \(diag.exifEntryCount ?? 0) entries")
                } else {
                    print("    tag 0x8769 (ExifIFD) → NOT FOUND")
                }
                if let mnOff = diag.makerNoteOffset, let mnSz = diag.makerNoteSize {
                    print(String(format: "    tag 0x927C (MakerNote) → offset %d, %d bytes", mnOff, mnSz))
                } else {
                    print("    tag 0x927C (MakerNote) → NOT FOUND")
                }
                if let sonyOff = diag.sonyIFDOffset {
                    let prefix = diag.hasSonyPrefix ? "\"SONY DSC \" found" : "no SONY prefix"
                    print(String(format: "  Sony prefix:      %@ → IFD starts at offset %d",
                                 prefix as NSString, sonyOff))
                    print("  Sony IFD:         \(diag.sonyIFDEntryCount ?? 0) entries")
                    let tagHex = diag.sonyAllTags
                        .map { String(format: "0x%04X", $0) }.joined(separator: " ")
                    print("    Tags present:   \(tagHex.isEmpty ? "(none)" : tagHex)")
                    if let tag = diag.focusTagUsed, let flOff = diag.focusOffset,
                       let raw = diag.focusRawBytes {
                        let rawHex = raw.map { String(format: "%02X", $0) }.joined(separator: " ")
                        print(String(format: "    tag 0x%04X (FocusLocation) → offset %d, 8 bytes",
                                     tag, flOff))
                        print("    Raw bytes:      \(rawHex)")
                        if let fr = diag.focusResult {
                            print("    Decoded:        sensorW=\(fr.width)  sensorH=\(fr.height)  x=\(fr.x)  y=\(fr.y)")
                            print(String(format: "  Normalized:       x=%.3f   y=%.3f",
                                         Double(fr.x) / Double(fr.width),
                                         Double(fr.y) / Double(fr.height)))
                            focusOK = true
                        } else {
                            print("    Decoded:        INVALID (zero dimensions or zero coords)")
                        }
                    } else {
                        print("    tag 0x2027 (FocusLocation) → NOT FOUND")
                        print("    tag 0x204A (FocusLocation alt) → NOT FOUND")
                        print("  Result:           FAILED — no focus location tag for this body")
                    }
                } else {
                    print("  Result:           FAILED — MakerNote not reachable")
                }
            } else {
                print("  Result:           FAILED — could not parse TIFF header")
            }

            // ── Sharpness score ──────────────────────────────────────────────
            print("\n── SHARPNESS SCORE " + String(repeating: "─", count: 45))

            let isoVal = rawISO ?? 400
            var cfg = FocusDetectorConfig()
            cfg.iso = isoVal

            let isoFactor  = max(1.0, min(sqrt(Float(max(isoVal, 1)) / 400.0), 3.0))
            let resFactor: Float = 1.0  // 512 px thumbnail → baseline
            let effective  = min(cfg.preBlurRadius * isoFactor * resFactor, 100.0)

            let (score, _) = await model.computeSharpnessScore(
                fromRawURL: url, config: cfg, thumbnailMaxPixelSize: 512)

            print("  Thumbnail:        512 px max dimension")
            print(String(format: "  preBlurRadius:    %.2f (base)", cfg.preBlurRadius))
            print(String(format: "    ISO factor:     √(%d/400) = %.2f   →   without ISO: %.2f   with ISO: %.2f",
                         isoVal, isoFactor, cfg.preBlurRadius, cfg.preBlurRadius * isoFactor))
            print(String(format: "    res factor:     √(512/512) = %.2f   →   effective: %.2f",
                         resFactor, effective))
            print(String(format: "  energyMultiplier: %.2f", cfg.energyMultiplier))
            print(String(format: "  threshold:        %.2f", cfg.threshold))
            print(String(format: "  salientWeight:    %.2f", cfg.salientWeight))
            if let s = score {
                print(String(format: "  Score:            %.4f", s))
            } else {
                print("  Score:            [FAILED — thumbnail decode or scoring failed]")
            }

            // ── Saliency / subject ───────────────────────────────────────────
            print("\n── SALIENCY / SUBJECT " + String(repeating: "─", count: 43))

            var saliencyFound = false
            if let thumb = decodeThumbnail(from: url, maxPx: 512) {
                let sal = runSaliencyDetail(cgImage: thumb)
                if let bbox = sal.boundingBox {
                    saliencyFound = true
                    print("  Salient region:   YES")
                    print(String(format: "  BBox (norm):      x=%.2f–%.2f   y=%.2f–%.2f   area=%.1f%%",
                                 bbox.minX, bbox.maxX, bbox.minY, bbox.maxY, sal.area * 100))
                    print(String(format: "  Max confidence:   %.2f", sal.maxConfidence))
                    if let lbl = sal.subjectLabel {
                        print("  Subject label:    \(lbl)   (VNClassifyImageRequest)")
                    } else {
                        print("  Subject label:    (none above threshold)")
                    }
                } else {
                    print("  Salient region:   NO — score used full-frame only")
                    print(String(format: "  Max confidence:   %.2f", sal.maxConfidence))
                }
            } else {
                print("  [FAILED — thumbnail decode failed]")
            }

            results.append(BodyFileResult(
                camera: camera,
                exifOK: true,
                focusOK: focusOK,
                sharpnessOK: score != nil,
                saliencyFound: saliencyFound))
        }

        // ── Summary table ────────────────────────────────────────────────────
        print("\n\(D)")
        print("SUMMARY — \(urls.count) files scanned")
        print(D)

        var byCamera: [String: [BodyFileResult]] = [:]
        for r in results { byCamera[r.camera, default: []].append(r) }

        func pad(_ s: String, _ width: Int) -> String {
            s.count >= width ? s : s + String(repeating: " ", count: width - s.count)
        }
        print("\(pad("Camera body", 24)) Files   EXIF   FocusPt  Sharpness  Saliency")
        print(d)

        var totFiles = 0, totExif = 0, totFocus = 0, totSharp = 0, totSal = 0
        for (cam, group) in byCamera.sorted(by: { $0.key < $1.key }) {
            let n     = group.count
            let exif  = group.filter(\.exifOK).count
            let focus = group.filter(\.focusOK).count
            let sharp = group.filter(\.sharpnessOK).count
            let sal   = group.filter(\.saliencyFound).count
            totFiles += n; totExif += exif; totFocus += focus; totSharp += sharp; totSal += sal
            print(String(format: "%@  %4d   %3d/%-3d  %3d/%-3d   %3d/%-3d   %3d/%-3d",
                         pad(cam, 24) as NSString, n,
                         exif, n, focus, n, sharp, n, sal, n))
        }
        print(d)
        print(String(format: "%@  %4d   %3d/%-3d  %3d/%-3d   %3d/%-3d   %3d/%-3d",
                     pad("Total", 24) as NSString, totFiles,
                     totExif, totFiles, totFocus, totFiles, totSharp, totFiles, totSal, totFiles))

        // Call out bodies with no focus point support and remind where to find their tag list
        let noFocusBodies = byCamera
            .filter { $0.value.allSatisfy { !$0.focusOK } }
            .keys.sorted()
        if !noFocusBodies.isEmpty {
            print("\nBodies with no focus point support:")
            for cam in noFocusBodies {
                print("  \(cam) — see \"Tags present\" lines above to find candidate tags")
            }
        }

        print(D)
    }
}
