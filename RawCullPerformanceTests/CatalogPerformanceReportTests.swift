import Foundation
@testable import RawCull
import RawCullCore
import Testing

struct CatalogPerformanceReportTests {
    @Test
    @MainActor
    func `navigation benchmark validates real presentation without a catalog fixture`() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let journal = try CatalogPerformanceJournal(url: directory.appendingPathComponent("events.jsonl"))
        let files = (0 ..< 4).map { index in
            FileItem(
                url: directory.appendingPathComponent("\(index).ARW"),
                name: "\(index).ARW",
                size: 10,
                dateModified: Date(timeIntervalSince1970: 0),
                exifData: nil,
                afFocusNormalized: nil,
            )
        }
        try await CatalogPerformanceTests().presentation(files, steps: 10, journal: journal)
        let result = try await journal.snapshot()
        let succeeded = result.metrics.allSatisfy(\.succeeded)
        #expect(succeeded)
        #expect(result.metrics.filter { $0.phase == "navigation.selectionAndControls" }.count == 10)
    }

    @Test
    func `journal preserves operations failures resources and pending decode release`() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("events.jsonl")
        let journal = try CatalogPerformanceJournal(url: url)
        await journal.sample()
        await journal.started("metadata")
        await journal.started("metadata")
        await journal.finished("metadata")
        await journal.finished("metadata")
        await journal.beginSave(bytes: 123)
        await journal.endSave()
        await journal.record(
            "metadata.file",
            since: ProcessInfo.processInfo.systemUptime,
            succeeded: false,
            detail: "broken.ARW",
        )
        let waiter = Task { await journal.waitForDecode() }
        await journal.finishDecodeWait()
        await waiter.value
        let snapshot = try await journal.snapshot()
        #expect(snapshot.counts["metadata"] == 2)
        #expect(snapshot.counts["peak.metadata"] == 2)
        #expect(snapshot.counts["encodedSaveBytes"] == 123)
        #expect(snapshot.peakSaves == 1)
        #expect(snapshot.metrics.count == 1)
        #expect(snapshot.metrics.first?.succeeded == false)
        #expect(snapshot.metrics.first?.detail == "broken.ARW")
        #expect(snapshot.metrics.first?.elapsedSeconds ?? -1 >= 0)
        #expect(snapshot.resources.count == 1)
        #expect(snapshot.resources.first?.footprintBytes != nil)
        let lines = try String(contentsOf: url, encoding: .utf8).split(separator: "\n")
        #expect(lines.count == 2)
        let saved = try JSONDecoder().decode(CatalogPerformanceMetric.self, from: Data(lines[1].utf8))
        #expect(saved.detail == "broken.ARW" && !saved.succeeded)
    }
}
