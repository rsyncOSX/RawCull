import Darwin
import Foundation

/// Test-only report types. Times use the monotonic clock; wall time is provenance only.
struct CatalogPerformanceMetric: Codable {
    let phase: String
    let milliseconds: Double
    let elapsedSeconds: Double
    let succeeded: Bool
    let detail: String
}

struct CatalogPerformanceResource: Codable {
    let elapsedSeconds: Double
    let footprintBytes: UInt64?
    let cpuSeconds: Double?
    let diskReadBytes: UInt64?
    let diskWriteBytes: UInt64?

    static func capture(since start: Double) -> Self {
        var usage = rusage_info_v4()
        let result = withUnsafeMutablePointer(to: &usage) { pointer in
            pointer.withMemoryRebound(to: rusage_info_t?.self, capacity: 1) {
                proc_pid_rusage(getpid(), RUSAGE_INFO_V4, $0)
            }
        }
        return Self(
            elapsedSeconds: ProcessInfo.processInfo.systemUptime - start,
            footprintBytes: result == 0 ? usage.ri_phys_footprint : nil,
            cpuSeconds: result == 0 ? Double(usage.ri_user_time + usage.ri_system_time) / 1_000_000_000 : nil,
            diskReadBytes: result == 0 ? usage.ri_diskio_bytesread : nil,
            diskWriteBytes: result == 0 ? usage.ri_diskio_byteswritten : nil,
        )
    }
}

actor CatalogPerformanceJournal {
    private let handle: FileHandle
    private let start = ProcessInfo.processInfo.systemUptime
    private(set) var resources: [CatalogPerformanceResource] = []
    private(set) var metrics: [CatalogPerformanceMetric] = []
    private(set) var counts: [String: Int] = [:]
    private(set) var peakSaves = 0
    private var activeSaves = 0
    private var activeOperations: [String: Int] = [:]
    private var decodeStarted = false
    private var decodeWaiters: [CheckedContinuation<Void, Never>] = []
    private var writeError: String?

    init(url: URL) throws {
        FileManager.default.createFile(atPath: url.path, contents: nil)
        handle = try FileHandle(forWritingTo: url)
    }

    deinit { try? handle.close() }

    func record(_ phase: String, since start: Double, succeeded: Bool, detail: String = "") {
        let metric = CatalogPerformanceMetric(
            phase: phase,
            milliseconds: (ProcessInfo.processInfo.systemUptime - start) * 1000,
            elapsedSeconds: ProcessInfo.processInfo.systemUptime - self.start,
            succeeded: succeeded,
            detail: detail,
        )
        metrics.append(metric)
        append(metric)
    }

    private func append(_ value: some Encodable) {
        do {
            var data = try JSONEncoder().encode(value)
            data.append(10)
            try handle.write(contentsOf: data)
        } catch {
            writeError = error.localizedDescription
        }
    }

    private struct PhaseStart: Encodable {
        let event = "phase-start"
        let phase: String
        let elapsedSeconds: Double
    }

    func phase(_ name: String) {
        append(PhaseStart(phase: name, elapsedSeconds: ProcessInfo.processInfo.systemUptime - start))
        print("Catalog benchmark phase: \(name)")
    }

    func sample() {
        let sample = CatalogPerformanceResource.capture(since: start)
        resources.append(sample)
        append(sample)
    }

    func started(_ operation: String) {
        counts[operation, default: 0] += 1
        activeOperations[operation, default: 0] += 1
        counts["peak." + operation] = max(counts["peak." + operation, default: 0], activeOperations[operation, default: 0])
        if operation == "thumbnailImage" {
            decodeStarted = true
            let waiters = decodeWaiters
            decodeWaiters.removeAll()
            for waiter in waiters {
                waiter.resume()
            }
        }
    }

    func finished(_ operation: String) {
        activeOperations[operation, default: 0] -= 1
    }

    func waitForDecode() async {
        if decodeStarted {
            return
        }
        await withCheckedContinuation { decodeWaiters.append($0) }
    }

    /// Called when preload finishes as well, so a decode regression cannot leave a waiter suspended.
    func finishDecodeWait() {
        let waiters = decodeWaiters
        decodeWaiters.removeAll()
        decodeStarted = true
        for waiter in waiters {
            waiter.resume()
        }
    }

    func beginSave(bytes: Int) {
        counts["encodedSaveBytes", default: 0] += bytes
        activeSaves += 1
        peakSaves = max(peakSaves, activeSaves)
        counts["save", default: 0] += 1
    }

    func endSave() {
        activeSaves -= 1
    }

    func snapshot() throws -> CatalogPerformanceSnapshot {
        if let writeError {
            throw CocoaError(.fileWriteUnknown, userInfo: [NSLocalizedDescriptionKey: writeError])
        }
        try handle.synchronize()
        return CatalogPerformanceSnapshot(metrics: metrics, resources: resources, counts: counts, peakSaves: peakSaves)
    }
}

struct CatalogPerformanceSnapshot: Codable {
    let metrics: [CatalogPerformanceMetric]
    let resources: [CatalogPerformanceResource]
    let counts: [String: Int]
    let peakSaves: Int
}
