import CryptoKit
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
    var usesSavedGrant: Bool?
    var usesSetupApproval: Bool { setupRequestId != nil && usesSavedGrant != true }
    var hasShareableResult: Bool { state == .completed && coverage != nil && bursts != nil }
    var catalogDisplayName: String?
    var setupHintDigest: Data?
    var resultCleared: Bool?
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
        Self.revision(of: directory?.appendingPathComponent("analysis-job.json"))
    }

    static func revision(of url: URL?) -> Revision? {
        guard let url else { return nil }
        var info = stat()
        guard lstat(url.path, &info) == 0 else { return nil }
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
    var catalogHint: String?
    var hintDigest: Data?
    let jobType: String
    let createdAt: Date
    var state: State = .pendingApproval
    var catalogId: UUID?
    var jobId: UUID?
    var message: String?
    var deniedAt: Date?

    var isExpired: Bool { isExpired(at: .now) }

    func isExpired(at now: Date) -> Bool { now.timeIntervalSince(createdAt) > 600 }

    func matches(_ proposed: Self) -> Bool {
        guard jobType == proposed.jobType, let hint = proposed.catalogHint else { return false }
        if let catalogHint { return catalogHint == hint }
        return hintDigest == Self.digest(hint)
    }

    var displayHint: String {
        guard let catalogHint else { return "" }
        let scalars = catalogHint.unicodeScalars.prefix(160)
        let line = String(String.UnicodeScalarView(scalars.map { scalar in
            CharacterSet.controlCharacters.contains(scalar) || CharacterSet.newlines.contains(scalar) ? " " : scalar
        })).trimmingCharacters(in: .whitespaces)
        return scalars.endIndex == catalogHint.unicodeScalars.endIndex ? line : line + "…"
    }

    var replayDigest: Data? { catalogHint.map(Self.digest) ?? hintDigest }

    mutating func discardHint() {
        hintDigest = replayDigest
        catalogHint = nil
    }

    private static func digest(_ hint: String) -> Data {
        Data(SHA256.hash(data: Data(hint.precomposedStringWithCanonicalMapping.utf8)))
    }
}

// Uses the job lock to serialize submissions and approval with job publication.
nonisolated struct CatalogSetupStore: Sendable {
    let jobs: AnalysisJobStore

    enum StoreError: Error {
        case pendingRequest, expiredRequest, storageFull
        case denialCooldown(secondsRemaining: Int)
    }

    struct Submission {
        let request: CatalogSetupRequest
        let wasAccepted: Bool
    }

    // Reserve space for every accepted UUID throughout its replay protection window.
    private static let replayWindow: TimeInterval = 24 * 60 * 60
    private static let retentionWindow: TimeInterval = 7 * 24 * 60 * 60
    private static let receiptLimit = 128
    private static let denialCooldown: TimeInterval = 10

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

    private func remove(_ url: URL) throws {
        do {
            try FileManager.default.removeItem(at: url)
        } catch let error as CocoaError where error.code == .fileNoSuchFile {}
    }

    private func receipt(_ id: UUID, at url: URL) throws -> CatalogSetupRequest? {
        guard let receipt = try read(CatalogSetupRequest.self, at: url) else { return nil }
        guard receipt.requestId == id else {
            throw DecodingError.dataCorrupted(.init(codingPath: [], debugDescription: "Setup receipt ID mismatch"))
        }
        return receipt
    }

    private func queuedReceipt(_ job: AnalysisJob, id: UUID, existing: CatalogSetupRequest?) -> CatalogSetupRequest {
        var request = existing ?? CatalogSetupRequest(
            requestId: id, catalogHint: nil, jobType: "burstAnalysis", createdAt: job.createdAt
        )
        request.state = .queued
        request.catalogId = job.catalogId
        request.jobId = job.jobId
        request.discardHint()
        request.hintDigest = request.hintDigest ?? job.setupHintDigest
        return request
    }

    private func currentSetupJob() throws -> AnalysisJob? {
        do {
            return try jobs.read()
        } catch is DecodingError {
            return nil
        } catch AnalysisJobStore.StoreError.unsupportedFormat {
            return nil
        }
    }

    func request(_ id: UUID, now: Date = .now) throws -> CatalogSetupRequest? {
        try jobs.withLock {
            _ = try pendingLocked(now: now)
            return try requestLocked(id, currentJob: currentSetupJob(), now: now)
        }
    }

    private func requestLocked(_ id: UUID, currentJob: AnalysisJob?, now: Date) throws -> CatalogSetupRequest? {
        let url = try root().appendingPathComponent(id.uuidString)
        let stored: CatalogSetupRequest?
        do {
            stored = try receipt(id, at: url)
        } catch is DecodingError {
            stored = nil
        }
        if let currentJob, currentJob.setupRequestId == id {
            if let stored, stored.state == .queued, stored.catalogHint == nil { return stored }
            let recovered = queuedReceipt(currentJob, id: id, existing: stored)
            try saveLocked(recovered)
            return recovered
        }
        guard var stored else { return nil }
        guard now.timeIntervalSince(stored.createdAt) <= Self.replayWindow else { throw StoreError.expiredRequest }
        if stored.state == .pendingApproval, try pendingIDLocked() != id {
            stored.state = .failed
            stored.message = "The setup request was interrupted. Start a new request."
        }
        if stored.state != .pendingApproval, stored.catalogHint != nil {
            stored.discardHint()
            try saveLocked(stored)
        }
        return stored
    }

    func pending() throws -> CatalogSetupRequest? {
        try jobs.withLock { try pendingLocked() }
    }

    private func pendingIDLocked() throws -> UUID? {
        let pointer = try root().appendingPathComponent("pending")
        do {
            return try read(UUID.self, at: pointer)
        } catch is DecodingError {
            try remove(pointer)
            return nil
        }
    }

    // Must be called with the job lock held.
    func pendingLocked(now: Date = .now) throws -> CatalogSetupRequest? {
        guard let id = try pendingIDLocked() else { return nil }
        let root = try root()
        let url = root.appendingPathComponent(id.uuidString)
        let stored: CatalogSetupRequest?
        do {
            stored = try receipt(id, at: url)
        } catch is DecodingError {
            stored = nil
        }
        if let job = try currentSetupJob(), job.setupRequestId == id {
            if stored?.state != .queued || stored?.catalogHint != nil {
                try saveLocked(queuedReceipt(job, id: id, existing: stored))
            }
        } else if var request = stored, request.state == .pendingApproval {
            if request.catalogHint != nil, !request.isExpired(at: now) { return request }
            request.state = .failed
            request.message = "The setup request expired or was incomplete. Start a new request."
            try saveLocked(request)
        } else if stored == nil {
            try remove(url)
        }
        try remove(root.appendingPathComponent("pending"))
        return nil
    }

    func submit(_ request: CatalogSetupRequest, now: Date = .now) throws -> Submission {
        try jobs.withLock {
            let pending = try pendingLocked(now: now)
            let currentJob = try currentSetupJob()
            let retained = try pruneLocked(pendingID: pending?.requestId, currentJob: currentJob, now: now)
            if let existing = try requestLocked(request.requestId, currentJob: currentJob, now: now) {
                return Submission(request: existing, wasAccepted: false)
            }
            guard pending == nil else { throw StoreError.pendingRequest }
            if let deniedAt = retained.lastDenial {
                let remaining = Self.denialCooldown - max(0, now.timeIntervalSince(deniedAt))
                if remaining > 0 {
                    throw StoreError.denialCooldown(secondsRemaining: Int(remaining.rounded(.up)))
                }
            }
            guard retained.count < Self.receiptLimit else { throw StoreError.storageFull }
            let root = try root()
            try saveLocked(request)
            try JSONEncoder().encode(request.requestId).write(to: root.appendingPathComponent("pending"), options: .atomic)
            return Submission(request: request, wasAccepted: true)
        }
    }

    func maintain(now: Date = .now) throws {
        try jobs.withLock {
            let pending = try pendingLocked(now: now)
            _ = try pruneLocked(pendingID: pending?.requestId, currentJob: currentSetupJob(), now: now)
        }
    }

    private func pruneLocked(
        pendingID: UUID?, currentJob: AnalysisJob?, now: Date
    ) throws -> (count: Int, lastDenial: Date?) {
        let root = try root()
        let files: [URL]
        do {
            files = try FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil)
        } catch let error as CocoaError where error.code == .fileReadNoSuchFile {
            return (0, nil)
        }
        var protectedCount = 0
        var lastDenial: Date?
        var historical: [(url: URL, createdAt: Date)] = []
        for url in files {
            guard let id = UUID(uuidString: url.lastPathComponent) else { continue }
            let stored: CatalogSetupRequest?
            do {
                stored = try receipt(id, at: url)
            } catch is DecodingError {
                stored = nil
            }
            if let currentJob, currentJob.setupRequestId == id {
                protectedCount += 1
                if stored?.state != .queued || stored?.catalogHint != nil {
                    try saveLocked(queuedReceipt(currentJob, id: id, existing: stored))
                }
            } else if id == pendingID {
                protectedCount += 1
            } else {
                guard var stored, now.timeIntervalSince(stored.createdAt) <= Self.retentionWindow else {
                    try remove(url)
                    continue
                }
                if stored.state == .pendingApproval {
                    stored.state = .failed
                    stored.message = "The setup request was interrupted. Start a new request."
                    try saveLocked(stored)
                } else if stored.catalogHint != nil {
                    try saveLocked(stored)
                }
                if stored.state == .denied, let deniedAt = stored.deniedAt {
                    lastDenial = max(lastDenial ?? .distantPast, deniedAt)
                }
                historical.append((url, max(stored.createdAt, stored.deniedAt ?? .distantPast)))
            }
        }
        if let currentJob, let id = currentJob.setupRequestId,
           !files.contains(where: { $0.lastPathComponent == id.uuidString }) {
            try saveLocked(queuedReceipt(currentJob, id: id, existing: nil))
            protectedCount += 1
        }
        let available = max(0, Self.receiptLimit - protectedCount)
        let ordered = historical.sorted {
            if $0.createdAt == $1.createdAt { return $0.url.lastPathComponent < $1.url.lastPathComponent }
            return $0.createdAt > $1.createdAt
        }
        for entry in ordered.dropFirst(available) { try remove(entry.url) }
        return (protectedCount + min(available, ordered.count), lastDenial)
    }

    // Must be called with the job lock held.
    func saveLocked(_ request: CatalogSetupRequest) throws {
        var receipt = request
        if receipt.state != .pendingApproval { receipt.discardHint() }
        let root = try root()
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try JSONEncoder().encode(receipt).write(
            to: root.appendingPathComponent(receipt.requestId.uuidString), options: .atomic
        )
    }
}
