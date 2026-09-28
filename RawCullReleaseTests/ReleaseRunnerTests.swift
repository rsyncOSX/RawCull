import Foundation
import Testing

@Suite("Release runner contract")
struct ReleaseRunnerTests {
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
}
