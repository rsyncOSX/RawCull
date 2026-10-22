import CoreImage
import Foundation
import ImageIO
import PhotoAnalysisKit
import Testing
import UniformTypeIdentifiers

@Suite("Sharpness release integration")
struct ReleaseSharpnessTest {
    @Test(.enabled(if: ProcessInfo.processInfo.environment["RAWCULL_RELEASE_SHARPNESS_RUN"] == "1"))
    func `analyze catalog`() async throws {
        let config = ReleaseRunConfiguration(environment: ProcessInfo.processInfo.environment)
        let files = try ReleaseRunConfiguration.discoverARWFiles(in: config.directory)
        try #require(!files.isEmpty, "No regular ARW files found in \(config.directory.path)")
        let reportURL = config.directory.appendingPathComponent("RawCull-Sharpness-\(UUID().uuidString).md")
        var report = ReleaseSharpnessReport(directory: config.directory, files: files)
        try report.write(to: reportURL)
        print("Sharpness: \(files.count) ARW files. Report: \(reportURL.path)")
        let adapter = RawCullPhotoAnalysisAdapter()
        do {
            for (index, url) in files.enumerated() {
                try Task.checkCancellation()
                print("Sharpness [\(index + 1)/\(files.count)]: \(url.lastPathComponent)")
                let metadata = await RawParserKitImageLoader.shared.fileMetadata(for: url)
                for scenario in ReleaseSharpnessScenario.all {
                    try Task.checkCancellation()
                    let started = Date()
                    do {
                        guard FileManager.default.isReadableFile(atPath: url.path) else {
                            throw ReleaseRunError.message("ARW file is not readable: \(url.path)")
                        }
                        let request = RawCullPhotoAnalysisRequest(
                            id: url,
                            file: RawCullPhotoAnalysisFile(
                                url: url,
                                iso: metadata?.exifMetadata.isoValue ?? 400,
                                aperture: metadata?.exifMetadata.apertureValue,
                                normalizedAFPoint: scenario.useAF ? metadata?.focusPoint : nil,
                            ),
                        )
                        let results = await adapter.analyzeBatch(
                            requests: [request], configuration: scenario.configuration,
                            maximumPixelSize: scenario.pixelSize, source: scenario.source,
                            maximumConcurrentTasks: 1,
                        )
                        guard let results, results.count == 1, let result = results.first,
                              result.id == url, let breakdown = result.breakdown
                        else {
                            throw ReleaseRunError.message("Decode or scoring failed to return one matching breakdown")
                        }
                        report.entries.append(.init(
                            file: url, scenario: scenario, metadata: metadata, breakdown: breakdown,
                            error: nil, elapsed: Date().timeIntervalSince(started),
                        ))
                    } catch {
                        report.entries.append(.init(
                            file: url, scenario: scenario, metadata: metadata, breakdown: nil,
                            error: error.localizedDescription, elapsed: Date().timeIntervalSince(started),
                        ))
                    }
                    // Persist each comparison, including failures, before continuing.
                    try report.write(to: reportURL)
                    print("Sharpness: \(scenario.name): \(report.entries.last?.succeeded == true ? "passed" : "failed")")
                }
            }
        } catch {
            report.runError = error.localizedDescription
        }
        report.finished = Date()
        try report.write(to: reportURL)
        print("Sharpness report saved: \(reportURL.path)")
        #expect(report.runError == nil, "\(report.runError ?? "") — see \(reportURL.path)")
        #expect(report.entries.count == files.count * ReleaseSharpnessScenario.all.count,
                "Every photo and scenario must be analyzed; see \(reportURL.path)")
        for entry in report.entries {
            #expect(entry.succeeded,
                    "\(entry.file.lastPathComponent), \(entry.scenario.name): \(entry.error ?? "invalid numeric output") — see \(reportURL.path)")
        }
    }

    @Test func `report preserves failures missing evidence and pending comparisons`() {
        let file = URL(fileURLWithPath: "/tmp/a|b.ARW")
        let scenario = ReleaseSharpnessScenario.all[0]
        var report = ReleaseSharpnessReport(directory: file.deletingLastPathComponent(), files: [file])
        let breakdown = SharpnessBreakdown(
            finalScore: 0, globalScore: 1, subjectScore: nil, afPointScore: nil,
            blurGateSigma: 0, subjectLabel: nil, subjectConfidence: nil, focusFailureKind: .none,
        )
        let entry = ReleaseSharpnessReport.Entry(
            file: file, scenario: scenario, metadata: nil, breakdown: breakdown, error: nil, elapsed: 1,
        )
        #expect(entry.succeeded, "Zero scores and unavailable evidence are legitimate outcomes")
        report.entries = [entry, .init(
            file: file, scenario: ReleaseSharpnessScenario.all[1], metadata: nil,
            breakdown: nil, error: "Decode failed", elapsed: 1,
        )]
        report.finished = Date()
        let content = report.markdown
        #expect(content.contains("Status: Failed"))
        #expect(content.contains("a\\|b.ARW"))
        #expect(content.contains("Decode failed"))
        #expect(content.contains("Not analyzed"))
        #expect(content.contains("unavailable"))
        #expect(content.contains("ISO unavailable (400 fallback)"))
    }

    @Test func `summary distinguishes ranking changes from larger scores`() {
        let files = ["a.ARW", "b.ARW", "c.ARW"].map { URL(fileURLWithPath: "/tmp/" + $0) }
        var report = ReleaseSharpnessReport(directory: URL(fileURLWithPath: "/tmp"), files: files)
        for scenario in ReleaseSharpnessScenario.all {
            for (index, file) in files.enumerated() {
                var score = Float(3 - index)
                if scenario.quality == .highPrecision {
                    score *= 10
                }
                if scenario.quality == .fast {
                    score = [2, 3, 1][index]
                }
                if scenario.source == .rawDemosaic {
                    score = [2, 2, 1][index]
                }
                let breakdown = SharpnessBreakdown(
                    finalScore: score, globalScore: 1, subjectScore: 1, afPointScore: nil,
                    blurGateSigma: 0, subjectLabel: nil, subjectConfidence: nil, focusFailureKind: .none,
                    focusEvidence: FocusEvidence(winningRegion: .saliency, saliencyCandidateCount: 1),
                )
                report.entries.append(.init(
                    file: file, scenario: scenario, metadata: nil, breakdown: breakdown,
                    error: nil, elapsed: 0,
                ))
            }
        }
        report.finished = Date()
        let summary = report.summary.joined(separator: "\n")
        #expect(summary.contains("All 33 comparisons across 3 photos"))
        #expect(summary.contains("High Precision quality | Same ordering, including ties"))
        #expect(summary.contains("Fast quality | 1 reversed pair; 0 tie changes"))
        #expect(summary.contains("RAW decoding | 0 reversed pairs; 1 tie change"))
        #expect(summary.contains("AF sensitivity cannot be evaluated yet"))
        #expect(summary.contains("not directly exercised by the baseline"))
        #expect(summary.contains("A / B / tie / uncertain"))
        #expect(summary.contains("photographic accuracy still needs your visual judgment"))
        report.entries.removeLast()
        let incomplete = report.summary.joined(separator: "\n")
        #expect(incomplete.contains("run is incomplete or has failures"))
        #expect(incomplete.contains("Finish the run and resolve failed comparisons first"))
        #expect(incomplete.contains("Insufficient complete results"))
    }

    @Test(arguments: [Float.nan, Float.infinity, -Float.infinity, -1])
    func `rejects invalid scores`(score: Float) {
        let breakdown = SharpnessBreakdown(
            finalScore: score, globalScore: 1, subjectScore: nil, afPointScore: nil,
            blurGateSigma: 0, subjectLabel: nil, subjectConfidence: nil, focusFailureKind: .none,
        )
        let entry = ReleaseSharpnessReport.Entry(
            file: URL(fileURLWithPath: "/tmp/photo.ARW"), scenario: ReleaseSharpnessScenario.all[0],
            metadata: nil, breakdown: breakdown, error: nil, elapsed: 0,
        )
        #expect(!entry.succeeded)
    }
}

/// Change one input at a time relative to Wildlife / Balanced / 1024 / Preview / metadata AF.
nonisolated struct ReleaseSharpnessScenario {
    let photoType: SharpnessPhotoType
    var quality: SharpnessScoringQuality = .balanced
    var pixelSize: Int = 1024
    var source: SharpnessScoringSource = .embeddedPreview
    var useAF = true

    var name: String {
        "\(photoType.title) / \(quality.title) / \(pixelSize) px / \(source.title) / \(useAF ? "metadata AF" : "AF removed")"
    }

    var configuration: SharpnessConfiguration {
        quality.packageQuality.applying(to: photoType.packagePreset.applying(to: .birdsInFlight))
    }

    static var all: [Self] {
        SharpnessPhotoType.allCases.map { Self(photoType: $0) } + [
            Self(photoType: .birdsWildlife, useAF: false),
            Self(photoType: .landscape, useAF: false),
            Self(photoType: .birdsWildlife, quality: .fast),
            Self(photoType: .birdsWildlife, quality: .highPrecision),
            Self(photoType: .birdsWildlife, pixelSize: 2048),
            Self(photoType: .birdsWildlife, source: .rawDemosaic)
        ]
    }
}

/// Opt-in dataset export for Scripts/CompareAFSharpness.py. Production runs on the
/// full decoded frame: cropping before its Gaussian filter would change the score.
extension ReleaseSharpnessTest {
    @Test(.enabled(if: ProcessInfo.processInfo.environment["RAWCULL_AF_COMPARISON_RUN"] == "1"))
    func `export AF comparison dataset`() async throws {
        let run = ReleaseRunConfiguration(environment: ProcessInfo.processInfo.environment)
        let files = try ReleaseRunConfiguration.discoverARWFiles(in: run.directory)
        try #require(!files.isEmpty)
        let output = run.directory.appendingPathComponent("AF-Comparison-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        let pins = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("RawCull.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved")
        try Data(contentsOf: pins).write(to: output.appendingPathComponent("Package.resolved"))
        let scenario = ReleaseSharpnessScenario(photoType: .birdsWildlife)
        let analyzer = PhotoAnalyzer()
        let context = CIContext(options: [.workingColorSpace: NSNull(), .workingFormat: CIFormat.RGBAf])
        var records: [[String: Any]] = []
        for (index, file) in files.enumerated() {
            try Task.checkCancellation()
            let id = String(format: "image-%04d", index + 1)
            var record: [String: Any] = ["id": id, "file": file.lastPathComponent]
            do {
                let metadata = await RawParserKitImageLoader.shared.fileMetadata(for: file)
                guard let point = metadata?.focusPoint,
                      point.x.isFinite, point.y.isFinite,
                      (0 ... 1).contains(point.x), (0 ... 1).contains(point.y),
                      let image = await RawParserKitImageLoader.shared.thumbnailCGImage(
                          for: file, maxPixelSize: scenario.pixelSize,
                      )
                else { throw ReleaseRunError.message("Missing valid AF point or preview") }
                let result = await analyzer.analyze(PhotoAnalysisInput(
                    image: image, iso: metadata?.exifMetadata.isoValue ?? 400,
                    aperture: metadata?.exifMetadata.apertureValue, normalizedAFPoint: point,
                ), configuration: scenario.configuration)
                guard let score = result.breakdown?.focusEvidence?.afCenterScore,
                      score.isFinite, score >= 0
                else { throw ReleaseRunError.message("Production AF-center evidence unavailable") }

                // Match package normalizeToSRGB and analyzeRegion's truncating bounds.
                let colorSpace = try #require(CGColorSpace(name: CGColorSpace.sRGB))
                let bitmap = try #require(CGContext(data: nil, width: image.width, height: image.height,
                                                    bitsPerComponent: 8, bytesPerRow: 0, space: colorSpace,
                                                    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
                bitmap.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
                let normalized = try #require(bitmap.makeImage())
                let ci = CIImage(cgImage: normalized)
                var pixels = [UInt8](repeating: 0, count: image.width * image.height * 4)
                context.render(ci, toBitmap: &pixels, rowBytes: image.width * 4,
                               bounds: ci.extent, format: .RGBA8, colorSpace: nil)
                let r = CGFloat(scenario.configuration.afCenterRegionRadius)
                let region = CGRect(x: point.x - r, y: 1 - point.y - r, width: 2 * r, height: 2 * r)
                    .intersection(CGRect(x: 0, y: 0, width: 1, height: 1))
                let x0 = max(0, Int(region.minX * CGFloat(image.width)))
                let x1 = min(image.width, Int(region.maxX * CGFloat(image.width)))
                let y0 = max(0, Int((1 - region.maxY) * CGFloat(image.height)))
                let y1 = min(image.height, Int((1 - region.minY) * CGFloat(image.height)))
                guard x1 - x0 >= 3, y1 - y0 >= 3, (x1 - x0) * (y1 - y0) >= 16 else {
                    throw ReleaseRunError.message("AF crop too small")
                }
                var crop = [UInt8]()
                for row in y0 ..< y1 {
                    crop.append(contentsOf: pixels[(row * image.width + x0) * 4 ..< (row * image.width + x1) * 4])
                }
                let provider = try #require(CGDataProvider(data: Data(crop) as CFData))
                let cropped = try #require(CGImage(width: x1 - x0, height: y1 - y0,
                                                   bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: (x1 - x0) * 4,
                                                   space: colorSpace, bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
                                                   provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent))
                let cropName = id + ".png"
                let destination = try #require(CGImageDestinationCreateWithURL(
                    output.appendingPathComponent(cropName) as CFURL, UTType.png.identifier as CFString, 1, nil,
                ))
                CGImageDestinationAddImage(destination, cropped, nil)
                guard CGImageDestinationFinalize(destination) else { throw ReleaseRunError.message("PNG export failed") }
                record["crop"] = cropName
                record["rawcull"] = score
                record["af_rect"] = [x0, y0, x1 - x0, y1 - y0]
                record["iso"] = metadata?.exifMetadata.isoValue
            } catch {
                record["error"] = error.localizedDescription
            }
            records.append(record)
            let manifest: [String: Any] = ["schema": 1, "scenario": scenario.name,
                                           "images": records, "complete": index == files.count - 1]
            try JSONSerialization.data(withJSONObject: manifest, options: [.prettyPrinted, .sortedKeys])
                .write(to: output.appendingPathComponent("manifest.json"), options: .atomic)
        }
        print("AF comparison dataset: \(output.path)")
        #expect(records.contains { $0["rawcull"] != nil }, "No usable AF crops; see manifest.json")
    }
}
