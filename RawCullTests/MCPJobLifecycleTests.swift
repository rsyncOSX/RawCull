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

    @Test func followUpSourceRequiresPublishedResultAndCurrentConsent() throws {
        try withStore { store, jobFile in
            let catalogID = UUID()
            let jobID = UUID()
            let grantStore = CatalogGrantStore(directory: store.directory)
            var grant = CatalogGrant(
                id: catalogID, displayName: "Fixture", summary: nil, analysisEnabled: true,
                followUpEnabled: true
            )
            try grantStore.authorize(grant)
            var job = AnalysisJob(jobId: jobID, catalogId: catalogID, createdAt: now, updatedAt: now)
            job.claim()
            try store.update { _ in job }
            let memberIDs = (0 ..< 7).map { "photo-\($0)" }
            let snapshot = FollowUpSourceSnapshot(jobID: jobID, catalogID: catalogID, photos: [:], bursts: [
                "burst": .init(photoIDs: memberIDs, ranks: [memberIDs[6]: 1],
                               recommendedPhotoID: memberIDs[6], alternatePhotoID: nil)
            ])
            try store.withLock { try store.stageFollowUpSourceLocked(snapshot) }
            #expect(throws: FollowUpSourceSnapshot.SourceError.unavailable) {
                try store.readFollowUpSource(catalogID: catalogID, jobID: jobID)
            }

            job.coverage = .init(photoCount: 7, burstCount: 1, singletonCount: 0,
                                 unevaluatedCount: 0, skippedByReason: [:], similarityBackends: [:])
            job.bursts = []
            job.finish(.completed)
            try store.update { _ in job }
            let source = try store.readFollowUpSource(catalogID: catalogID, jobID: jobID)
            #expect(try source.burst(id: "burst").photoIDs == memberIDs)
            #expect(try source.burst(id: "burst").ranks[memberIDs[6]] == 1)
            #expect(throws: FollowUpSourceSnapshot.SourceError.unavailable) {
                try store.readFollowUpSource(catalogID: catalogID, jobID: UUID())
            }

            grant.followUpEnabled = nil
            try store.withLock { try grantStore.writeLocked(grant) }
            #expect(throws: FollowUpSourceSnapshot.SourceError.unavailable) {
                try store.readFollowUpSource(catalogID: catalogID, jobID: jobID)
            }
            grant.followUpEnabled = true
            try store.withLock { try grantStore.writeLocked(grant) }

            // Simulate an older app clearing the result without removing the snapshot.
            var cleared = job
            cleared.resultCleared = true
            try JSONEncoder().encode(cleared).write(to: jobFile, options: .atomic)
            #expect(throws: FollowUpSourceSnapshot.SourceError.unavailable) {
                try store.readFollowUpSource(catalogID: catalogID, jobID: jobID)
            }
            try JSONEncoder().encode(job).write(to: jobFile, options: .atomic)
            #expect(try store.clearResult(expectedJobID: jobID))
            let snapshotFile = jobFile.deletingLastPathComponent().appendingPathComponent("follow-up-source.json")
            #expect(!FileManager.default.fileExists(atPath: snapshotFile.path))
        }
    }

    @Test func followUpPhotoResolutionRejectsChangesAndSymlinkEscape() throws {
        try withStore { _, jobFile in
            let directory = jobFile.deletingLastPathComponent()
            let catalog = directory.appendingPathComponent("catalog")
            try FileManager.default.createDirectory(at: catalog, withIntermediateDirectories: false)
            let photo = catalog.appendingPathComponent("sample.ARW")
            try Data([1]).write(to: photo)
            let values = try photo.resourceValues(forKeys: [.contentModificationDateKey])
            let modified = try #require(values.contentModificationDate)
            let entry = FollowUpSourceSnapshot.Photo(relativePath: "sample.ARW", size: 1, modified: modified)
            #expect(try entry.resolve(in: catalog).path == photo.resolvingSymlinksInPath().path)

            try Data([1, 2]).write(to: photo)
            #expect(throws: FollowUpSourceSnapshot.SourceError.changedFile) {
                try entry.resolve(in: catalog)
            }

            let outside = directory.appendingPathComponent("outside.ARW")
            try FileManager.default.moveItem(at: photo, to: outside)
            try FileManager.default.createSymbolicLink(at: photo, withDestinationURL: outside)
            #expect(throws: FollowUpSourceSnapshot.SourceError.invalidTarget) {
                try entry.resolve(in: catalog)
            }
        }
    }

    private func withStore(_ test: (AnalysisJobStore, URL) throws -> Void) throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        try test(AnalysisJobStore(directory: directory), directory.appendingPathComponent("analysis-job.json"))
    }
}
