//
//  ARWJPEGExtractionTests.swift
//  RawCullTests
//
//  Diagnostic test for embedded JPEG extraction across Sony camera bodies.
//  For each ARW file in the catalog it exercises two extraction paths:
//
//    1. Binary parser  — SonyMakerNoteParser.embeddedJPEGLocations reads the
//       TIFF IFD chain to find the thumbnail, preview, and full-JPEG locations,
//       then reads the raw bytes directly from the file.  This path works even
//       when the macOS RA16 decoder returns err=-50 (ARW 6.0 / A7V).
//
//    2. JPGSonyARWExtractor — the production extractor used by "Extract JPGs".
//       Run in both thumbnail mode (fullSize: false) and export mode (fullSize: true).
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

/// Must match the path set in ARWBodyCompatibilityTests.swift.
private let catalogPath = "/Users/thomas/ARWtestfiles"

// MARK: - Private helpers

private func arwURLsForExtraction(in path: String) -> [URL] {
    guard !path.isEmpty else { return [] }
    let dir = URL(fileURLWithPath: path, isDirectory: true)
    guard let contents = try? FileManager.default.contentsOfDirectory(
        at: dir, includingPropertiesForKeys: nil, options: .skipsHiddenFiles
    ) else { return [] }
    return contents
        .filter { $0.pathExtension.lowercased() == "arw" }
        .sorted { $0.lastPathComponent < $1.lastPathComponent }
}

/// Decode raw JPEG bytes and return the image dimensions, or nil on failure.
private func decodeJPEGDimensions(from data: Data) -> (width: Int, height: Int)? {
    guard let src = CGImageSourceCreateWithData(data as CFData, nil),
          let props = CGImageSourceCopyPropertiesAtIndex(src, 0, nil) as? [CFString: Any],
          let w = props[kCGImagePropertyPixelWidth] as? Int,
          let h = props[kCGImagePropertyPixelHeight] as? Int
    else { return nil }
    return (w, h)
}

/// Returns the camera model string from EXIF, or "unknown".
private func cameraModel(from url: URL) -> String {
    guard let src = CGImageSourceCreateWithURL(url as CFURL, nil),
          let props = CGImageSourceCopyPropertiesAtIndex(src, 0, nil) as? [CFString: Any],
          let tiff = props[kCGImagePropertyTIFFDictionary] as? [CFString: Any],
          let model = tiff[kCGImagePropertyTIFFModel] as? String
    else { return "unknown" }
    return model
}

private func formatBytes(_ n: Int) -> String {
    ByteCountFormatter.string(fromByteCount: Int64(n), countStyle: .file)
}

private struct ExtractionResult {
    let camera: String
    let binaryThumbnailOK: Bool
    let binaryPreviewOK: Bool
    let binaryFullJPEGOK: Bool
    let extractorThumbOK: Bool
    let extractorFullOK: Bool
}

// MARK: - Test

struct ARWJPEGExtractionTests {

    @Test(.tags(.integration))
    @MainActor
    func `ARW JPEG extraction diagnostic`() async {
        let urls = arwURLsForExtraction(in: catalogPath)
        guard !urls.isEmpty else {
            print("\n⚠️  ARWJPEGExtractionTests: set catalogPath in ARWBodyCompatibilityTests.swift")
            return
        }

        let D = String(repeating: "=", count: 64)
        let d = String(repeating: "─", count: 64)
        print("\n\(D)")
        print("JPEG EXTRACTION DIAGNOSTIC: \(catalogPath)")
        print("Files found: \(urls.count)")
        print(D)

        var results: [ExtractionResult] = []

        for (idx, url) in urls.enumerated() {
            let name = url.lastPathComponent
            let resKeys: [URLResourceKey] = [.fileSizeKey]
            let res = try? url.resourceValues(forKeys: Set(resKeys))
            let sizeStr = ByteCountFormatter.string(
                fromByteCount: Int64(res?.fileSize ?? 0), countStyle: .file)

            print("\n\(D)")
            print("FILE [\(idx + 1)/\(urls.count)]: \(name)   \(sizeStr)")
            print(D)

            let camera = cameraModel(from: url)
            print("  Camera: \(camera)")

            // ── 1. Binary parser ─────────────────────────────────────────────
            print("\n── BINARY PARSER (SonyMakerNoteParser) " + String(repeating: "─", count: 26))

            var binaryThumbOK = false
            var binaryPreviewOK = false
            var binaryFullOK = false

            if let locations = SonyMakerNoteParser.embeddedJPEGLocations(from: url) {

                // Thumbnail (IFD1)
                if let loc = locations.thumbnail {
                    print("  Thumbnail:   offset=\(loc.offset)  length=\(formatBytes(loc.length))")
                    if let data = SonyMakerNoteParser.readEmbeddedJPEGData(at: loc, from: url),
                       let dim = decodeJPEGDimensions(from: data) {
                        print("               → decoded OK  \(dim.width) × \(dim.height) px")
                        binaryThumbOK = true
                    } else {
                        print("               → FAILED to decode bytes as JPEG")
                    }
                } else {
                    print("  Thumbnail:   NOT FOUND in IFD1")
                }

                // Preview (IFD0)
                if let loc = locations.preview {
                    print("  Preview:     offset=\(loc.offset)  length=\(formatBytes(loc.length))")
                    if let data = SonyMakerNoteParser.readEmbeddedJPEGData(at: loc, from: url),
                       let dim = decodeJPEGDimensions(from: data) {
                        print("               → decoded OK  \(dim.width) × \(dim.height) px")
                        binaryPreviewOK = true
                    } else {
                        print("               → FAILED to decode bytes as JPEG")
                    }
                } else {
                    print("  Preview:     NOT FOUND in IFD0")
                }

                // Full JPEG (IFD2)
                if let loc = locations.fullJPEG {
                    print("  Full JPEG:   offset=\(loc.offset)  length=\(formatBytes(loc.length))")
                    if let data = SonyMakerNoteParser.readEmbeddedJPEGData(at: loc, from: url),
                       let dim = decodeJPEGDimensions(from: data) {
                        print("               → decoded OK  \(dim.width) × \(dim.height) px")
                        binaryFullOK = true
                    } else {
                        print("               → FAILED to decode bytes as JPEG")
                    }
                } else {
                    print("  Full JPEG:   NOT FOUND in IFD2")
                }

            } else {
                print("  FAILED — could not parse TIFF IFD chain")
            }

            // ── 2. JPGSonyARWExtractor ───────────────────────────────────────
            print("\n── JPGSonyARWExtractor " + String(repeating: "─", count: 42))

            // Thumbnail mode (fullSize: false, max 4320 px)
            let thumbImage = await JPGSonyARWExtractor.jpgSonyARWExtractor(
                from: url, fullSize: false)
            if let img = thumbImage {
                print("  Thumbnail mode:  OK   \(img.width) × \(img.height) px")
            } else {
                print("  Thumbnail mode:  FAILED")
            }

            // Export mode (fullSize: true, max 8640 px)
            let fullImage = await JPGSonyARWExtractor.jpgSonyARWExtractor(
                from: url, fullSize: true)
            if let img = fullImage {
                print("  Export mode:     OK   \(img.width) × \(img.height) px")
            } else {
                print("  Export mode:     FAILED")
            }

            results.append(ExtractionResult(
                camera: camera,
                binaryThumbnailOK: binaryThumbOK,
                binaryPreviewOK: binaryPreviewOK,
                binaryFullJPEGOK: binaryFullOK,
                extractorThumbOK: thumbImage != nil,
                extractorFullOK: fullImage != nil))
        }

        // ── Summary table ────────────────────────────────────────────────────
        print("\n\(D)")
        print("SUMMARY — \(urls.count) files scanned")
        print(D)

        func pad(_ s: String, _ width: Int) -> String {
            s.count >= width ? s : s + String(repeating: " ", count: width - s.count)
        }

        print("\(pad("Camera body", 24))  Files  BinThumb  BinPrev  BinFull  ExtThumb  ExtFull")
        print(d)

        var byCamera: [String: [ExtractionResult]] = [:]
        for r in results { byCamera[r.camera, default: []].append(r) }

        var totN = 0, totBT = 0, totBP = 0, totBF = 0, totET = 0, totEF = 0
        for (cam, group) in byCamera.sorted(by: { $0.key < $1.key }) {
            let n   = group.count
            let bt  = group.filter(\.binaryThumbnailOK).count
            let bp  = group.filter(\.binaryPreviewOK).count
            let bf  = group.filter(\.binaryFullJPEGOK).count
            let et  = group.filter(\.extractorThumbOK).count
            let ef  = group.filter(\.extractorFullOK).count
            totN += n; totBT += bt; totBP += bp; totBF += bf; totET += et; totEF += ef
            print(String(format: "%@  %4d   %3d/%-3d   %3d/%-3d   %3d/%-3d   %3d/%-3d   %3d/%-3d",
                         pad(cam, 24) as NSString, n,
                         bt, n, bp, n, bf, n, et, n, ef, n))
        }
        print(d)
        print(String(format: "%@  %4d   %3d/%-3d   %3d/%-3d   %3d/%-3d   %3d/%-3d   %3d/%-3d",
                     pad("Total", 24) as NSString, totN,
                     totBT, totN, totBP, totN, totBF, totN, totET, totN, totEF, totN))
        print(D)
    }
}
