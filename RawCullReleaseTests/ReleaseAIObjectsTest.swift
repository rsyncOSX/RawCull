import CoreAISAM3Backend
import Foundation
import PhotoAIStorage
import PhotoAIWorkflows
import Testing

@Suite("AI Objects release integration")
struct ReleaseAIObjectsTest {
    @Test func discoversOnlyTopLevelRegularARWFiles() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        for name in ["b.ARW", "a.arw", "other.jpg"] {
            try Data().write(to: directory.appendingPathComponent(name))
        }
        let subdirectory = directory.appendingPathComponent("folder.ARW")
        try FileManager.default.createDirectory(at: subdirectory, withIntermediateDirectories: true)
        try Data().write(to: subdirectory.appendingPathComponent("nested.ARW"))
        #expect(try ReleaseRunConfiguration.discoverARWFiles(in: directory).map(\.lastPathComponent) == ["a.arw", "b.ARW"])
        try FileManager.default.removeItem(at: directory.appendingPathComponent("a.arw"))
        try FileManager.default.removeItem(at: directory.appendingPathComponent("b.ARW"))
        #expect(try ReleaseRunConfiguration.discoverARWFiles(in: directory).isEmpty)
    }

    @Test func reportPreservesFailuresAndUnprocessedFiles() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let first = directory.appendingPathComponent("a|b.ARW")
        let second = directory.appendingPathComponent("pending.ARW")
        var report = ReleaseAnalysisReport(directory: directory, files: [first, second])
        report.entries = [.init(file: first, result: nil, error: "Decode failed", elapsed: 1)]
        report.runError = "Model failure"
        report.finished = Date()
        let url = directory.appendingPathComponent("report.md")
        try report.write(to: url)
        let content = try String(contentsOf: url, encoding: .utf8)
        #expect(content.contains("Status: Failed"))
        #expect(content.contains("a\\|b.ARW | Failed"))
        #expect(content.contains("pending.ARW | Not analyzed"))
        #expect(content.contains("Decode failed"))
        #expect(content.contains("Model failure"))
    }

    @MainActor
    @Test(.enabled(if: ProcessInfo.processInfo.environment["RAWCULL_RELEASE_RUN"] == "1"))
    func analyzeDownloads() async throws {
        let config = ReleaseRunConfiguration(environment: ProcessInfo.processInfo.environment)
        let files = try ReleaseRunConfiguration.discoverARWFiles(in: config.directory)
        try #require(!files.isEmpty, "No regular ARW files found in \(config.directory.path)")
        let reportURL = config.directory.appendingPathComponent(
            "RawCull-AI-Objects-\(UUID().uuidString).md"
        )
        var report = ReleaseAnalysisReport(directory: config.directory, files: files)
        // Verify report access before spending time loading models or running inference.
        try report.write(to: reportURL)
        print("AI Objects: \(files.count) ARW files. Report: \(reportURL.path)")
        let inference = QwenInferenceRuntime()
        do {
            let qwenURL = try config.modelURL(override: config.qwenPath, relativePath: "Qwen/qwen3_vl_2b", option: "RELEASE_QWEN")
            let samURL = try config.modelURL(override: config.samPath, relativePath: "SAM3", option: "RELEASE_SAM3")
            report.qwenPath = qwenURL.path
            report.samPath = samURL.path
            let qwenStatus = await inference.validate(url: qwenURL)
            guard qwenStatus.isAvailable else {
                throw ReleaseRunError.message("Qwen model validation failed: \(qwenStatus)")
            }
            let provider = try CoreAISAM3Provider(modelBundleURL: samURL)
            report.samIdentity = provider.modelIdentity.artifactIdentifier
            if case let .available(_, name) = qwenStatus { report.qwenName = name }
            for (index, url) in files.enumerated() {
                try Task.checkCancellation()
                print("AI Objects [\(index + 1)/\(files.count)]: \(url.lastPathComponent)")
                let started = Date()
                do {
                    let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
                    guard FileManager.default.isReadableFile(atPath: url.path) else {
                        throw ReleaseRunError.message("ARW file is not readable: \(url.path)")
                    }
                    let file = FileItem(
                        id: UUID(), url: url, name: url.lastPathComponent,
                        size: (attributes[.size] as? NSNumber)?.int64Value ?? 0,
                        dateModified: (attributes[.modificationDate] as? Date) ?? .distantPast,
                        exifData: nil, afFocusNormalized: nil
                    )
                    // Each photo gets fresh masks and results; no production disk cache is used.
                    let store = ObjectMaskMemoryStore()
                    let segmentation = try ObjectSegmentationService(provider: provider, stores: [store], maxSide: 4320)
                    let feature = RawCullObjectAnalysisFeature(inference: inference, maskStores: [store])
                    feature.install(segmentation: segmentation, qwenStatus: qwenStatus)
                    guard feature.canRun else { throw ReleaseRunError.message("AI Objects pipeline is not ready") }
                    await feature.analyze([file])
                    guard feature.results.count == 1, let result = feature.results.first,
                          result.fileID == file.id else {
                        throw ReleaseRunError.message("Pipeline did not return exactly one matching result")
                    }
                    report.entries.append(.init(file: url, result: result, error: nil, elapsed: Date().timeIntervalSince(started)))
                } catch {
                    report.entries.append(.init(file: url, result: nil, error: error.localizedDescription, elapsed: Date().timeIntervalSince(started)))
                }
                // Preserve completed photos if the process is interrupted later.
                try report.write(to: reportURL)
                print("AI Objects: \(report.entries.last?.succeeded == true ? "passed" : "failed") — \(url.lastPathComponent)")
            }
        } catch {
            report.runError = error.localizedDescription
        }
        await inference.clear()
        report.finished = Date()
        try report.write(to: reportURL)
        print("AI Objects report saved: \(reportURL.path)")
        #expect(report.runError == nil, "\(report.runError ?? "") — report: \(reportURL.path)")
        #expect(report.entries.count == files.count, "Every ARW file must be analyzed; see \(reportURL.path)")
        for entry in report.entries {
            #expect(entry.succeeded, "\(entry.file.lastPathComponent): \(entry.error ?? entry.result?.failure ?? "incomplete assessment") — see \(reportURL.path)")
        }
    }
}
