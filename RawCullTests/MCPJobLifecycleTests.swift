import Foundation
@testable import RawCull
import Testing

@Suite("MCP job lifecycle")
struct MCPJobLifecycleTests {
    private let now = Date(timeIntervalSince1970: 1_000)

    @Test func liveWorkerSurvivesStaleHeartbeatAndOwnsCancellation() throws {
        try withStore { store, _ in
            var lease: AnalysisJobStore.WorkerLease? = try #require(try store.acquireWorkerLease())
            var job = AnalysisJob(jobId: UUID(), catalogId: UUID(), createdAt: now, updatedAt: now)
            job.claim()
            job.heartbeatAt = now
            try store.update { _ in job }
            let stale = try #require(try store.expireInterruptedJob(now: now + 90))
            #expect(stale.state == .running)
            try store.update { _ in
                job.cancellationRequested = true
                return job
            }
            #expect(try store.expireInterruptedJob(now: now + 90)?.state == .running)
            withExtendedLifetime(lease) {}
            lease = nil
            #expect(try store.expireInterruptedJob(now: now + 90)?.state == .cancelled)
        }
    }

    @Test func interruptedWorkerFailsImmediately() throws {
        try withStore { store, _ in
            var job = AnalysisJob(jobId: UUID(), catalogId: UUID(), createdAt: now, updatedAt: now)
            job.claim()
            try store.update { _ in job }
            let recovered = try #require(try store.expireInterruptedJob(now: now))
            #expect(recovered.state == .failed)
            #expect(recovered.message?.contains("worker exited") == true)
        }
    }

    @Test func legacyHeartbeatUsesAwakeUptimeAndFallsBackOnReboot() {
        var job = AnalysisJob(jobId: UUID(), catalogId: UUID(), createdAt: now, updatedAt: now)
        job.state = .running
        job.heartbeatAt = now
        job.heartbeatUptime = 10_000_000_000
        job.heartbeatBootID = "boot"
        #expect(!job.isExpired(at: now + 120, uptime: 12_000_000_000, bootID: "boot"))
        #expect(job.isExpired(at: now + 120, uptime: 12_000_000_000, bootID: "reboot"))
    }

    @Test func publicationChecksOwnershipAndCancellation() {
        var job = AnalysisJob(jobId: UUID(), catalogId: UUID(), createdAt: now, updatedAt: now)
        job.claim()
        var current = job
        #expect(current.canPublish(for: job))
        current.cancellationRequested = true
        #expect(!current.canPublish(for: job))
        let replacement = AnalysisJob(jobId: UUID(), catalogId: job.catalogId, createdAt: now, updatedAt: now)
        #expect(!current.canPublish(for: replacement))
    }

    @Test @MainActor func lockContentionIsRetryable() throws {
        try withStore { store, _ in
            _ = try store.withLock {
                #expect(throws: AnalysisJobStore.StoreError.busy) {
                    try store.update { _ in nil }
                }
            }
            #expect(AnalysisJobStore.StoreError.isRetryable(POSIXError(.EIO)))
            #expect(!AnalysisJobStore.StoreError.isRetryable(POSIXError(.EACCES)))
            #expect(try store.update { _ in nil } == nil)
        }
    }

    @Test func malformedRecordIsProtectedWhileWorkerOwnsSlot() throws {
        try withStore { store, file in
            try Data("{".utf8).write(to: file)
            do {
                let lease = try #require(try store.acquireWorkerLease())
                #expect(throws: AnalysisJobStore.StoreError.damagedActiveJob) { try store.readRecovering() }
                #expect(FileManager.default.fileExists(atPath: file.path))
                withExtendedLifetime(lease) {}
            }
            #expect(try store.readRecovering() == nil)
            #expect(!FileManager.default.fileExists(atPath: file.path))
        }
    }

    @Test func unsupportedFormatAndIOFailureArePreserved() throws {
        try withStore { store, file in
            let future = Data(#"{"formatVersion":999}"#.utf8)
            try future.write(to: file)
            #expect(throws: AnalysisJobStore.StoreError.unsupportedFormat) { try store.readRecovering() }
            #expect(try Data(contentsOf: file) == future)
            try FileManager.default.removeItem(at: file)
            try FileManager.default.createDirectory(at: file, withIntermediateDirectories: false)
            #expect(throws: CocoaError.self) { try store.readRecovering() }
            #expect(FileManager.default.fileExists(atPath: file.path))
        }
    }

    private func withStore(_ test: (AnalysisJobStore, URL) throws -> Void) throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        try test(AnalysisJobStore(directory: directory), directory.appendingPathComponent("analysis-job.json"))
    }
}
