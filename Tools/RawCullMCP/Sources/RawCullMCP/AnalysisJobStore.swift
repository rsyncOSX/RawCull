import CryptoKit
import Darwin
import Dispatch
import Foundation

nonisolated struct AnalysisJob: Codable, Sendable {
    static let currentFormatVersion = 2

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
    private(set) var formatVersion: Int? = 1
    var usesWorkerLease: Bool { formatVersion == Self.currentFormatVersion && state == .running }

    func canPublish(for job: Self) -> Bool {
        jobId == job.jobId && catalogId == job.catalogId && state == .running && !cancellationRequested
    }

    var burstCursorPrefix: String { "\(catalogId.uuidString):\(jobId.uuidString):" }

    func burstCursorOffset(_ token: String, count: Int) -> Int? {
        guard token.hasPrefix(burstCursorPrefix),
              let offset = Int(token.dropFirst(burstCursorPrefix.count)),
              offset > 0, offset < count else { return nil }
        return offset
    }

    static let directReplayLimit = 128

    func nextDirectRequestHistory() -> [UUID] {
        Array(((previousRequestIds ?? []).suffix(Self.directReplayLimit - 1)) + [jobId])
    }

    mutating func claim() {
        state = .running
        formatVersion = Self.currentFormatVersion
    }

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
        if !state.isActive { formatVersion = 1 }
        stage = state.rawValue
        stageCompleted = nil
        stageTotal = nil
        self.message = message
    }

    private static let bootID: String? = {
        var bytes = [UInt8](repeating: 0, count: 64)
        var size = bytes.count
        guard sysctlbyname("kern.bootsessionuuid", &bytes, &size, nil, 0) == 0 else { return nil }
        return String(bytes: bytes.prefix { $0 != 0 }, encoding: .utf8)
    }()

    mutating func recordHeartbeat() {
        heartbeatAt = .now
        heartbeatUptime = DispatchTime.now().uptimeNanoseconds
        heartbeatBootID = Self.bootID
    }

    func isExpired(at now: Date, uptime: UInt64 = DispatchTime.now().uptimeNanoseconds, bootID: String? = Self.bootID) -> Bool {
        switch state {
        case .queued:
            return now.timeIntervalSince(createdAt) > 120
        case .running:
            // Dispatch uptime pauses during system sleep and is shared across processes.
            let wallAge = now.timeIntervalSince(heartbeatAt ?? updatedAt)
            if let heartbeatUptime, let bootID,
               heartbeatBootID == bootID, uptime >= heartbeatUptime {
                return uptime - heartbeatUptime > 45_000_000_000
            }
            return wallAge > 45
        default:
            return false
        }
    }
}

/// Private source evidence. The public burst result remains the publication marker.
nonisolated struct FollowUpSourceSnapshot: Codable, Sendable {
    static let currentVersion = 1
    static let maximumBytes = 16 * 1024 * 1024

    var version = Self.currentVersion
    let jobID: UUID
    let catalogID: UUID
    let photos: [String: Photo]
    let bursts: [String: Burst]

    struct Photo: Codable, Sendable {
        let relativePath: String
        let size: Int64
        let modified: Date

        func resolve(in catalog: URL) throws -> URL {
            let components = relativePath.split(separator: "/", omittingEmptySubsequences: false)
            guard !components.contains(where: { $0.isEmpty || $0 == "." || $0 == ".." }) else {
                throw SourceError.invalidTarget
            }

            let root = catalog.resolvingSymlinksInPath().standardizedFileURL
            let file = root.appendingPathComponent(relativePath).resolvingSymlinksInPath().standardizedFileURL
            let rootComponents = root.pathComponents
            let fileComponents = file.pathComponents
            guard fileComponents.count > rootComponents.count,
                  fileComponents.starts(with: rootComponents, by: { $0.utf8.elementsEqual($1.utf8) }) else {
                throw SourceError.invalidTarget
            }
            let values = try file.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey, .contentModificationDateKey])
            guard values.isRegularFile == true, values.fileSize.map(Int64.init) == size,
                  values.contentModificationDate == modified else {
                throw SourceError.changedFile
            }
            return file
        }
    }

    struct Burst: Codable, Sendable {
        let photoIDs: [String]
        let ranks: [String: Int]
        let recommendedPhotoID: String?
        let alternatePhotoID: String?
    }

    enum SourceError: Error {
        case unavailable
        case invalidTarget
        case changedFile
    }

    // The caller retains the authorized catalog's security-scoped access.
    func resolve(photoID: String, in catalog: URL) throws -> URL {
        guard let photo = photos[photoID] else { throw SourceError.invalidTarget }
        return try photo.resolve(in: catalog)
    }

    func burst(id: String) throws -> Burst {
        guard let burst = bursts[id] else { throw SourceError.invalidTarget }
        return burst
    }
}

/// One job slot shared by the app and any number of helper processes. The lock
/// file is never replaced. Every state transition replaces the JSON atomically.
nonisolated struct AnalysisJobStore: Sendable {
    let directory: URL?

    enum StoreError: Error {
        case unsupportedFormat
        case busy
        case damagedActiveJob

        static func isRetryable(_ error: Error) -> Bool {
            if case Self.busy = error { return true }
            if case Self.damagedActiveJob = error { return true }
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

    // Stage the snapshot before publishing the completed burst result under the job lock.
    // An interrupted publication leaves a snapshot that cannot be read as a source.
    func stageFollowUpSourceLocked(_ snapshot: FollowUpSourceSnapshot) throws {
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

    private func readFollowUpSourceLocked(catalogID: UUID, jobID: UUID) throws -> FollowUpSourceSnapshot {
        let grant = try CatalogGrantStore(directory: directory).authorizedCatalog()
        guard grant?.id == catalogID, grant?.analysisEnabled == true, grant?.followUpEnabled == true,
              let job = try read(), job.catalogId == catalogID, job.jobId == jobID,
              !job.usesSetupApproval, job.hasShareableResult, job.resultCleared != true else {
            throw FollowUpSourceSnapshot.SourceError.unavailable
        }
        do {
            let data = try Data(contentsOf: sourceSnapshotURL())
            guard data.count <= FollowUpSourceSnapshot.maximumBytes else {
                throw FollowUpSourceSnapshot.SourceError.unavailable
            }
            let snapshot = try JSONDecoder().decode(FollowUpSourceSnapshot.self, from: data)
            guard snapshot.version == FollowUpSourceSnapshot.currentVersion,
                  snapshot.catalogID == catalogID, snapshot.jobID == jobID else {
                throw FollowUpSourceSnapshot.SourceError.unavailable
            }
            return snapshot
        } catch let error as CocoaError where error.code == .fileReadNoSuchFile {
            throw FollowUpSourceSnapshot.SourceError.unavailable
        } catch is DecodingError {
            throw FollowUpSourceSnapshot.SourceError.unavailable
        }
    }

    private func removeFollowUpSourceLocked() throws {
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

    final class WorkerLease: Sendable {
        private let descriptor: Int32

        init(descriptor: Int32) { self.descriptor = descriptor }

        deinit { close(descriptor) }
    }

    func acquireWorkerLease() throws -> WorkerLease? {
        guard let directory else { throw CatalogGrantStore.StoreError.unavailable }
        let path = directory.appendingPathComponent("analysis-worker.lock").path
        let descriptor = open(path, O_CREAT | O_RDWR | O_NOFOLLOW | O_CLOEXEC, S_IRUSR | S_IWUSR)
        guard descriptor >= 0 else { throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO) }
        if flock(descriptor, LOCK_EX | LOCK_NB) == 0 { return WorkerLease(descriptor: descriptor) }
        let code = errno
        close(descriptor)
        if code == EWOULDBLOCK { return nil }
        throw POSIXError(POSIXErrorCode(rawValue: code) ?? .EIO)
    }

    // The caller must hold the job lock.
    func updateLocked(_ change: (AnalysisJob?) throws -> AnalysisJob?) throws -> AnalysisJob? {
        let current = try readRecoveringLocked()
        if let next = try change(current) {
            if let current, current.hasShareableResult, current.jobId != next.jobId {
                guard let lease = try acquireWorkerLease() else { throw StoreError.busy }
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
            to: directory.appendingPathComponent("analysis-job.json"), options: .atomic
        )
        return next
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
            guard let lease = try acquireWorkerLease() else { throw StoreError.damagedActiveJob }
            try withExtendedLifetime(lease) { try removeLocked() }
            return nil
        }
    }

    // The caller must hold the job lock.
    func removeLocked() throws {
        try removeFollowUpSourceLocked()
        try removeFollowUpRequestsLocked()
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

/// Internal follow-up storage. The request record is the publication marker for its result.
nonisolated extension AnalysisJobStore {
    struct FollowUpRequest: Codable, Equatable, Sendable {
        enum Target: Codable, Equatable, Sendable {
            case photos([String])
            case burst(String)
        }

        let id: UUID
        let catalogID: UUID
        let sourceJobID: UUID
        let target: Target
        let rubric: [String]

        init(id: UUID, catalogID: UUID, sourceJobID: UUID, target: Target, rubric: [String]) {
            self.id = id
            self.catalogID = catalogID
            self.sourceJobID = sourceJobID
            self.target = target
            self.rubric = rubric.sorted()
        }
    }

    struct FollowUpRecord: Codable, Sendable {
        enum State: String, Codable, Sendable {
            case running, completed, cancelled, interrupted
        }

        var version = 1
        var kind = "photoAssessment"
        let request: FollowUpRequest
        let snapshotVersion: Int
        let createdAt: Date
        var finishedAt: Date?
        var state = State.running
        var cancellationRequested = false
    }

    final class FollowUpWorker: Sendable {
        let request: FollowUpRequest
        let source: FollowUpSourceSnapshot
        fileprivate let lease: WorkerLease

        func resolveTargets(in catalog: URL) throws -> [URL] {
            try request.target.photoIDs(in: source).map { try source.resolve(photoID: $0, in: catalog) }
        }

        fileprivate init(request: FollowUpRequest, source: FollowUpSourceSnapshot, lease: WorkerLease) {
            self.request = request
            self.source = source
            self.lease = lease
        }
    }

    enum FollowUpAdmission {
        case started(FollowUpWorker)
        case replay(FollowUpRecord)
    }

    enum FollowUpError: Error {
        case conflict
        case invalidRequest
        case capacity
        case unavailable
        case expiredResult
        case resultTooLarge
    }

    func beginFollowUp(_ request: FollowUpRequest, now: Date = .now) throws -> FollowUpAdmission {
        try withLock {
            let source = try readFollowUpSourceLocked(catalogID: request.catalogID, jobID: request.sourceJobID)
            _ = try request.target.photoIDs(in: source)
            let supportedRubric = Set(["composition", "exposure", "subjectVisibility"])
            guard !request.rubric.isEmpty, request.rubric.count <= supportedRubric.count,
                  Set(request.rubric).count == request.rubric.count,
                  Set(request.rubric).isSubset(of: supportedRubric) else { throw FollowUpError.invalidRequest }
            if let existing = try readFollowUpRecordLocked(request.id),
               existing.finishedAt.map({ now.timeIntervalSince($0) < Self.followUpReceiptLifetime }) ?? true {
                guard existing.request == request, existing.snapshotVersion == source.version else {
                    throw FollowUpError.conflict
                }
                if existing.state != .running { return .replay(existing) }
                guard let lease = try acquireWorkerLease() else { return .replay(existing) }
                return try withExtendedLifetime(lease) {
                    try .replay(interruptFollowUpLocked(existing, now: now))
                }
            }

            guard let lease = try acquireWorkerLease() else { throw StoreError.busy }
            try maintainFollowUpsLocked(source: source, now: now)
            let folder = try followUpDirectory()
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            let records = try FileManager.default.contentsOfDirectory(atPath: folder.path)
            guard records.count < 128 else { throw FollowUpError.capacity }
            try writeFollowUpRecordLocked(.init(request: request, snapshotVersion: source.version, createdAt: now))
            return .started(FollowUpWorker(request: request, source: source, lease: lease))
        }
    }

    func cancelFollowUp(_ requestID: UUID) throws {
        try withLock {
            var record = try authorizedFollowUpRecordLocked(requestID)
            guard record.state == .running else { return }
            record.cancellationRequested = true
            try writeFollowUpRecordLocked(record)
        }
    }

    func finishFollowUp(_ worker: FollowUpWorker, result: Data?, now: Date = .now) throws {
        try withLock {
            let request = worker.request
            var record = try authorizedFollowUpRecordLocked(request.id)
            guard record.request == request, record.snapshotVersion == worker.source.version,
                  record.state == .running else { throw FollowUpError.unavailable }

            if let result, !record.cancellationRequested {
                guard result.count <= 16 * 1024 else { throw FollowUpError.resultTooLarge }
                try result.write(to: followUpResultURL(request.id), options: .atomic)
                record.state = .completed
            } else {
                try removeFollowUpFile(try followUpResultURL(request.id))
                record.state = .cancelled
            }
            record.finishedAt = now
            try writeFollowUpRecordLocked(record)
            withExtendedLifetime(worker.lease) {}
        }
    }

    func readFollowUpResult(_ requestID: UUID, now: Date = .now) throws -> Data {
        try withLock {
            let record = try authorizedFollowUpRecordLocked(requestID)
            guard record.state == .completed, let finishedAt = record.finishedAt else {
                throw FollowUpError.unavailable
            }
            guard now.timeIntervalSince(finishedAt) < Self.followUpResultLifetime else {
                throw FollowUpError.expiredResult
            }
            let data = try Data(contentsOf: followUpResultURL(requestID))
            guard data.count <= 16 * 1024 else { throw FollowUpError.resultTooLarge }
            return data
        }
    }

    private static let followUpResultLifetime: TimeInterval = 24 * 60 * 60
    private static let followUpReceiptLifetime: TimeInterval = 7 * 24 * 60 * 60

    private func authorizedFollowUpRecordLocked(_ requestID: UUID) throws -> FollowUpRecord {
        guard let record = try readFollowUpRecordLocked(requestID) else { throw FollowUpError.unavailable }
        let request = record.request
        let source = try readFollowUpSourceLocked(catalogID: request.catalogID, jobID: request.sourceJobID)
        guard source.version == record.snapshotVersion else { throw FollowUpError.unavailable }
        return record
    }

    private func interruptFollowUpLocked(_ record: FollowUpRecord, now: Date) throws -> FollowUpRecord {
        var record = record
        try removeFollowUpFile(try followUpResultURL(record.request.id))
        record.state = record.cancellationRequested ? .cancelled : .interrupted
        record.finishedAt = now
        try writeFollowUpRecordLocked(record)
        return record
    }

    // The worker lock is held here, so a running record belongs to an exited process.
    private func maintainFollowUpsLocked(source: FollowUpSourceSnapshot, now: Date) throws {
        let folder = try followUpDirectory()
        let entries: [URL]
        do {
            entries = try FileManager.default.contentsOfDirectory(
                at: folder, includingPropertiesForKeys: nil
            )
        } catch let error as CocoaError where error.code == .fileReadNoSuchFile {
            return
        }
        for entry in entries {
            guard let id = UUID(uuidString: entry.lastPathComponent),
                  let record = try readFollowUpRecordLocked(id),
                  record.request.sourceJobID == source.jobID, record.request.catalogID == source.catalogID,
                  record.snapshotVersion == source.version else {
                try removeFollowUpFile(entry)
                continue
            }
            if record.state == .running {
                _ = try interruptFollowUpLocked(record, now: now)
            } else if let finishedAt = record.finishedAt {
                let age = now.timeIntervalSince(finishedAt)
                if age >= Self.followUpReceiptLifetime {
                    try removeFollowUpFile(entry)
                } else if age >= Self.followUpResultLifetime {
                    try removeFollowUpFile(try followUpResultURL(id))
                }
            }
        }
    }

    private func followUpDirectory() throws -> URL {
        guard let directory else { throw CatalogGrantStore.StoreError.unavailable }
        return directory.appendingPathComponent("follow-up-requests", isDirectory: true)
    }

    private func followUpRecordURL(_ id: UUID) throws -> URL {
        try followUpDirectory().appendingPathComponent(id.uuidString, isDirectory: true)
            .appendingPathComponent("request.json")
    }

    private func followUpResultURL(_ id: UUID) throws -> URL {
        try followUpRecordURL(id).deletingLastPathComponent().appendingPathComponent("result.json")
    }

    private func readFollowUpRecordLocked(_ id: UUID) throws -> FollowUpRecord? {
        do {
            let record = try JSONDecoder().decode(FollowUpRecord.self, from: Data(contentsOf: followUpRecordURL(id)))
            guard record.version == 1, record.kind == "photoAssessment", record.request.id == id else {
                throw StoreError.unsupportedFormat
            }
            return record
        } catch let error as CocoaError where error.code == .fileReadNoSuchFile {
            return nil
        }
    }

    private func writeFollowUpRecordLocked(_ record: FollowUpRecord) throws {
        let url = try followUpRecordURL(record.request.id)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try JSONEncoder().encode(record).write(to: url, options: .atomic)
    }

    private func removeFollowUpRequestsLocked() throws {
        try removeFollowUpFile(try followUpDirectory())
    }

    private func removeFollowUpFile(_ url: URL) throws {
        do {
            try FileManager.default.removeItem(at: url)
        } catch let error as CocoaError where error.code == .fileNoSuchFile {}
    }
}

nonisolated extension AnalysisJobStore.FollowUpRequest.Target {
    fileprivate func photoIDs(in source: FollowUpSourceSnapshot) throws -> [String] {
        let ids: [String]
        switch self {
        case let .photos(selected):
            ids = selected
        case let .burst(id):
            let burst = try source.burst(id: id)
            ids = [burst.recommendedPhotoID, burst.alternatePhotoID].compactMap { $0 }.reduce(into: []) { ids, id in
                if !ids.contains(id) { ids.append(id) }
            }
        }
        guard (1 ... 4).contains(ids.count), Set(ids).count == ids.count,
              ids.allSatisfy({ source.photos[$0] != nil }) else { throw AnalysisJobStore.FollowUpError.invalidRequest }
        return ids
    }
}

nonisolated struct CatalogSetupRequest: Codable, Sendable {
    enum State: String, Codable, Sendable {
        case pendingApproval, queued, denied, failed
    }

    static let maximumHintScalars = 512

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
    var usesExactHint: Bool?

    var expiresAt: Date { createdAt.addingTimeInterval(600) }
    var isExpired: Bool { isExpired(at: .now) }

    func isExpired(at now: Date) -> Bool { now >= expiresAt }

    func matches(_ proposed: Self) -> Bool {
        guard jobType == proposed.jobType, let hint = proposed.catalogHint else { return false }
        func matchesHint(_ value: String) -> Bool {
            if let catalogHint { return catalogHint == value }
            return hintDigest == Self.digest(value)
        }
        if matchesHint(hint) { return true }
        guard usesExactHint != true else { return false }
        // Older helpers replaced control characters before writing the receipt.
        let legacyHint = String(String.UnicodeScalarView(hint.unicodeScalars.prefix(Self.maximumHintScalars).map {
            CharacterSet.controlCharacters.contains($0) ? " " : $0
        }))
        return matchesHint(legacyHint)
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

    enum StoreError: Error, Equatable {
        case pendingRequest, expiredRequest, invalidHint, storageFull(retryAt: Date?)
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
    // Keep expired IDs separately so they can still reject stale retries.
    private static let expiredReceiptLimit = 7 * receiptLimit
    private static let denialWindow: TimeInterval = 15 * 60
    private static let denialDelays: [TimeInterval] = [10, 20, 40, 80, 160, 300]

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
        guard now.timeIntervalSince(stored.createdAt) < Self.replayWindow else { throw StoreError.expiredRequest }
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
            let maximumHintScalars = CatalogSetupRequest.maximumHintScalars
            guard let hint = request.catalogHint,
                  hint.unicodeScalars.prefix(maximumHintScalars + 1).count <= maximumHintScalars else {
                throw StoreError.invalidHint
            }
            guard pending == nil else { throw StoreError.pendingRequest }
            if let delay = retained.denialRetryAt?.timeIntervalSince(now), delay > 0 {
                throw StoreError.denialCooldown(secondsRemaining: Int(delay.rounded(.up)))
            }
            guard retained.count < Self.receiptLimit else {
                throw StoreError.storageFull(retryAt: retained.nextSlotAt)
            }
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
    ) throws -> (count: Int, nextSlotAt: Date?, denialRetryAt: Date?) {
        let root = try root()
        let files: [URL]
        do {
            files = try FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil)
        } catch let error as CocoaError where error.code == .fileReadNoSuchFile {
            return (0, nil, nil)
        }
        var protectedCount = 0
        var recentDenials: [Date] = []
        var replayable: [(url: URL, createdAt: Date)] = []
        var expired: [(url: URL, createdAt: Date)] = []
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
                if stored.state == .denied, let deniedAt = stored.deniedAt,
                   now.timeIntervalSince(deniedAt) < Self.denialWindow {
                    recentDenials.append(min(now, deniedAt))
                }
                if now.timeIntervalSince(stored.createdAt) < Self.replayWindow {
                    replayable.append((url, stored.createdAt))
                } else {
                    expired.append((url, stored.createdAt))
                }
            }
        }
        if let currentJob, let id = currentJob.setupRequestId,
           !files.contains(where: { $0.lastPathComponent == id.uuidString }) {
            try saveLocked(queuedReceipt(currentJob, id: id, existing: nil))
            protectedCount += 1
        }
        let available = max(0, Self.receiptLimit - protectedCount)
        func newestFirst(_ lhs: (url: URL, createdAt: Date), _ rhs: (url: URL, createdAt: Date)) -> Bool {
            if lhs.createdAt == rhs.createdAt { return lhs.url.lastPathComponent < rhs.url.lastPathComponent }
            return lhs.createdAt > rhs.createdAt
        }
        let ordered = replayable.sorted(by: newestFirst)
        for entry in ordered.dropFirst(available) { try remove(entry.url) }
        for entry in expired.sorted(by: newestFirst).dropFirst(Self.expiredReceiptLimit) {
            try remove(entry.url)
        }
        let kept = ordered.prefix(available)
        let nextSlotAt = kept.last?.createdAt.addingTimeInterval(Self.replayWindow)
        let denialRetryAt = recentDenials.max().map { deniedAt in
            let delay = Self.denialDelays[min(recentDenials.count, Self.denialDelays.count) - 1]
            return deniedAt.addingTimeInterval(delay)
        }
        return (protectedCount + kept.count, nextSlotAt, denialRetryAt)
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
