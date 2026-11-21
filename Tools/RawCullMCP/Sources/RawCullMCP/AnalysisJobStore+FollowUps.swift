import CryptoKit
import Darwin
import Dispatch
import Foundation

/// Internal follow-up storage. The request record is the publication marker for its result.
nonisolated extension AnalysisJobStore {
    struct FollowUpRequest: Codable, Equatable, Sendable {
        enum Target: Codable, Equatable, Sendable {
            case photos([String])
            case burst(String)

            var burstID: String? {
                guard case let .burst(id) = self else { return nil }
                return id
            }
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

    struct FollowUpRecord: Codable, Equatable, Sendable {
        enum State: String, Codable, Sendable {
            case queued, running, completed, cancelled, interrupted, failed
        }

        var version = 1
        var kind = "photoAssessment"
        let request: FollowUpRequest
        let snapshotVersion: Int
        let createdAt: Date
        var finishedAt: Date?
        var state = State.running
        var errorCode: String?
        var resultCleared: Bool?
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
        case disabled
        case conflict
        case permissionRequired
        case invalidRequest
        case capacity
        case unavailable
        case expiredResult
        case resultTooLarge
    }

    private func followUpDisabledURL() throws -> URL {
        guard let directory else { throw CatalogGrantStore.StoreError.unavailable }
        return directory.appendingPathComponent("follow-up-disabled")
    }

    func followUpsEnabled() throws -> Bool {
        do {
            _ = try FileManager.default.attributesOfItem(atPath: followUpDisabledURL().path)
            return false
        } catch let error as CocoaError where error.code == .fileNoSuchFile || error.code == .fileReadNoSuchFile {
            return true
        }
    }

    func setFollowUpsEnabled(_ enabled: Bool) throws {
        try withLock {
            guard try followUpsEnabled() != enabled else { return }
            let marker = try followUpDisabledURL()
            // Removing the source also blocks helpers that predate this setting.
            try removeFollowUpSourceLocked()
            try removeFollowUpRequestsLocked()
            if enabled {
                try removeFollowUpFile(marker)
            } else {
                try Data().write(to: marker, options: .atomic)
            }
        }
    }

    struct FollowUpHost: Codable, Sendable {
        let version: Int
        let pid: Int32
        let bundlePath: String
        let timestamp: Date
        let supportsBurstAssessment: Bool?
    }

    func publishFollowUpHost(bundlePath: String) throws {
        let host = FollowUpHost(version: 1, pid: getpid(), bundlePath: bundlePath, timestamp: .now,
                                supportsBurstAssessment: true)
        try JSONEncoder().encode(host).write(to: followUpHostURL(), options: .atomic)
    }

    func hasFollowUpHost(bundlePath: String, requiresBurstAssessment: Bool = false) -> Bool {
        guard let host = try? JSONDecoder().decode(FollowUpHost.self, from: Data(contentsOf: followUpHostURL())),
              host.version == 1, host.pid > 0, host.bundlePath == bundlePath,
              abs(host.timestamp.timeIntervalSinceNow) < 10,
              !requiresBurstAssessment || host.supportsBurstAssessment == true else { return false }
        return kill(host.pid, 0) == 0 || errno == EPERM
    }

    private func followUpHostURL() throws -> URL {
        guard let directory else { throw CatalogGrantStore.StoreError.unavailable }
        return directory.appendingPathComponent("follow-up-host.json")
    }

    private func followUpInboxURL() throws -> URL {
        try followUpDirectory().appendingPathComponent("pending.json")
    }

    func queuedFollowUp() throws -> FollowUpRecord? {
        do {
            return try JSONDecoder().decode(FollowUpRecord.self, from: Data(contentsOf: followUpInboxURL()))
        } catch let error as CocoaError where error.code == .fileReadNoSuchFile { return nil }
    }

    func enqueueFollowUp(_ request: FollowUpRequest, now: Date = .now) throws -> FollowUpRecord {
        try withLock {
            let source = try validateFollowUpRequestLocked(request)
            if let existing = try readFollowUpRecordLocked(request.id),
               existing.finishedAt.map({ now.timeIntervalSince($0) < Self.followUpReceiptLifetime }) ?? true {
                guard existing.request == request else { throw FollowUpError.conflict }
                try checkFollowUpReplayLifetime(existing, now: now)
                return existing
            }
            var expired: FollowUpRecord?
            if let pending = try queuedFollowUp() {
                if pending.request.id == request.id {
                    guard pending.request == request else { throw FollowUpError.conflict }
                    return pending
                }
                guard now.timeIntervalSince(pending.createdAt) >= 120 else { throw StoreError.busy }
                expired = pending
            }
            guard let lease = try acquireWorkerLease() else { throw StoreError.busy }
            return try withExtendedLifetime(lease) {
                try maintainFollowUpsLocked(source: source, now: now)
                if var expired {
                    expired.state = .failed
                    expired.errorCode = "pickupTimeout"
                    expired.finishedAt = now
                    try writeFollowUpRecordLocked(expired)
                    try removeFollowUpFile(followUpInboxURL())
                }
                let folder = try followUpDirectory()
                try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
                guard try FileManager.default.contentsOfDirectory(atPath: folder.path).filter({ UUID(uuidString: $0) != nil }).count < 128 else {
                    throw FollowUpError.capacity
                }
                var record = FollowUpRecord(request: request, snapshotVersion: source.version, createdAt: now)
                record.state = .queued
                try JSONEncoder().encode(record).write(to: followUpInboxURL(), options: .atomic)
                return record
            }
        }
    }

    func replayFollowUp(_ request: FollowUpRequest, now: Date = .now) throws -> FollowUpRecord? {
        try withLock {
            _ = try validateFollowUpRequestLocked(request)
            let record = try readFollowUpRecordLocked(request.id) ?? queuedFollowUp()
            guard var record, record.request.id == request.id else { return nil }
            if let finalized = record.finishedAt, now.timeIntervalSince(finalized) >= Self.followUpReceiptLifetime {
                return nil
            }
            guard record.request == request else { throw FollowUpError.conflict }
            try checkFollowUpReplayLifetime(record, now: now)
            if record.state == .queued, now.timeIntervalSince(record.createdAt) >= 120 {
                record.state = .failed
                record.errorCode = "pickupTimeout"
            } else if record.state == .running, let lease = try acquireWorkerLease() {
                return try withExtendedLifetime(lease) {
                    try interruptFollowUpLocked(record, now: now)
                }
            }
            return record
        }
    }

    func followUpStatus(_ requestID: UUID) throws -> FollowUpRecord {
        try withLock {
            guard try followUpsEnabled() else { throw FollowUpError.disabled }
            if try readFollowUpRecordLocked(requestID) != nil {
                let record = try authorizedFollowUpRecordLocked(requestID)
                if record.state == .running, let lease = try acquireWorkerLease() {
                    return try withExtendedLifetime(lease) {
                        try interruptFollowUpLocked(record, now: .now)
                    }
                }
                return record
            }
            guard var pending = try queuedFollowUp(), pending.request.id == requestID else {
                throw FollowUpError.unavailable
            }
            _ = try validateFollowUpRequestLocked(pending.request)
            if Date.now.timeIntervalSince(pending.createdAt) >= 120 {
                pending.state = .failed
                pending.errorCode = "pickupTimeout"
            }
            return pending
        }
    }

    func recentFollowUps(now: Date = .now) throws -> [FollowUpRecord] {
        guard try FileManager.default.fileExists(atPath: followUpDirectory().path) else { return [] }
        return try withLock {
            guard let job = try read(),
                  let source = try? readFollowUpSourceLocked(catalogID: job.catalogId, jobID: job.jobId) else { return [] }
            return try Array(recentFollowUpsLocked(source: source, now: now).prefix(5))
        }
    }

    private func recentFollowUpsLocked(source: FollowUpSourceSnapshot, now: Date) throws -> [FollowUpRecord] {
        let entries = try FileManager.default.contentsOfDirectory(atPath: followUpDirectory().path)
        var records = try entries.compactMap { name -> FollowUpRecord? in
            guard let id = UUID(uuidString: name) else { return nil }
            return try readFollowUpRecordLocked(id)
        }
        if let pending = try queuedFollowUp(), !records.contains(where: { $0.request.id == pending.request.id }),
           now.timeIntervalSince(pending.createdAt) < 120 {
            records.append(pending)
        }
        return records.filter {
            $0.request.sourceJobID == source.jobID && $0.request.catalogID == source.catalogID
                && $0.snapshotVersion == source.version && $0.resultCleared != true
                && ($0.finishedAt.map { now.timeIntervalSince($0) < Self.followUpResultLifetime } ?? true)
        }.sorted { $0.createdAt > $1.createdAt }
    }

    func readBurstAssessmentResults(now: Date = .now) throws -> (
        job: AnalysisJob, source: FollowUpSourceSnapshot, results: [(FollowUpRecord, Data)],
    )? {
        guard try FileManager.default.fileExists(atPath: followUpDirectory().path) else { return nil }
        return try withLock {
            guard let job = try read(), try followUpsEnabled() else { return nil }
            let source = try readFollowUpSourceLocked(catalogID: job.catalogId, jobID: job.jobId)
            let results = try recentFollowUpsLocked(source: source, now: now).compactMap { record -> (FollowUpRecord, Data)? in
                guard record.state == .completed, record.request.target.burstID != nil,
                      let data = try? readFollowUpResultLocked(record, now: now) else { return nil }
                return (record, data)
            }
            return (job, source, results)
        }
    }

    func clearFollowUpResult(_ requestID: UUID) throws {
        try withLock {
            var record = try authorizedFollowUpRecordLocked(requestID)
            guard record.state == .completed || record.state == .failed else { return }
            record.resultCleared = true
            try writeFollowUpRecordLocked(record)
            try removeFollowUpFile(followUpResultURL(requestID))
        }
    }

    private func validateFollowUpRequestLocked(_ request: FollowUpRequest) throws -> FollowUpSourceSnapshot {
        guard try followUpsEnabled() else { throw FollowUpError.disabled }
        let grant = try CatalogGrantStore(directory: directory).authorizedCatalog()
        if grant?.id != request.catalogID || grant?.analysisEnabled != true {
            guard let job = try read(), job.catalogId == request.catalogID, job.jobId == request.sourceJobID,
                  job.usesSetupApproval, job.allowsJobPhotoAccess == true
            else {
                throw FollowUpError.permissionRequired
            }
        }
        let source = try readFollowUpSourceLocked(catalogID: request.catalogID, jobID: request.sourceJobID)
        _ = try request.target.photoIDs(in: source)
        let supported = Set(["composition", "exposure", "subjectVisibility"])
        let fields = Set(request.rubric)
        guard !fields.isEmpty, fields.count == request.rubric.count, fields.isSubset(of: supported) else {
            throw FollowUpError.invalidRequest
        }
        return source
    }

    func beginFollowUp(_ request: FollowUpRequest, now: Date = .now) throws -> FollowUpAdmission {
        try withLock {
            let source = try validateFollowUpRequestLocked(request)
            if let pending = try queuedFollowUp() {
                guard pending.request == request, now.timeIntervalSince(pending.createdAt) < 120 else {
                    throw FollowUpError.unavailable
                }
            }
            if let existing = try readFollowUpRecordLocked(request.id),
               existing.finishedAt.map({ now.timeIntervalSince($0) < Self.followUpReceiptLifetime }) ?? true {
                guard existing.request == request, existing.snapshotVersion == source.version else {
                    throw FollowUpError.conflict
                }
                if existing.state != .running {
                    return .replay(existing)
                }
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
            try removeFollowUpFile(followUpInboxURL())
            return .started(FollowUpWorker(request: request, source: source, lease: lease))
        }
    }

    func cancelFollowUp(_ requestID: UUID) throws {
        try withLock {
            if var pending = try queuedFollowUp(), pending.request.id == requestID,
               try readFollowUpRecordLocked(requestID) == nil {
                _ = try validateFollowUpRequestLocked(pending.request)
                pending.state = .cancelled
                pending.finishedAt = .now
                try writeFollowUpRecordLocked(pending)
                try removeFollowUpFile(followUpInboxURL())
                return
            }
            var record = try authorizedFollowUpRecordLocked(requestID)
            guard record.state == .running else { return }
            record.cancellationRequested = true
            try writeFollowUpRecordLocked(record)
        }
    }

    func finishFollowUp(_ worker: FollowUpWorker, result: Data?, errorCode: String? = nil, now: Date = .now) throws {
        try withLock {
            let request = worker.request
            var record = try authorizedFollowUpRecordLocked(request.id)
            guard record.request == request, record.snapshotVersion == worker.source.version,
                  record.state == .running else { throw FollowUpError.unavailable }

            if let result, !record.cancellationRequested {
                guard result.count <= 16 * 1024 else { throw FollowUpError.resultTooLarge }
                try result.write(to: followUpResultURL(request.id), options: .atomic)
                record.state = errorCode == nil ? .completed : .failed
            } else {
                try removeFollowUpFile(followUpResultURL(request.id))
                record.state = errorCode != nil && !record.cancellationRequested ? .failed : .cancelled
            }
            record.errorCode = record.state == .failed ? errorCode : nil
            record.finishedAt = now
            try writeFollowUpRecordLocked(record)
            withExtendedLifetime(worker.lease) {}
        }
    }

    func readFollowUpResult(_ requestID: UUID, now: Date = .now) throws -> Data {
        try withLock {
            let record = try authorizedFollowUpRecordLocked(requestID, now: now)
            return try readFollowUpResultLocked(record, now: now)
        }
    }

    private func readFollowUpResultLocked(_ record: FollowUpRecord, now: Date) throws -> Data {
        guard record.state == .completed || record.state == .failed, record.resultCleared != true,
              let finishedAt = record.finishedAt
        else {
            throw FollowUpError.unavailable
        }
        guard now.timeIntervalSince(finishedAt) < Self.followUpResultLifetime else {
            throw FollowUpError.expiredResult
        }
        let data = try Data(contentsOf: followUpResultURL(record.request.id))
        guard data.count <= 16 * 1024 else { throw FollowUpError.resultTooLarge }
        return data
    }

    private static let followUpResultLifetime: TimeInterval = 24 * 60 * 60
    private static let followUpReceiptLifetime: TimeInterval = 7 * 24 * 60 * 60

    private func checkFollowUpReplayLifetime(_ record: FollowUpRecord, now: Date) throws {
        if let finishedAt = record.finishedAt, now.timeIntervalSince(finishedAt) >= Self.followUpResultLifetime {
            throw FollowUpError.expiredResult
        }
    }

    private func authorizedFollowUpRecordLocked(_ requestID: UUID, now: Date = .now) throws -> FollowUpRecord {
        guard try followUpsEnabled() else { throw FollowUpError.disabled }
        guard let record = try readFollowUpRecordLocked(requestID),
              record.finishedAt.map({ now.timeIntervalSince($0) < Self.followUpReceiptLifetime }) ?? true
        else {
            throw FollowUpError.unavailable
        }
        let request = record.request
        // Every receipt operation rechecks the current source and its saved grant
        // or one-time job approval under the same lock as revocation.
        let source = try readFollowUpSourceLocked(catalogID: request.catalogID, jobID: request.sourceJobID)
        guard source.version == record.snapshotVersion else { throw FollowUpError.unavailable }
        return record
    }

    private func interruptFollowUpLocked(_ record: FollowUpRecord, now: Date) throws -> FollowUpRecord {
        var record = record
        try removeFollowUpFile(followUpResultURL(record.request.id))
        record.state = record.cancellationRequested ? .cancelled : .interrupted
        record.finishedAt = now
        try writeFollowUpRecordLocked(record)
        return record
    }

    /// The worker lock is held here, so a running record belongs to an exited process.
    private func maintainFollowUpsLocked(source: FollowUpSourceSnapshot, now: Date) throws {
        let folder = try followUpDirectory()
        let entries: [URL]
        do {
            entries = try FileManager.default.contentsOfDirectory(
                at: folder, includingPropertiesForKeys: nil,
            )
        } catch let error as CocoaError where error.code == .fileReadNoSuchFile {
            return
        }
        for entry in entries where entry.lastPathComponent != "pending.json" {
            guard let id = UUID(uuidString: entry.lastPathComponent),
                  let record = try readFollowUpRecordLocked(id),
                  record.request.sourceJobID == source.jobID, record.request.catalogID == source.catalogID,
                  record.snapshotVersion == source.version
            else {
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
                    try removeFollowUpFile(followUpResultURL(id))
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

    func removeFollowUpRequestsLocked() throws {
        try removeFollowUpFile(followUpDirectory())
    }

    func removeFollowUpFile(_ url: URL) throws {
        do {
            try FileManager.default.removeItem(at: url)
        } catch let error as CocoaError where error.code == .fileNoSuchFile {}
    }
}

nonisolated extension AnalysisJobStore.FollowUpRequest.Target {
    func photoIDs(in source: FollowUpSourceSnapshot) throws -> [String] {
        let ids: [String]
        switch self {
        case let .photos(selected):
            ids = selected

        case let .burst(id):
            let burst = try source.burst(id: id)
            ids = [burst.recommendedPhotoID,
                   burst.alternatePhotoID == burst.recommendedPhotoID ? nil : burst.alternatePhotoID].compactMap { $0 }
            guard ids.allSatisfy({ burst.photoIDs.contains($0) && (burst.ranks[$0] ?? 0) > 0 }) else {
                throw FollowUpSourceSnapshot.SourceError.invalidTarget
            }
        }
        guard (1 ... 4).contains(ids.count), Set(ids).count == ids.count,
              ids.allSatisfy({ source.photos[$0] != nil }) else { throw AnalysisJobStore.FollowUpError.invalidRequest }
        return ids
    }
}
