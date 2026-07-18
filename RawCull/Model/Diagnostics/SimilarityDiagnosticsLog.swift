import Foundation
import PhotoAIContracts

nonisolated enum SimilarityDiagnosticsOutcome: Equatable, Sendable {
    case visionFallback(
        artifactsCreated: Int,
        clipFailures: [RawCullCLIPPrimaryFailure],
        visionFailures: [RawCullSimilarityIndexingFailure],
        validationFailures: [RawCullSimilarityIndexingFailure],
    )
    case indexingFailure(message: String)
}

nonisolated struct SimilarityDiagnosticsEvent: Equatable, Sendable {
    let timestamp: Date
    let backend: SimilarityBackendDescriptor
    let requestedImageCount: Int
    let thumbnailMaxPixelSize: Int
    let summary: String?
    let outcome: SimilarityDiagnosticsOutcome
}

nonisolated protocol SimilarityDiagnosticsWriting: Sendable {
    func record(_ event: SimilarityDiagnosticsEvent) async throws
}

nonisolated enum SimilarityDiagnosticsLogError: Error, Equatable, Sendable {
    case invalidUTF8
}

actor SimilarityDiagnosticsLog: SimilarityDiagnosticsWriting {
    static let shared = SimilarityDiagnosticsLog()

    nonisolated let fileURL: URL

    private static let maximumLogBytes = 5 * 1024 * 1024

    init(fileURL: URL? = nil) {
        self.fileURL = fileURL ?? Self.defaultLogURL()
    }

    func record(_ event: SimilarityDiagnosticsEvent) async throws {
        let directory = fileURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true,
        )

        let entryData = Data(format(event).utf8)
        if shouldReplaceExistingLog() {
            try entryData.write(to: fileURL, options: .atomic)
            return
        }
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            try entryData.write(to: fileURL, options: .atomic)
            return
        }

        let handle = try FileHandle(forWritingTo: fileURL)
        defer { try? handle.close() }
        try handle.seekToEnd()
        try handle.write(contentsOf: entryData)
    }

    func contents() throws -> String {
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            return ""
        }
        let data = try Data(contentsOf: fileURL)
        guard let contents = String(bytes: data, encoding: .utf8) else {
            throw SimilarityDiagnosticsLogError.invalidUTF8
        }
        return contents
    }

    func clear() throws {
        let directory = fileURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true,
        )
        try Data().write(to: fileURL, options: .atomic)
    }

    private func shouldReplaceExistingLog() -> Bool {
        guard let attributes = try? FileManager.default.attributesOfItem(
            atPath: fileURL.path,
        ), let size = attributes[.size] as? NSNumber else {
            return false
        }
        return size.intValue >= Self.maximumLogBytes
    }

    private func format(_ event: SimilarityDiagnosticsEvent) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]

        var lines: [String] = []
        lines.append(String(repeating: "=", count: 80))
        lines.append("Timestamp: \(formatter.string(from: event.timestamp))")
        lines.append("Requested images: \(event.requestedImageCount)")
        lines.append("Thumbnail maximum pixel size: \(event.thumbnailMaxPixelSize)")
        lines.append("CLIP backend: \(event.backend.backend)")
        lines.append("Model fingerprint: \(event.backend.modelFingerprint)")
        lines.append("Representation: \(event.backend.representation)")
        lines.append("Preprocessing: \(event.backend.preprocessingVersion)")
        lines.append("Normalization: \(event.backend.normalizationVersion)")
        lines.append("Configuration: \(event.backend.configurationVersion)")
        if let summary = event.summary {
            lines.append("Summary: \(summary)")
        }

        switch event.outcome {
        case let .visionFallback(
            artifactsCreated,
            clipFailures,
            visionFailures,
            validationFailures,
        ):
            lines.append("Outcome: CLIP failed; used whole-batch Vision fallback")
            lines.append("Artifacts created by fallback: \(artifactsCreated)")
            appendCLIPFailures(clipFailures, to: &lines)
            appendFailures(
                visionFailures,
                heading: "Vision fallback generation failures",
                to: &lines,
            )
            appendFailures(
                validationFailures,
                heading: "Artifact validation failures",
                to: &lines,
            )

        case let .indexingFailure(message):
            lines.append("Outcome: CLIP indexing operation failed")
            lines.append("Reason: \(message)")
        }

        lines.append("")
        return lines.joined(separator: "\n")
    }

    private func appendCLIPFailures(
        _ failures: [RawCullCLIPPrimaryFailure],
        to lines: inout [String],
    ) {
        lines.append("CLIP image failures (\(failures.count)):")
        guard !failures.isEmpty else {
            lines.append("  No image-level primary failure was captured.")
            return
        }

        for (index, failure) in failures.enumerated() {
            lines.append("  \(index + 1). Image: \(failure.source.displayName)")
            lines.append("     URL: \(failure.source.url.path)")
            lines.append("     Stage: \(failure.stage.rawValue)")
            lines.append("     Reason: \(failure.message)")
        }
    }

    private func appendFailures(
        _ failures: [RawCullSimilarityIndexingFailure],
        heading: String,
        to lines: inout [String],
    ) {
        lines.append("\(heading) (\(failures.count)):")
        for (index, failure) in failures.enumerated() {
            lines.append("  \(index + 1). Image: \(failure.source.displayName)")
            lines.append("     URL: \(failure.source.url.path)")
            lines.append("     Reason: \(failure.message)")
        }
    }

    private nonisolated static func defaultLogURL() -> URL {
        RawCullAIPaths.live().applicationSupportDirectory
            .appendingPathComponent("Diagnostics", isDirectory: true)
            .appendingPathComponent("Similarity.log", isDirectory: false)
    }
}
