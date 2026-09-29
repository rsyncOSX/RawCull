import Foundation
import PhotoAnalysisKit
import Testing

@Suite("Sharpness release integration")
struct ReleaseSharpnessTest {
    @Test(.enabled(if: ProcessInfo.processInfo.environment["RAWCULL_RELEASE_SHARPNESS_RUN"] == "1"))
    func analyzeCatalog() async throws {
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
                                normalizedAFPoint: scenario.useAF ? metadata?.focusPoint : nil
                            )
                        )
                        let results = await adapter.analyzeBatch(
                            requests: [request], configuration: scenario.configuration,
                            maximumPixelSize: scenario.pixelSize, source: scenario.source,
                            maximumConcurrentTasks: 1
                        )
                        guard let results, results.count == 1, let result = results.first,
                              result.id == url, let breakdown = result.breakdown else {
                            throw ReleaseRunError.message("Decode or scoring failed to return one matching breakdown")
                        }
                        report.entries.append(.init(
                            file: url, scenario: scenario, metadata: metadata, breakdown: breakdown,
                            error: nil, elapsed: Date().timeIntervalSince(started)
                        ))
                    } catch {
                        report.entries.append(.init(
                            file: url, scenario: scenario, metadata: metadata, breakdown: nil,
                            error: error.localizedDescription, elapsed: Date().timeIntervalSince(started)
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

    @Test func reportPreservesFailuresMissingEvidenceAndPendingComparisons() throws {
        let file = URL(fileURLWithPath: "/tmp/a|b.ARW")
        let scenario = ReleaseSharpnessScenario.all[0]
        var report = ReleaseSharpnessReport(directory: file.deletingLastPathComponent(), files: [file])
        let breakdown = SharpnessBreakdown(
            finalScore: 0, globalScore: 1, subjectScore: nil, afPointScore: nil,
            blurGateSigma: 0, subjectLabel: nil, subjectConfidence: nil, focusFailureKind: .none
        )
        let entry = ReleaseSharpnessReport.Entry(
            file: file, scenario: scenario, metadata: nil, breakdown: breakdown, error: nil, elapsed: 1
        )
        #expect(entry.succeeded, "Zero scores and unavailable evidence are legitimate outcomes")
        report.entries = [entry, .init(
            file: file, scenario: ReleaseSharpnessScenario.all[1], metadata: nil,
            breakdown: nil, error: "Decode failed", elapsed: 1
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

    @Test(arguments: [Float.nan, Float.infinity, -Float.infinity, -1])
    func rejectsInvalidScores(score: Float) {
        let breakdown = SharpnessBreakdown(
            finalScore: score, globalScore: 1, subjectScore: nil, afPointScore: nil,
            blurGateSigma: 0, subjectLabel: nil, subjectConfidence: nil, focusFailureKind: .none
        )
        let entry = ReleaseSharpnessReport.Entry(
            file: URL(fileURLWithPath: "/tmp/photo.ARW"), scenario: ReleaseSharpnessScenario.all[0],
            metadata: nil, breakdown: breakdown, error: nil, elapsed: 0
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
            Self(photoType: .birdsWildlife, source: .rawDemosaic),
        ]
    }
}
