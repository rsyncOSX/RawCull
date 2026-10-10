import Foundation
import PhotoAnalysisKit
import Testing

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
