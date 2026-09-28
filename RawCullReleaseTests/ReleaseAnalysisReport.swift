import Foundation

nonisolated struct ReleaseAnalysisReport {
    struct Entry {
        let file: URL
        let result: ObjectPhotoAnalysisResult?
        let error: String?
        let elapsed: Double

        var succeeded: Bool {
            guard error == nil, let result, result.isSuccessful, !result.concepts.isEmpty,
                  result.sam3ModelIdentity != nil else { return false }
            // No retained objects is a valid production outcome. Assessment is then inapplicable.
            if result.instances.isEmpty { return result.assessment == nil }
            guard let assessment = result.assessment else { return false }
            return Set(assessment.objects.map(\.id)) == Set(result.instances.map(\.id))
        }
    }

    let directory: URL
    let files: [URL]
    let started = Date()
    var finished: Date?
    var qwenPath: String?
    var samPath: String?
    var qwenName: String?
    var samIdentity: String?
    var entries: [Entry] = []
    var runError: String?

    func write(to url: URL) throws {
        try markdown.write(to: url, atomically: true, encoding: .utf8)
    }

    var markdown: String {
        var lines = [
            "# RawCull AI Objects release test", "",
            "- Status: \(finished == nil ? "Running" : (passed ? "Passed" : "Failed"))",
            "- Started: \(started.ISO8601Format())",
            "- Finished: \(finished?.ISO8601Format() ?? "Pending")",
            "- Catalog: \(Self.text(directory.path))",
            "- Build configuration: Release; hostless runner",
            "- Discovery: automatic; image maximum side: 4320; at most 6 concepts and 8 retained objects per photo",
            "- Qwen: \(Self.text(qwenName ?? "Not validated"))",
            "- Qwen bundle: \(Self.text(qwenPath ?? "Not resolved"))",
            "- SAM 3 identity: \(Self.text(samIdentity ?? "Not validated"))",
            "- SAM 3 bundle: \(Self.text(samPath ?? "Not resolved"))",
            "- Files: \(files.count); completed: \(entries.count); passed: \(entries.filter(\.succeeded).count); failed: \(entries.filter { !$0.succeeded }.count)",
            "", "The pipeline decodes each ARW preview, discovers concepts with Qwen, segments them with SAM 3, deduplicates instances, prepares a numbered crop board, and assesses retained objects with Qwen. Zero retained objects is reported explicitly; crop preparation and assessment are then inapplicable. This test checks completion and structured output, not the factual accuracy of AI descriptions.", "",
        ]
        if let runError { lines += ["## Run error", "", Self.text(runError), ""] }
        lines += ["## File summary", "", "| File | Status | Concepts | Objects | Seconds |", "| --- | --- | --- | ---: | ---: |"]
        for file in files {
            if let entry = entries.first(where: { $0.file == file }) {
                lines.append("| \(Self.text(file.lastPathComponent)) | \(entry.succeeded ? "Passed" : "Failed") | \(Self.list(entry.result?.concepts ?? [])) | \(entry.result?.instances.count ?? 0) | \(Self.seconds(entry.elapsed)) |")
            } else {
                lines.append("| \(Self.text(file.lastPathComponent)) | Not analyzed | — | — | — |")
            }
        }
        for entry in entries {
            lines += ["", "## \(Self.text(entry.file.lastPathComponent))", "", "- Status: \(entry.succeeded ? "Passed" : "Failed")", "- Total seconds: \(Self.seconds(entry.elapsed))"]
            if let error = entry.error { lines += ["- Error: \(Self.text(error))"] }
            guard let result = entry.result else { continue }
            lines += ["- Source bytes: \(result.sourceSize); modified: \(result.sourceModified.ISO8601Format())", "- Concepts: \(Self.list(result.concepts))", "- Raw instances: \(result.rawInstanceCount); retained instances: \(result.instances.count)", "- Stage seconds: discovery \(Self.seconds(result.timings.conceptDiscoverySeconds)), segmentation \(Self.seconds(result.timings.segmentationSeconds)), board \(Self.seconds(result.timings.boardRenderingSeconds)), assessment \(Self.seconds(result.timings.assessmentSeconds))"]
            if let failure = result.failure { lines.append("- Error: \(Self.text(failure))") }
            if result.instances.isEmpty { lines.append("- No retained objects; board and assessment inapplicable.") }
            for instance in result.instances {
                let box = instance.normalizedBoundingBox
                lines += ["", "### Object \(Self.text(instance.id)): \(Self.text(instance.concept))", "", "- SAM score: \(instance.score)", "- Aliases: \(Self.list(instance.aliases))", "- Normalized bounding box (bottom-left origin): x=\(box.minX), y=\(box.minY), width=\(box.width), height=\(box.height)"]
                if let object = result.assessment?.objects.first(where: { $0.id == instance.id }) {
                    lines += ["- Assessed concept: \(Self.text(object.concept))", "- Description: \(Self.text(object.description))", "- Visibility: \(object.visibility.rawValue)", "- Focus: \(object.focusQuality.rawValue)", "- Expression: \(Self.text(object.expression ?? "Not applicable"))", "- Obstructions: \(Self.list(object.obstructions))", "- Strengths: \(Self.list(object.strengths))", "- Problems: \(Self.list(object.problems))", "- Confidence: \(object.confidence)"]
                }
            }
            if let assessment = result.assessment {
                lines += ["", "### Photo assessment", "", "- Summary: \(Self.text(assessment.imageSummary ?? "Not provided"))", "- Relationships: \(Self.list(assessment.relationships))", "- Strengths: \(Self.list(assessment.strengths))", "- Problems: \(Self.list(assessment.problems))", "- Preferred object IDs: \(Self.list(assessment.preferredObjectIDs))", "- Confidence: \(assessment.confidence)"]
            }
            if let raw = result.freeformResponse { lines += ["", "### Unparsed Qwen assessment", "", Self.text(raw)] }
        }
        return lines.joined(separator: "\n") + "\n"
    }

    private var passed: Bool { runError == nil && entries.count == files.count && !files.isEmpty && entries.allSatisfy(\.succeeded) }
    private static func seconds(_ value: Double) -> String { String(format: "%.2f", value) }
    private static func list(_ values: [String]) -> String { values.isEmpty ? "None" : values.map(text).joined(separator: "; ") }
    static func text(_ value: String) -> String {
        var value = value.replacingOccurrences(of: "\r\n", with: " ").replacingOccurrences(of: "\n", with: " ").replacingOccurrences(of: "\r", with: " ")
        for character in ["\\", "`", "*", "_", "[", "]", "<", ">", "#", "|"] {
            value = value.replacingOccurrences(of: character, with: "\\" + character)
        }
        return value
    }
}
