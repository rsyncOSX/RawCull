import Foundation
@testable import RawCull
import RawCullCore
import Testing

struct CatalogPerformanceReportTests {
    @Test
    func `CPU counters convert Mach ticks and avoid integer overflow`() {
        #expect(abs(CatalogPerformanceResource.cpuSeconds(
            userTicks: 4_800_000, systemTicks: 1_200_000, numerator: 125, denominator: 3,
        ) - 0.25) < 0.000001)
        #expect(CatalogPerformanceResource.cpuSeconds(
            userTicks: 1_000_000_000, systemTicks: 0, numerator: 1, denominator: 1,
        ) == 1)
        #expect(CatalogPerformanceResource.cpuSeconds(
            userTicks: .max, systemTicks: .max, numerator: 125, denominator: 3,
        ).isFinite)
    }

    @Test
    func `operation timings exclude the journal actor wait`() async throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: url) }
        let journal = try CatalogPerformanceJournal(url: url)
        let end = ProcessInfo.processInfo.systemUptime
        await journal.record(ScanAndCreateThumbnails.Measurement(
            phase: "jpeg.encode",
            source: URL(fileURLWithPath: "/tmp/image.ARW"),
            start: end - 0.025,
            end: end,
            succeeded: true,
        ))
        let result = try await journal.snapshot()
        let metric = try #require(result.metrics.first)
        #expect(abs(metric.milliseconds - 25) < 0.001)
        #expect(metric.phase == "jpeg.encode" && metric.detail == "image.ARW")
    }

    @Test
    func `source stage timestamps survive reporting without becoming ordinary metrics`() async throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: url) }
        let journal = try CatalogPerformanceJournal(url: url)
        let timing = RawSourceLoadDiagnostic(
            id: UUID(),
            operation: "thumbnail.preload",
            source: URL(fileURLWithPath: "/tmp/test.ARW"),
            requestedPixelSize: 1616,
            submitted: 1,
            accessReady: 2,
            taskStarted: 3,
            parserReturned: 4,
            delivered: 5,
            succeeded: false,
            cancelled: true,
        )
        await journal.record(timing)
        let snapshot = try await journal.snapshot()
        #expect(snapshot.metrics.isEmpty)
        let object = try #require(JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
        #expect(object["event"] as? String == "source-load")
        let recorded = try #require(object["timing"] as? [String: Any])
        #expect(recorded["delivered"] as? Double == 5)
        #expect(recorded["cancelled"] as? Bool == true)
        #expect(object["journalOriginUptime"] is Double)
    }

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
