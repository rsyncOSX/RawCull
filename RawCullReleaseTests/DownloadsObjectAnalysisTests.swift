import CoreAISAM3Backend
import Foundation
import PhotoAIStorage
import PhotoAIWorkflows
import Testing

/// Deliberately outside RawCullTests: real photos and real local models only.
@Suite("Downloads AI Objects release integration")
struct DownloadsObjectAnalysisTests {
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

nonisolated enum ReleaseRunError: Error, LocalizedError {
    case message(String)
    var errorDescription: String? {
        switch self { case let .message(text): text }
    }
}

nonisolated struct ReleaseRunConfiguration {
    let directory: URL
    let qwenPath: String?
    let samPath: String?
    let modelRoots: [URL]

    init(environment: [String: String]) {
        let home = FileManager.default.homeDirectoryForCurrentUser
        directory = URL(fileURLWithPath: environment["RAWCULL_RELEASE_DIRECTORY"] ?? home.appendingPathComponent("Downloads").path, isDirectory: true)
        qwenPath = environment["RAWCULL_RELEASE_QWEN"].flatMap { $0.isEmpty ? nil : $0 }
        samPath = environment["RAWCULL_RELEASE_SAM3"].flatMap { $0.isEmpty ? nil : $0 }
        modelRoots = [
            home.appendingPathComponent("ModelAssets/Release/Models"),
            home.appendingPathComponent("Library/Application Support/RawCull/Models"),
            home.appendingPathComponent("Library/Containers/no.blogspot.RawCull/Data/Library/Application Support/RawCull/Models"),
        ]
    }

    static func discoverARWFiles(in directory: URL) throws -> [URL] {
        try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: [.isRegularFileKey])
            .filter { url in
                guard url.pathExtension.lowercased() == "arw" else { return false }
                return try url.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile == true
            }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
    }

    func modelURL(override: String?, relativePath: String, option: String) throws -> URL {
        let candidates = override.map { [URL(fileURLWithPath: $0, isDirectory: true)] }
            ?? modelRoots.map { $0.appendingPathComponent(relativePath, isDirectory: true) }
        for url in candidates {
            var isDirectory: ObjCBool = false
            if FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory), isDirectory.boolValue {
                return url
            }
        }
        throw ReleaseRunError.message("Model bundle missing. Set \(option)=\"/path/to/model\" when invoking make releastest. Checked: \(candidates.map(\.path).joined(separator: ", "))")
    }
}
