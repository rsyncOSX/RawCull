import CryptoKit
import Darwin
import Dispatch
import Foundation

nonisolated struct AnalysisJob: Codable, Sendable {
    static let currentFormatVersion = 2

    enum State: String, Codable, Sendable {
        case queued, running, completed, cancelled, failed

        var isActive: Bool {
            self == .queued || self == .running
        }
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
    var allowsJobPhotoAccess: Bool?
    var usesSetupApproval: Bool {
        setupRequestId != nil && usesSavedGrant != true
    }

    var hasShareableResult: Bool {
        state == .completed && coverage != nil && bursts != nil
    }

    var catalogDisplayName: String?
    var setupHintDigest: Data?
    var resultCleared: Bool?
    var previousRequestIds: [UUID]?
    private(set) var formatVersion: Int? = 1
    var usesWorkerLease: Bool {
        formatVersion == Self.currentFormatVersion && state == .running
    }

    func canPublish(for job: Self) -> Bool {
        jobId == job.jobId && catalogId == job.catalogId && state == .running && !cancellationRequested
    }

    var burstCursorPrefix: String {
        "\(catalogId.uuidString):\(jobId.uuidString):"
    }

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
        var confidence: String
        var reasons: [String]
        var cautions: [String]
        var candidates: [Candidate]
    }

    struct Candidate: Codable, Sendable {
        let photoId: String
        var name: String
        let score: Double?
        var confidence: String
        var reasons: [String]
        var cautions: [String]
    }

    mutating func finish(_ state: State, message: String? = nil) {
        self.state = state
        if !state.isActive {
            formatVersion = 1
        }
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

    struct Photo: Codable, Equatable, Sendable {
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
                  fileComponents.starts(with: rootComponents, by: { $0.utf8.elementsEqual($1.utf8) })
            else {
                throw SourceError.invalidTarget
            }
            let values = try file.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey, .contentModificationDateKey])
            guard values.isRegularFile == true, values.fileSize.map(Int64.init) == size,
                  values.contentModificationDate == modified
            else {
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

    /// The caller retains the authorized catalog's security-scoped access.
    func resolve(photoID: String, in catalog: URL) throws -> URL {
        guard let photo = photos[photoID] else { throw SourceError.invalidTarget }
        return try photo.resolve(in: catalog)
    }

    func burst(id: String) throws -> Burst {
        guard let burst = bursts[id] else { throw SourceError.invalidTarget }
        return burst
    }
}
