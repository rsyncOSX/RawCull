//
//  ARWTimingTests.swift
//  RawCullTests
//
//  Measures per-file time for the three core operations on real Sony ARW files:
//    1. Thumbnail creation  (SonyThumbnailExtractor)
//    2. EXIF extraction     (ImageIO / CGImageSource)
//    3. Focus point parsing (SonyMakerNoteParser)
//
//  ┌─────────────────────────────────────────────────────────┐
//  │  HOW TO USE                                             │
//  │  Set `catalogPath` below to a directory that contains   │
//  │  ~10 real Sony ARW files, then run the test suite.      │
//  │  Results are printed to the console — no assertions.    │
//  └─────────────────────────────────────────────────────────┘

import AppKit
import Foundation
import ImageIO
@testable import RawCull
import Testing

// ── Catalog location ──────────────────────────────────────────────────────────
// Set this to the folder containing your ARW test files.
// Leave empty to skip all timing tests gracefully.
private let catalogPath = "/Users/thomas/Pictures/TestARW"
// Example: private let catalogPath = "/Users/thomas/Pictures/TestARW"
// ─────────────────────────────────────────────────────────────────────────────

// MARK: - Helpers

private struct TimingResult {
    let filename: String
    let milliseconds: Double
}

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

private func durationMs(_ d: Duration) -> Double {
    Double(d.components.seconds) * 1_000
        + Double(d.components.attoseconds) / 1_000_000_000_000_000
}

private func printTable(title: String, results: [TimingResult]) {
    let divider = String(repeating: "─", count: 56)
    print("\n\(divider)")
    print("  \(title)")
    print(divider)
    for r in results {
        print(String(format: "  %-36@  %7.1f ms", r.filename as NSString, r.milliseconds))
    }
    print(divider)
    if !results.isEmpty {
        let times = results.map(\.milliseconds)
        let total = times.reduce(0, +)
        print(String(format: "  Files:    %d", results.count))
        print(String(format: "  Min:      %7.1f ms", times.min()!))
        print(String(format: "  Max:      %7.1f ms", times.max()!))
        print(String(format: "  Average:  %7.1f ms", total / Double(results.count)))
        print(String(format: "  Total:    %7.1f ms", total))
    }
    print(divider)
}

// MARK: - Tests

struct ARWTimingTests {

    // MARK: 1 — Thumbnail creation

    @Test
    func `Thumbnail creation timing`() async throws {
        let urls = arwURLs(in: catalogPath)
        guard !urls.isEmpty else {
            print("\n⚠️  ARWTimingTests: set catalogPath to run timing tests")
            return
        }

        let clock = ContinuousClock()
        var results: [TimingResult] = []

        for url in urls {
            let elapsed = try await clock.measure {
                // Raw extraction — bypasses cache for an honest cold-read measurement.
                _ = try await SonyThumbnailExtractor.extractSonyThumbnail(
                    from: url, maxDimension: 512
                )
            }
            results.append(TimingResult(filename: url.lastPathComponent,
                                        milliseconds: durationMs(elapsed)))
        }

        printTable(title: "Thumbnail Creation  (SonyThumbnailExtractor, maxDimension=512)",
                   results: results)
    }

    // MARK: 2 — EXIF extraction

    @Test
    func `EXIF extraction timing`() {
        let urls = arwURLs(in: catalogPath)
        guard !urls.isEmpty else {
            print("\n⚠️  ARWTimingTests: set catalogPath to run timing tests")
            return
        }

        let clock = ContinuousClock()
        var results: [TimingResult] = []

        for url in urls {
            let elapsed = clock.measure {
                // Mirror of ScanFiles.extractExifData — CGImageSource property read.
                guard let src = CGImageSourceCreateWithURL(url as CFURL, nil) else { return }
                _ = CGImageSourceCopyPropertiesAtIndex(src, 0, nil)
            }
            results.append(TimingResult(filename: url.lastPathComponent,
                                        milliseconds: durationMs(elapsed)))
        }

        printTable(title: "EXIF Extraction  (CGImageSourceCopyPropertiesAtIndex)",
                   results: results)
    }

    // MARK: 3 — Focus point extraction

    @Test
    func `Focus point extraction timing`() {
        let urls = arwURLs(in: catalogPath)
        guard !urls.isEmpty else {
            print("\n⚠️  ARWTimingTests: set catalogPath to run timing tests")
            return
        }

        let clock = ContinuousClock()
        var results: [TimingResult] = []
        var successCount = 0

        for url in urls {
            var found = false
            let elapsed = clock.measure {
                found = SonyMakerNoteParser.focusLocation(from: url) != nil
            }
            if found { successCount += 1 }
            results.append(TimingResult(filename: url.lastPathComponent,
                                        milliseconds: durationMs(elapsed)))
        }

        printTable(title: "Focus Point Extraction  (SonyMakerNoteParser, native TIFF parse)",
                   results: results)
        print(String(format: "  Found focus data in %d / %d files", successCount, urls.count))
        print(String(repeating: "─", count: 56))
    }
}
