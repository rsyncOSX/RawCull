import AppKit
import Foundation
@testable import RawCull
import Testing

private actor MetadataScanProbe: RawImageLoading {
    let started: AsyncStream<Void>
    private let signal: AsyncStream<Void>.Continuation
    private let longRead: Bool
    private(set) var calls = 0
    private(set) var active = 0
    private(set) var peak = 0

    init(longRead: Bool = false) {
        (started, signal) = AsyncStream.makeStream()
        self.longRead = longRead
    }

    func fileMetadata(for _: URL) async -> RawImageFileMetadata? {
        calls += 1
        active += 1
        peak = max(peak, active)
        defer { active -= 1 }
        signal.yield(())
        try? await Task.sleep(for: longRead ? .seconds(30) : .milliseconds(2))
        return nil
    }

    func thumbnailCGImage(for _: URL, maxPixelSize _: Int) async -> CGImage? { nil }
    func thumbnailImage(for _: URL, maxPixelSize _: Int) async -> NSImage? { nil }
    func previewCGImage(for _: URL) async -> CGImage? { nil }
    func embeddedPreviewJPEGData(for _: URL, matchingPixelWidth _: Int, height _: Int) async -> Data? { nil }
}

@MainActor
private final class ScanProgressRecorder { var values: [Int] = [] }

struct ScanAdmissionTests {
    private func catalog() throws -> URL {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        for index in 0..<65 { try Data([0]).write(to: root.appendingPathComponent("photo\(index).ARW")) }
        try Data([0]).write(to: root.appendingPathComponent("ignored.txt"))
        return root
    }

    @Test
    @MainActor
    func `scan bounds metadata reads and coalesces monotonic progress`() async throws {
        let root = try catalog()
        defer { try? FileManager.default.removeItem(at: root) }
        let probe = MetadataScanProbe()
        let progress = ScanProgressRecorder()
        let files = await ScanFiles(rawLoader: probe, maximumConcurrentReads: 3).scanFiles(url: root) {
            progress.values.append($0)
        }
        #expect(files.count == 65)
        #expect(await probe.calls == 65)
        #expect(await probe.peak <= 3)
        #expect(await probe.active == 0)
        #expect(progress.values == [1, 32, 64, 65])
    }

    @Test
    func `cancelling a scan stops admission and drains admitted workers`() async throws {
        let root = try catalog()
        defer { try? FileManager.default.removeItem(at: root) }
        let probe = MetadataScanProbe(longRead: true)
        let scan = ScanFiles(rawLoader: probe, maximumConcurrentReads: 2)
        let task = Task { await scan.scanFiles(url: root) }
        for await _ in probe.started { break }
        task.cancel()
        #expect(await task.value.isEmpty)
        #expect(await probe.calls <= 2)
        #expect(await probe.active == 0)
    }
}
