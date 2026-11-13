import Darwin
import Dispatch
import Foundation

nonisolated struct AnalysisJob: Codable, Sendable {
    static let currentFormatVersion = 1

    enum State: String, Codable, Sendable {
        case queued, running, completed, cancelled, failed

        var isActive: Bool { self == .queued || self == .running }
    }

    let jobId: UUID
    let catalogId: UUID
    let createdAt: Date
    var updatedAt: Date
    var heartbeatAt: Date?
    var heartbeatUptime: UInt64?
    var heartbeatBootID: String?
    var state: State = .queued
    var cancellationRequested = false
    var stage = "queued"
    var filesScanned = 0
    var filesAnalyzed = 0
    var stageCompleted: Int?
    var stageTotal: Int?
    var message: String?
    var coverage: Coverage?
    var bursts: [Burst]?
    var setupRequestId: UUID?
    var previousRequestIds: [UUID]?
    private(set) var formatVersion: Int? = currentFormatVersion

    struct Coverage: Codable, Sendable {
        let photoCount: Int
        let burstCount: Int
        let singletonCount: Int
        let unevaluatedCount: Int
        let skippedByReason: [String: Int]
        let similarityBackends: [String: Int]
    }

    struct Burst: Codable, Sendable {
        let id: String
        let frameCount: Int
        let recommendedPhotoId: String?
        let alternatePhotoId: String?
        let confidence: String
        let reasons: [String]
        let cautions: [String]
        var candidates: [Candidate]
    }

    struct Candidate: Codable, Sendable {
        let photoId: String
        var name: String
        let score: Double?
        let confidence: String
        let reasons: [String]
        let cautions: [String]
    }

    mutating func finish(_ state: State, message: String? = nil) {
        self.state = state
        stage = state.rawValue
        stageCompleted = nil
        stageTotal = nil
        self.message = message
    }

    private static let bootID: String? = {
        var bytes = [UInt8](repeating: 0, count: 64)
        var size = bytes.count
        guard sysctlbyname("kern.bootsessionuuid", &bytes, &size, nil, 0) == 0 else { return nil }
        return String(validating: bytes.prefix { $0 != 0 }, as: UTF8.self)
    }()

    mutating func recordHeartbeat() {
        heartbeatAt = .now
        heartbeatUptime = DispatchTime.now().uptimeNanoseconds
        heartbeatBootID = Self.bootID
    }

    func isExpired(at now: Date) -> Bool {
        switch state {
        case .queued:
            return now.timeIntervalSince(createdAt) > 120
        case .running:
            // Dispatch uptime pauses during system sleep and is shared across processes.
            let uptime = DispatchTime.now().uptimeNanoseconds
            let wallAge = now.timeIntervalSince(heartbeatAt ?? updatedAt)
            if let heartbeatUptime, let bootID = Self.bootID,
               heartbeatBootID == bootID, uptime >= heartbeatUptime {
                return uptime - heartbeatUptime > 45_000_000_000
            }
            return wallAge > 45
        default:
            return false
        }
    }
}

/// One job slot shared by the app and any number of helper processes. The lock
/// file is never replaced. Every state transition replaces the JSON atomically.
nonisolated struct AnalysisJobStore: Sendable {
    let directory: URL?

    enum StoreError: Error {
        case unsupportedFormat
        case busy
    }

    /// An atomic replacement changes the inode or its change time.
    struct Revision: Equatable {
        let inode: ino_t
        let seconds: time_t
        let nanoseconds: Int
    }

    func revision() -> Revision? {
        guard let directory else { return nil }
        var info = stat()
        let path = directory.appendingPathComponent("analysis-job.json").path
        guard lstat(path, &info) == 0 else { return nil }
        return Revision(
            inode: info.st_ino,
            seconds: info.st_ctimespec.tv_sec,
            nanoseconds: info.st_ctimespec.tv_nsec
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
            guard (format.formatVersion ?? 1) == AnalysisJob.currentFormatVersion else {
                throw StoreError.unsupportedFormat
            }
            return try decoder.decode(AnalysisJob.self, from: data)
        } catch let error as CocoaError where error.code == .fileReadNoSuchFile {
            return nil
        }
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
        // UI callers must never wait for a separate helper process to release the lock.
        let flags = LOCK_EX | (Thread.isMainThread ? LOCK_NB : 0)
        guard flock(descriptor, flags) == 0 else {
            let code = errno
            if code == EWOULDBLOCK { throw StoreError.busy }
            throw POSIXError(POSIXErrorCode(rawValue: code) ?? .EIO)
        }
        defer { flock(descriptor, LOCK_UN) }

        return try operation()
    }

    // The caller must hold the job lock.
    func updateLocked(_ change: (AnalysisJob?) throws -> AnalysisJob?) throws -> AnalysisJob? {
        guard let directory else { throw CatalogGrantStore.StoreError.unavailable }
        let current = try readRecoveringLocked()
        if var next = try change(current) {
            next.updatedAt = .now
            try JSONEncoder().encode(next).write(
                to: directory.appendingPathComponent("analysis-job.json"), options: .atomic
            )
            return next
        }
        return current
    }

    func readRecovering() throws -> AnalysisJob? {
        do {
            return try read()
        } catch is DecodingError {
            // The writer may have replaced the record before we acquired the lock.
            return try withLock { try readRecoveringLocked() }
        }
    }

    private func readRecoveringLocked() throws -> AnalysisJob? {
        do {
            return try read()
        } catch is DecodingError {
            try removeLocked()
            return nil
        }
    }

    // The caller must hold the job lock.
    func removeLocked() throws {
        guard let directory else { throw CatalogGrantStore.StoreError.unavailable }
        do {
            try FileManager.default.removeItem(at: directory.appendingPathComponent("analysis-job.json"))
        } catch let error as CocoaError where error.code == .fileNoSuchFile {}
    }

    func expireInterruptedJob() throws -> AnalysisJob? {
        // Use the lock only for an expired job. An app heartbeat may race this read.
        let job = try readRecovering()
        guard let job, job.isExpired(at: .now) else { return job }

        return try update { current in
            guard var current, current.isExpired(at: .now) else { return nil }
            if current.cancellationRequested {
                current.finish(.cancelled)
                return current
            }
            let message = if current.state == .queued {
                "RawCull did not pick up the analysis. Open RawCull and start a new job with a new request ID."
            } else {
                "RawCull stopped responding. Start a new job with a new request ID."
            }
            current.finish(.failed, message: message)
            return current
        }
    }
}

nonisolated struct CatalogSetupRequest: Codable, Sendable {
    enum State: String, Codable, Sendable {
        case pendingApproval, queued, denied, failed
    }

    let requestId: UUID
    let catalogHint: String
    let jobType: String
    let createdAt: Date
    var state: State = .pendingApproval
    var catalogId: UUID?
    var jobId: UUID?
    var message: String?

    var isExpired: Bool { Date.now.timeIntervalSince(createdAt) > 600 }
}

// Uses the job lock to serialize submissions and approval with job publication.
nonisolated struct CatalogSetupStore: Sendable {
    let jobs: AnalysisJobStore

    enum StoreError: Error { case pendingRequest }

    private func root() throws -> URL {
        guard let directory = jobs.directory else { throw CatalogGrantStore.StoreError.unavailable }
        return directory.appendingPathComponent("catalog-setup", isDirectory: true)
    }

    private func read<T: Decodable>(_ type: T.Type, at url: URL) throws -> T? {
        do {
            return try JSONDecoder().decode(type, from: Data(contentsOf: url))
        } catch let error as CocoaError where error.code == .fileReadNoSuchFile {
            return nil
        }
    }

    func request(_ id: UUID) throws -> CatalogSetupRequest? {
        try read(CatalogSetupRequest.self, at: root().appendingPathComponent(id.uuidString))
    }

    func pending() throws -> CatalogSetupRequest? {
        guard let id = try read(UUID.self, at: root().appendingPathComponent("pending")),
              let request = try request(id), request.state == .pendingApproval else { return nil }
        return request
    }

    func submit(_ request: CatalogSetupRequest) throws -> CatalogSetupRequest {
        try jobs.withLock {
            if let existing = try self.request(request.requestId) { return existing }
            if let pending = try pending() {
                guard pending.isExpired else { throw StoreError.pendingRequest }
                var expired = pending
                expired.state = .failed
                expired.message = "The catalog setup request expired. Start a new request."
                try saveLocked(expired)
            }
            let root = try root()
            try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
            try JSONEncoder().encode(request.requestId).write(to: root.appendingPathComponent("pending"), options: .atomic)
            try saveLocked(request)
            return request
        }
    }

    func saveLocked(_ request: CatalogSetupRequest) throws {
        try JSONEncoder().encode(request).write(
            to: root().appendingPathComponent(request.requestId.uuidString), options: .atomic
        )
    }
}
