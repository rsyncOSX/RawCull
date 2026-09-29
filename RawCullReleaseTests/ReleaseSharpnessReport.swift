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
        ]
        lines += summary
        lines += [
            "", "## How the measurements were made", "", "Baseline: Wildlife / Balanced / 1024 px / Embedded Preview / metadata AF. Each comparison changes one input. Metadata AF uses the real point when available; absent AF is not fabricated. AF-removed comparisons use the same source, size, ISO, aperture, and scoring configuration. Auto preserves the birdsInFlight base configuration.",
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

    /// Keep the human interpretation separate from the measurement tables.
    /// No visual correctness or absolute quality is inferred from a numeric score.
    var summary: [String] {
        let expected = files.count * ReleaseSharpnessScenario.all.count
        let valid = entries.filter(\.succeeded).count
        let complete = finished != nil && runError == nil && expected > 0
            && entries.count == expected && valid == expected
        var lines = ["", "## Results in plain language", ""]
        if complete {
            lines.append("All \(expected) comparisons across \(files.count) photos completed with valid numbers. **Passed means the software ran successfully; photographic accuracy still needs your visual judgment.**")
        } else {
            lines.append("\(valid) of \(expected) expected comparisons currently have valid results. \(finished == nil ? "The run is still in progress." : "The run is incomplete or has failures; resolve those before drawing conclusions about the full catalog.") Comparisons below require valid results for every photo in both settings.")
        }

        let baseline = ReleaseSharpnessScenario(photoType: .birdsWildlife)
        let ranked = rankedEntries(for: baseline)
        if ranked.count == files.count, let first = ranked.first, let last = ranked.last {
            lines += ["", "The baseline uses Wildlife, Balanced quality, a 1024 px camera preview, and recorded autofocus (AF) information.", "",
                      "- Highest baseline score: **\(Self.text(first.file.lastPathComponent))** (\(Self.number(first.breakdown?.finalScore))).",
                      "- Lowest baseline score: **\(Self.text(last.file.lastPathComponent))** (\(Self.number(last.breakdown?.finalScore))).",
                      "", "These are inspection candidates, not confirmed sharpest/softest photos. Different subjects, textures, and scenes can affect scores."]
        }

        var reviewFiles: [URL] = []
        var reviewReasons: [URL: [String]] = [:]
        func prioritize(_ file: URL, reason: String) {
            if reviewReasons[file] == nil { reviewFiles.append(file) }
            reviewReasons[file, default: []].append(reason)
        }

        lines += ["", "### Sensitivity to autofocus information", ""]
        for photoType in [SharpnessPhotoType.birdsWildlife, .landscape] {
            let withAF = ReleaseSharpnessScenario(photoType: photoType)
            let withoutAF = ReleaseSharpnessScenario(photoType: photoType, useAF: false)
            let changes: [(file: URL, percent: Double)] = files.compactMap { file in
                guard let original = validEntry(for: file, scenario: withAF),
                      original.metadata?.focusPoint != nil,
                      let a = original.breakdown?.finalScore, a > 0,
                      let b = validEntry(for: file, scenario: withoutAF)?.breakdown?.finalScore else { return nil }
                return (file, 100 * (Double(b) / Double(a) - 1))
            }
            if let largest = changes.max(by: { abs($0.percent) < abs($1.percent) }) {
                let change = String(format: "%.1f", abs(largest.percent))
                let direction = largest.percent < 0 ? "fell" : "rose"
                lines.append("- \(photoType.title): the largest relative change was **\(Self.text(largest.file.lastPathComponent))**; its score \(direction) **\(change)%** when AF information was removed (\(changes.count) photos compared). The pixels were decoded under the same conditions. Check whether the AF point identifies useful subject detail or detail elsewhere; a score change alone does not prove a defect.")
                if largest.percent != 0 {
                    prioritize(largest.file, reason: "\(photoType.title) score \(direction) \(change)% without AF. Check the subject and AF location.")
                }
            } else {
                lines.append("- \(photoType.title): no valid paired comparisons with recorded AF and a positive baseline score are available. AF sensitivity cannot be evaluated yet.")
            }
        }

        lines += ["", "### Does another setting change the choices?", "",
                  "Each row compares photo ordering with the Wildlife baseline. A reversed pair means two photos exchange order; a tie change means equal scores become unequal, or vice versa. Only compare photographs visually as a pair when their subjects/scenes are comparable.", "",
                  "| Change from baseline | Result | How to use it |",
                  "| --- | --- | --- |"]
        let comparisons: [(label: String, scenario: ReleaseSharpnessScenario)] = [
            ("High Precision quality", .init(photoType: .birdsWildlife, quality: .highPrecision)),
            ("Fast quality", .init(photoType: .birdsWildlife, quality: .fast)),
            ("2048 px analysis size", .init(photoType: .birdsWildlife, pixelSize: 2048)),
            ("RAW decoding", .init(photoType: .birdsWildlife, source: .rawDemosaic)),
            ("AF information removed", .init(photoType: .birdsWildlife, useAF: false)),
        ]
        for comparison in comparisons {
            guard files.count >= 2, ranked.count == files.count,
                  rankedEntries(for: comparison.scenario).count == files.count else {
                lines.append("| \(comparison.label) | Insufficient complete results | Wait for valid results for all photos; at least two photos are needed. |")
                continue
            }
            var reversed: [(URL, URL)] = []
            var tieChanges = 0
            for (index, left) in ranked.enumerated() {
                for right in ranked.dropFirst(index + 1) {
                    guard let a = left.breakdown?.finalScore, let b = right.breakdown?.finalScore,
                          let c = validEntry(for: left.file, scenario: comparison.scenario)?.breakdown?.finalScore,
                          let d = validEntry(for: right.file, scenario: comparison.scenario)?.breakdown?.finalScore else { continue }
                    if (a > b && c < d) || (a < b && c > d) { reversed.append((left.file, right.file)) }
                    if (a == b) != (c == d) { tieChanges += 1 }
                }
            }
            if reversed.isEmpty && tieChanges == 0 {
                lines.append("| \(comparison.label) | Same ordering, including ties | No evidence of better photo selection from this ordering alone. |")
            } else {
                let examples = reversed.prefix(3).map { "\(Self.text($0.0.lastPathComponent)) / \(Self.text($0.1.lastPathComponent))" }.joined(separator: "; ")
                let pairCount = "\(reversed.count) reversed \(reversed.count == 1 ? "pair" : "pairs")"
                let tieCount = "\(tieChanges) tie \(tieChanges == 1 ? "change" : "changes")"
                lines.append("| \(comparison.label) | \(pairCount); \(tieCount)\(examples.isEmpty ? "" : ". Examples: " + examples) | Inspect comparable pairs without scores first, then see which setting agrees with your choice. |")
                if let pair = reversed.first {
                    prioritize(pair.0, reason: "Order reverses with \(Self.text(pair.1.lastPathComponent)) under \(comparison.label.lowercased()); compare if scenes match.")
                    prioritize(pair.1, reason: "Order reverses with \(Self.text(pair.0.lastPathComponent)) under \(comparison.label.lowercased()); compare if scenes match.")
                }
            }
        }

        let knownEvidence = ranked.compactMap { $0.breakdown?.focusEvidence?.saliencyCandidateCount }
        let missingCandidates = knownEvidence.filter { $0 == 0 }.count
        lines += ["", "### What this catalog does not establish", ""]
        if knownEvidence.count == files.count && !files.isEmpty && missingCandidates == 0 {
            lines.append("Every baseline photo had at least one detected subject candidate. The review's missing-subject fallback concern is **not directly exercised by the baseline in this catalog**. A detected candidate can still identify the wrong subject.")
        } else {
            lines.append("\(missingCandidates) baseline photos had no detected subject candidates; candidate counts are available for \(knownEvidence.count)/\(files.count) photos. Missing localization is not proof of blur: inspect those photos before treating a low score as softness.")
            for entry in ranked where entry.breakdown?.focusEvidence?.saliencyCandidateCount == 0 {
                prioritize(entry.file, reason: "No baseline subject candidate. Check for a sharp subject that scoring failed to locate.")
            }
        }
        lines += ["", "The run has no human sharpness labels. It cannot measure agreement with a photographer or establish reliability for sharp backgrounds, small subjects, low contrast, motion blur, silhouettes, or high ISO merely because processing passed."]

        if let lowest = ranked.last { prioritize(lowest.file, reason: "Lowest available baseline score. Check whether the intended subject is actually soft.") }
        if let highest = ranked.first { prioritize(highest.file, reason: "Highest available baseline score. Check that detail belongs to the intended subject.") }
        lines += ["", "## Visual check: start here", "",
                  "Use your RAW viewer or RawCull to inspect the original files. This report contains measurements, not image crops. Start with these photos; the list is ordered by review priority.", "",
                  "| Photo | Why inspect it | Your visual judgment |",
                  "| --- | --- | --- |"]
        for file in reviewFiles.prefix(8) {
            lines.append("| \(Self.text(file.lastPathComponent)) | \(reviewReasons[file, default: []].joined(separator: " ")) | Sharp / soft / uncertain; subject or eye checked: ___ |")
        }
        if reviewFiles.isEmpty { lines.append("| No valid review candidates yet | Resolve missing or failed analysis first. | — |") }
        lines += ["",
                  "1. Select two photos from the same burst or scene. Hide their scores before comparing them.",
                  "2. View matching subject crops at 100% zoom, with the same RAW rendering and sharpening settings. For birds, inspect the eye, head, and feather detail. Check background detail separately.",
                  "3. Record A sharper, B sharper, or too close to tell. Judge subject focus separately from pose, exposure, and composition.",
                  "4. Reveal the baseline and alternative rankings. Record which setting agrees with your judgment. A larger number in another setting does not by itself mean a better result.",
                  "5. Save disagreements, especially a soft subject with a sharp background outranking a sharp subject. These examples are the most useful cases for regression tests.",
                  "", "Use this worksheet for comparable pairs:", "",
                  "| Photo A | Photo B | Your choice before seeing scores | Baseline agrees? | Alternative that agrees | Notes on subject/background |",
                  "| --- | --- | --- | --- | --- | --- |",
                  "| ___ | ___ | A / B / tie / uncertain | Yes / No / tie | ___ | ___ |",
                  "", "## Conclusion and next steps", ""]
        if complete {
            lines.append("The execution check passed. Keep the current scoring formula while you validate its photographic choices. Use the baseline as the reference for visual comparisons; this report does not establish an optimal setting or justify automatic rejection of low-scoring photos.")
        } else {
            lines.append("Finish the run and resolve failed comparisons first. Partial results can identify inspection candidates, but they cannot support a conclusion about the complete catalog.")
        }
        lines += ["", "Build a held-out set of human-ranked burst pairs, including the disagreements above and examples of missing subject localization, sharp backgrounds, small birds, low contrast, motion blur, silhouettes, and high ISO. Then compare how often the baseline and each candidate setting pick your preferred subject sharpness, and count severe subject/background mistakes. Change fallback policy or tune coefficients only when those labeled comparisons show an improvement."]
        return lines
    }

    private func validEntry(for file: URL, scenario: ReleaseSharpnessScenario) -> Entry? {
        entries.first { $0.file == file && $0.scenario.name == scenario.name && $0.succeeded }
    }

    private func rankedEntries(for scenario: ReleaseSharpnessScenario) -> [Entry] {
        files.compactMap { validEntry(for: $0, scenario: scenario) }.sorted {
            let left = $0.breakdown?.finalScore ?? 0
            let right = $1.breakdown?.finalScore ?? 0
            return left == right ? $0.file.lastPathComponent < $1.file.lastPathComponent : left > right
        }
    }

    private static func number(_ value: Float?) -> String {
        value.map { String(format: "%.6f", $0) } ?? "unavailable"
    }
    private static func text(_ value: String) -> String { ReleaseAnalysisReport.text(value) }
}
