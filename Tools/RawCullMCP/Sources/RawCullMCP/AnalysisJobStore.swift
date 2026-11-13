import Darwin
import Foundation

nonisolated struct AnalysisJob: Codable, Sendable {
    enum State: String, Codable, Sendable {
        case queued, running, completed, cancelled, failed

        var isActive: Bool { self == .queued || self == .running }
    }

    let jobId: UUID
    let catalogId: UUID
    let createdAt: Date
    var updatedAt: Date
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
    var previousRequestIds: [UUID]?

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
        let candidates: [Candidate]
    }

    struct Candidate: Codable, Sendable {
        let photoId: String
        let name: String
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
}

/// One job slot shared by the app and any number of helper processes. The lock
/// file is never replaced. Every state transition replaces the JSON atomically.
nonisolated struct AnalysisJobStore: Sendable {
    static let heartbeatTimeout: TimeInterval = 45
    let directory: URL?

    func read() throws -> AnalysisJob? {
        guard let directory else { throw CatalogGrantStore.StoreError.unavailable }
        do {
            return try JSONDecoder().decode(
                AnalysisJob.self,
                from: Data(contentsOf: directory.appendingPathComponent("analysis-job.json"))
            )
        } catch let error as CocoaError where error.code == .fileReadNoSuchFile {
            return nil
        }
    }

    /// The update returns a new record only when it needs to change the slot.
    @discardableResult
    func update(_ change: (AnalysisJob?) throws -> AnalysisJob?) throws -> AnalysisJob? {
        guard let directory else { throw CatalogGrantStore.StoreError.unavailable }
        let lock = directory.appendingPathComponent("analysis-job.lock")
        let descriptor = open(lock.path, O_CREAT | O_RDWR | O_NOFOLLOW | O_CLOEXEC, S_IRUSR | S_IWUSR)
        guard descriptor >= 0 else { throw POSIXError(.EIO) }
        defer { close(descriptor) }
        guard flock(descriptor, LOCK_EX) == 0 else { throw POSIXError(.EIO) }
        defer { flock(descriptor, LOCK_UN) }

        let current = try read()
        if var next = try change(current) {
            next.updatedAt = .now
            try JSONEncoder().encode(next).write(
                to: directory.appendingPathComponent("analysis-job.json"), options: .atomic
            )
            return next
        }
        return current
    }

    func expireInterruptedJob() throws -> AnalysisJob? {
        // Use the lock only for an expired job. An app heartbeat may race this read.
        let job = try read()
        guard let job, job.state.isActive,
              Date.now.timeIntervalSince(job.updatedAt) > Self.heartbeatTimeout
        else { return job }

        return try update { current in
            guard var current, current.state.isActive,
                  Date.now.timeIntervalSince(current.updatedAt) > Self.heartbeatTimeout
            else { return nil }
            current.finish(.failed, message: "RawCull stopped responding. Start a new job with a new request ID.")
            return current
        }
    }
}
