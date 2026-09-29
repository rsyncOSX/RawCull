import Foundation
import PhotoAnalysisKit

nonisolated struct ReleaseSharpnessReport {
    struct Entry {
        let file: URL
        let scenario: ReleaseSharpnessScenario
        let metadata: RawImageFileMetadata?
        let breakdown: SharpnessBreakdown?
        let error: String?
        let elapsed: Double

        var succeeded: Bool {
            guard error == nil, let breakdown else { return false }
            let scores = [breakdown.finalScore, breakdown.globalScore, breakdown.subjectScore,
                          breakdown.afPointScore, breakdown.blurGateSigma,
                          breakdown.focusEvidence?.scoringAFLocalPatchScore,
                          breakdown.focusEvidence?.scoringSubjectInteriorPatchScore,
                          breakdown.focusEvidence?.scoringLocalDetailScore].compactMap { $0 }
            return scores.allSatisfy { $0.isFinite && $0 >= 0 }
        }
    }

    let directory: URL
    let files: [URL]
    let started = Date()
    var finished: Date?
    var entries: [Entry] = []
    var runError: String?

    func write(to url: URL) throws {
        try markdown.write(to: url, atomically: true, encoding: .utf8)
    }

    var markdown: String {
        let scenarios = ReleaseSharpnessScenario.all
        let expectedCount = files.count * scenarios.count
        let passed = runError == nil && expectedCount > 0 && entries.count == expectedCount && entries.allSatisfy(\.succeeded)
        var lines = [
            "# RawCull sharpness release test", "",
            "- Status: \(finished == nil ? "Running" : (passed ? "Passed" : "Failed"))",
            "- Started: \(started.ISO8601Format())",
            "- Finished: \(finished?.ISO8601Format() ?? "Pending")",
            "- Catalog: \(Self.text(directory.path))",
            "- Build configuration: Release; hostless runner; fresh scores without production caches",
            "- Files: \(files.count); scenarios per file: \(scenarios.count); completed: \(entries.count)/\(expectedCount); failed: \(entries.filter { !$0.succeeded }.count)",
            "", "Baseline: Wildlife / Balanced / 1024 px / Embedded Preview / metadata AF. Each comparison changes one input. Metadata AF uses the real point when available; absent AF is not fabricated. AF-removed comparisons use the same source, size, ISO, aperture, and scoring configuration. Auto preserves the birdsInFlight base configuration.",
            "", "Scores are relative detail measurements, not absolute focus quality. Zero scores and unavailable subject/AF evidence are valid. Success checks completion and finite nonnegative numeric output. This catalog has no expert ranking labels, so this run cannot prove ranking accuracy, diagnose sharp-background mistakes, or prove High Precision is better. Missing evidence, fallback suppression, AF sensitivity, and source/scale/quality changes require photographic review (see Docs/sharpness-scoring-review-2026-09-28.md). ISO and aperture are observed, not manipulated. Focus diagnostics use broad saliency/AF evidence, not the blended subject score. The scalar facade may leave confidence and mask-only diagnostics unavailable; no mask is rendered.",
            "", "## Algorithm and configurations", "",
        ]
        for scenario in scenarios {
            let descriptor = PhotoAnalyzer.sharpnessDescriptor(for: scenario.configuration)
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.sortedKeys]
            let identity = (try? encoder.encode(descriptor)).flatMap { String(data: $0, encoding: .utf8) } ?? "unavailable"
            lines += ["- \(Self.text(scenario.name)): `\(identity)`"]
        }
        if let runError { lines += ["", "## Run error", "", Self.text(runError)] }
        for file in files {
            let metadata = entries.first { $0.file == file }?.metadata
            let exif = metadata?.exifMetadata
            let iso = exif?.isoValue.map { String($0) } ?? "unavailable (400 fallback)"
            let aperture = exif?.apertureValue.map { String($0) } ?? "unavailable"
            let af = metadata?.focusPoint.map { "x=\($0.x), y=\($0.y)" } ?? "unavailable"
            lines += ["", "## \(Self.text(file.lastPathComponent))", "",
                      "- ISO \(iso); aperture \(aperture); metadata AF: \(af)", "",
                      "| Scenario | Status | Final | Global | Subject | Broad AF | AF local | Subject interior | Local detail | Final/global | Sigma | Candidates | Evidence region | Confidence | Focus diagnostic | Seconds |",
                      "| --- | --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | --- | --- | --- | ---: |"]
            for scenario in scenarios {
                guard let entry = entries.first(where: { $0.file == file && $0.scenario.name == scenario.name }) else {
                    lines.append("| \(Self.text(scenario.name)) | Not analyzed | — | — | — | — | — | — | — | — | — | — | — | — | — | — |")
                    continue
                }
                let b = entry.breakdown
                let e = b?.focusEvidence
                let ratio = b.flatMap { b in b.globalScore.flatMap { $0 > 0 ? b.finalScore / $0 : nil } }
                lines.append("| \(Self.text(scenario.name)) | \(entry.succeeded ? "Passed" : "Failed") | \(Self.number(b?.finalScore)) | \(Self.number(b?.globalScore)) | \(Self.number(b?.subjectScore)) | \(Self.number(b?.afPointScore)) | \(Self.number(e?.scoringAFLocalPatchScore)) | \(Self.number(e?.scoringSubjectInteriorPatchScore)) | \(Self.number(e?.scoringLocalDetailScore)) | \(Self.number(ratio)) | \(Self.number(b?.blurGateSigma)) | \(e.map { String($0.saliencyCandidateCount) } ?? "unavailable") | \(e?.winningRegion.rawValue ?? "unavailable") | \(e?.focusEvidenceConfidence?.rawValue ?? "unavailable") | \(b?.focusFailureKind.rawValue ?? "unavailable") | \(String(format: "%.2f", entry.elapsed)) |")
            }
            for entry in entries where entry.file == file {
                if let error = entry.error {
                    lines += ["", "Error (\(Self.text(entry.scenario.name))): \(Self.text(error))"]
                }
            }
            lines += ["", "### Subject evidence", ""]
            for entry in entries where entry.file == file {
                guard let b = entry.breakdown else { continue }
                let e = b.focusEvidence
                lines += ["- \(Self.text(entry.scenario.name)): subject \(Self.text(b.subjectLabel ?? "unavailable")), confidence \(Self.number(b.subjectConfidence)); winning saliency rect \(Self.text(e?.winningSaliencyRect.map { String(describing: $0) } ?? "unavailable")); selection \(Self.text(e?.saliencySelectionReason ?? "unavailable")); evidence \(Self.text(e?.focusEvidenceConfidenceReason ?? "unavailable")); configured silhouette penalty strength \(Self.number(entry.scenario.configuration.silhouettePenaltyStrength))."]
            }
        }
        lines += ["", "## Catalog rankings", "", "Rankings use unnormalized final scores within each scenario. They require expert review; ordering alone is not a test assertion."]
        for scenario in scenarios {
            let ranked = entries.filter { $0.scenario.name == scenario.name && $0.succeeded }
                .sorted {
                    let left = $0.breakdown?.finalScore ?? 0
                    let right = $1.breakdown?.finalScore ?? 0
                    return left == right ? $0.file.lastPathComponent < $1.file.lastPathComponent : left > right
                }
            lines += ["", "### \(Self.text(scenario.name))", ""]
            for (index, entry) in ranked.enumerated() {
                lines.append("\(index + 1). \(Self.text(entry.file.lastPathComponent)): \(Self.number(entry.breakdown?.finalScore))")
            }
            if ranked.isEmpty { lines.append("No valid scores available.") }
        }
        return lines.joined(separator: "\n") + "\n"
    }

    private static func number(_ value: Float?) -> String {
        value.map { String(format: "%.6f", $0) } ?? "unavailable"
    }
    private static func text(_ value: String) -> String { ReleaseAnalysisReport.text(value) }
}
