import CryptoKit
import Darwin
import Dispatch
import Foundation

/// One job slot shared by the app and any number of helper processes. The lock
/// file is never replaced. Every state transition replaces the JSON atomically.
nonisolated struct AnalysisJobStore: Sendable {
    let directory: URL?

    enum StoreError: Error {
        case unsupportedFormat
        case busy
        case damagedActiveJob
        case recoveredDamagedJob

        static func isRetryable(_ error: Error) -> Bool {
            if case busy = error {
                return true
            }
            if case damagedActiveJob = error {
                return true
            }
            let code = (error as NSError)
            if code.domain == NSPOSIXErrorDomain {
                return [EINTR, EAGAIN, EIO, ETIMEDOUT].contains(Int32(code.code))
            }
            if let underlying = code.userInfo[NSUnderlyingErrorKey] as? POSIXError {
                return isRetryable(underlying)
            }
            return false
        }
    }

    /// An atomic replacement changes the inode or its change time.
    struct Revision: Equatable {
        let inode: ino_t
        let seconds: time_t
        let nanoseconds: Int
    }

    func revision() -> Revision? {
        Self.revision(of: directory?.appendingPathComponent("analysis-job.json"))
    }

    static func revision(of url: URL?) -> Revision? {
        guard let url else { return nil }
        var info = stat()
        guard lstat(url.path, &info) == 0 else { return nil }
        return Revision(
            inode: info.st_ino,
            seconds: info.st_ctimespec.tv_sec,
            nanoseconds: info.st_ctimespec.tv_nsec,
        )
    }

    private struct Format: Decodable {
        let formatVersion: Int?
    }

    func read() throws -> AnalysisJob? {
        guard let directory else { throw CatalogGrantStore.StoreError.unavailable }
        do {
            let data = try Data(contentsOf: directory.appendingPathComponent("analysis-job.json"))
            let decoder = JSONDecoder()
            let format = try decoder.decode(Format.self, from: data)
            guard (1 ... AnalysisJob.currentFormatVersion).contains(format.formatVersion ?? 1) else {
                throw StoreError.unsupportedFormat
            }
            return try decoder.decode(AnalysisJob.self, from: data)
        } catch let error as CocoaError where error.code == .fileReadNoSuchFile {
            return nil
        }
    }

    private func sourceSnapshotURL() throws -> URL {
        guard let directory else { throw CatalogGrantStore.StoreError.unavailable }
        return directory.appendingPathComponent("follow-up-source.json")
    }

    /// Stage the snapshot before publishing the completed burst result under the job lock.
    /// An interrupted publication leaves a snapshot that cannot be read as a source.
    func stageFollowUpSourceLocked(_ snapshot: FollowUpSourceSnapshot) throws {
        guard try followUpsEnabled() else { return }
        let data = try JSONEncoder().encode(snapshot)
        guard data.count <= FollowUpSourceSnapshot.maximumBytes else {
            try removeFollowUpSourceLocked()
            return
        }
        try data.write(to: sourceSnapshotURL(), options: .atomic)
    }

    func readFollowUpSource(catalogID: UUID, jobID: UUID) throws -> FollowUpSourceSnapshot {
        try withLock { try readFollowUpSourceLocked(catalogID: catalogID, jobID: jobID) }
    }

    func readFollowUpSourceLocked(catalogID: UUID, jobID: UUID) throws -> FollowUpSourceSnapshot {
        guard try followUpsEnabled() else { throw FollowUpError.disabled }
        guard let job = try read(), job.catalogId == catalogID, job.jobId == jobID,
              job.hasShareableResult, job.resultCleared != true
        else {
            throw FollowUpSourceSnapshot.SourceError.unavailable
        }
        do {
            if !job.usesSetupApproval || job.allowsJobPhotoAccess != true {
                let grant = try CatalogGrantStore(directory: directory).authorizedCatalog()
                guard grant?.id == catalogID, grant?.analysisEnabled == true else {
                    throw FollowUpSourceSnapshot.SourceError.unavailable
                }
            }
            let data = try Data(contentsOf: sourceSnapshotURL())
            guard data.count <= FollowUpSourceSnapshot.maximumBytes else {
                throw FollowUpSourceSnapshot.SourceError.unavailable
            }
            let snapshot = try JSONDecoder().decode(FollowUpSourceSnapshot.self, from: data)
            guard snapshot.version == FollowUpSourceSnapshot.currentVersion,
                  snapshot.catalogID == catalogID, snapshot.jobID == jobID
            else {
                throw FollowUpSourceSnapshot.SourceError.unavailable
            }
            return snapshot
        } catch let error as CocoaError where error.code == .fileReadNoSuchFile {
            throw FollowUpSourceSnapshot.SourceError.unavailable
        } catch is DecodingError {
            throw FollowUpSourceSnapshot.SourceError.unavailable
        }
    }

    func removeFollowUpSourceLocked() throws {
        do {
            try FileManager.default.removeItem(at: sourceSnapshotURL())
        } catch let error as CocoaError where error.code == .fileNoSuchFile {}
    }

    /// The update returns a new record only when it needs to change the slot.
    @discardableResult
    func update(_ change: (AnalysisJob?) throws -> AnalysisJob?) throws -> AnalysisJob? {
        try withLock { try updateLocked(change) }
    }

    func withLock<Result>(_ operation: () throws -> Result) throws -> Result {
        guard let directory else { throw CatalogGrantStore.StoreError.unavailable }
        let lock = directory.appendingPathComponent("analysis-job.lock")
        let descriptor = open(lock.path, O_CREAT | O_RDWR | O_NOFOLLOW | O_CLOEXEC, S_IRUSR | S_IWUSR)
        guard descriptor >= 0 else { throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO) }
        defer { close(descriptor) }
        // Callers can retry without blocking the UI or a cooperative executor thread.
        guard flock(descriptor, LOCK_EX | LOCK_NB) == 0 else {
            let code = errno
            if code == EWOULDBLOCK {
                throw StoreError.busy
            }
            throw POSIXError(POSIXErrorCode(rawValue: code) ?? .EIO)
        }
        defer { flock(descriptor, LOCK_UN) }

        return try operation()
    }

    final class WorkerLease: Sendable {
        private let descriptor: Int32

        init(descriptor: Int32) {
            self.descriptor = descriptor
        }

        deinit { close(descriptor) }
    }

    func acquireWorkerLease() throws -> WorkerLease? {
        guard let directory else { throw CatalogGrantStore.StoreError.unavailable }
        let path = directory.appendingPathComponent("analysis-worker.lock").path
        let descriptor = open(path, O_CREAT | O_RDWR | O_NOFOLLOW | O_CLOEXEC, S_IRUSR | S_IWUSR)
        guard descriptor >= 0 else { throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO) }
        if flock(descriptor, LOCK_EX | LOCK_NB) == 0 {
            return WorkerLease(descriptor: descriptor)
        }
        let code = errno
        close(descriptor)
        if code == EWOULDBLOCK {
            return nil
        }
        throw POSIXError(POSIXErrorCode(rawValue: code) ?? .EIO)
    }

    /// The caller must hold the job lock.
    func updateLocked(_ change: (AnalysisJob?) throws -> AnalysisJob?) throws -> AnalysisJob? {
        let current = try readRecoveringLocked()
        if let next = try change(current) {
            if let current, current.hasShareableResult, current.jobId != next.jobId {
                guard try queuedFollowUp().map({ Date.now.timeIntervalSince($0.createdAt) >= 120 }) ?? true,
                      let lease = try acquireWorkerLease() else { throw StoreError.busy }
                return try withExtendedLifetime(lease) { try writeLocked(next, replacing: current) }
            }
            return try writeLocked(next, replacing: current)
        }
        return current
    }

    private func writeLocked(_ next: AnalysisJob, replacing current: AnalysisJob?) throws -> AnalysisJob {
        guard let directory else { throw CatalogGrantStore.StoreError.unavailable }
        var next = next
        if next.jobId != current?.jobId || (next.state != .running && !next.hasShareableResult) {
            try removeFollowUpSourceLocked()
            try removeFollowUpRequestsLocked()
        }
        next.updatedAt = .now
        try JSONEncoder().encode(next).write(
            to: directory.appendingPathComponent("analysis-job.json"), options: .atomic,
        )
        return next
    }

    func readRecovering() throws -> AnalysisJob? {
        do {
            return try read()
        } catch is DecodingError {
            // The writer may have replaced the record before we acquired the lock.
            return try withLock { try readRecoveringLocked(reportRecovery: true) }
        }
    }

    private func readRecoveringLocked(reportRecovery: Bool = false) throws -> AnalysisJob? {
        do {
            return try read()
        } catch is DecodingError {
            guard let lease = try acquireWorkerLease() else { throw StoreError.damagedActiveJob }
            try withExtendedLifetime(lease) {
                guard let directory else { throw CatalogGrantStore.StoreError.unavailable }
                try removeFollowUpSourceLocked()
                try removeFollowUpRequestsLocked()
                let job = directory.appendingPathComponent("analysis-job.json")
                let damagedJob = directory.appendingPathComponent("analysis-job.damaged")
                guard rename(job.path, damagedJob.path) == 0 else {
                    throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
                }
            }
            if reportRecovery {
                throw StoreError.recoveredDamagedJob
            }
            return nil
        }
    }

    /// The caller must hold the job lock.
    func removeLocked() throws {
        try removeFollowUpSourceLocked()
        try removeFollowUpRequestsLocked()
        guard let directory else { throw CatalogGrantStore.StoreError.unavailable }
        try removeFollowUpFile(directory.appendingPathComponent("analysis-job.damaged"))
        do {
            try FileManager.default.removeItem(at: directory.appendingPathComponent("analysis-job.json"))
        } catch let error as CocoaError where error.code == .fileNoSuchFile {}
    }

    @discardableResult
    func clearResult(expectedJobID: UUID) throws -> Bool {
        try withLock {
            guard let job = try read(), job.jobId == expectedJobID, job.hasShareableResult else { return false }
            // Retain job identity for replay without retaining the shared result.
            var cleared = AnalysisJob(jobId: job.jobId, catalogId: job.catalogId,
                                      createdAt: job.createdAt, updatedAt: .now)
            cleared.finish(.completed)
            cleared.resultCleared = true
            cleared.setupRequestId = job.setupRequestId
            cleared.setupHintDigest = job.setupHintDigest
            cleared.usesSavedGrant = job.usesSavedGrant
            cleared.previousRequestIds = job.previousRequestIds
            _ = try updateLocked { _ in cleared }
            return true
        }
    }

    func expireInterruptedJob(now: Date = .now) throws -> AnalysisJob? {
        let job = try readRecovering()
        guard let job, job.state.isActive, job.usesWorkerLease || job.isExpired(at: now) else { return job }

        return try update { current in
            guard var current, current.jobId == job.jobId, current.state.isActive else { return nil }
            if current.usesWorkerLease {
                // The kernel releases this lock even when the app exits without cleaning up.
                guard try acquireWorkerLease() != nil else { return nil }
            } else {
                guard current.isExpired(at: now) else { return nil }
            }
            if current.cancellationRequested {
                current.finish(.cancelled)
            } else if current.state == .queued {
                current.finish(.failed, message: "RawCull did not pick up the analysis. Open RawCull and start a new job with a new request ID.")
            } else if current.usesWorkerLease {
                current.finish(.failed, message: "The RawCull analysis worker exited. Start a new job with a new request ID.")
            } else {
                current.finish(.failed, message: "RawCull stopped reporting progress. Start a new job with a new request ID.")
            }
            return current
        }
    }
}
