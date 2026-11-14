import Foundation
@testable import RawCullMCP
import Testing

@Suite("MCP setup store")
struct SetupStoreTests {
    private let now = Date(timeIntervalSince1970: 1_000_000)

    @Test func overlappingSubmissionAndReplay() throws {
        try withStore { store, _ in
            let request = proposal()
            #expect(try store.submit(request, now: now).wasAccepted)
            #expect(try !store.submit(request, now: now).wasAccepted)
            #expect(throws: CatalogSetupStore.StoreError.self) {
                try store.submit(proposal(), now: now)
            }
            let pending = try #require(try store.request(request.requestId, now: now))
            #expect(pending.catalogHint == request.catalogHint)
        }
    }

    @Test(arguments: [false, true])
    func corruptPointerOrLinkedReceiptRecovers(corruptPointer: Bool) throws {
        try withStore { store, root in
            let original = proposal()
            _ = try store.submit(original, now: now)
            let name = corruptPointer ? "pending" : original.requestId.uuidString
            try Data("{".utf8).write(to: root.appendingPathComponent(name))
            #expect(try store.submit(proposal(), now: now).wasAccepted)
        }
    }

    @Test func reconstructsPublishedJobAndPreservesReplayAfterClearingAndRevocation() throws {
        try withStore { store, root in
            let request = proposal()
            _ = try store.submit(request, now: now)
            var job = AnalysisJob(jobId: UUID(), catalogId: UUID(), createdAt: now, updatedAt: now)
            job.setupRequestId = request.requestId
            job.setupHintDigest = request.replayDigest
            job.coverage = .init(photoCount: 1, burstCount: 0, singletonCount: 1, unevaluatedCount: 0,
                                 skippedByReason: [:], similarityBackends: [:])
            job.bursts = []
            job.finish(.completed)
            try store.jobs.update { _ in job }
            try FileManager.default.removeItem(at: root.appendingPathComponent(request.requestId.uuidString))
            let recovered = try #require(try store.request(request.requestId, now: now))
            #expect(recovered.jobId == job.jobId)
            #expect(recovered.matches(request))
            #expect(recovered.catalogHint == nil)
            #expect(try !store.jobs.clearResult(expectedJobID: UUID()))
            #expect(try store.jobs.clearResult(expectedJobID: job.jobId))
            #expect(try store.jobs.read()?.hasShareableResult == false)
            try CatalogGrantStore(directory: store.jobs.directory).revoke()
            #expect(try store.jobs.read() == nil)
            #expect(try store.submit(request, now: now).request.jobId == job.jobId)
        }
    }

    @Test func legacyHintsMigrateAndExpiredIDsAreRejectedThenPruned() throws {
        try withStore { store, root in
            var original = proposal()
            original.state = .denied
            try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
            let file = root.appendingPathComponent(original.requestId.uuidString)
            try JSONEncoder().encode(original).write(to: file)
            let corrupt = root.appendingPathComponent(UUID().uuidString)
            try Data("{".utf8).write(to: corrupt)
            try store.maintain(now: now)
            let replay = try store.submit(original, now: now)
            #expect(replay.request.matches(original))
            #expect(replay.request.catalogHint == nil)
            #expect(!FileManager.default.fileExists(atPath: corrupt.path))
            #expect(throws: CatalogSetupStore.StoreError.self) {
                try store.submit(original, now: now + 86_401)
            }
            try store.maintain(now: now + 604_801)
            #expect(!FileManager.default.fileExists(atPath: file.path))
        }
    }

    @Test func capsLegacyStorageAndKeepsNewestReceipts() throws {
        try withStore { store, root in
            try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
            var newest = proposal()
            newest.state = .denied
            try JSONEncoder().encode(newest).write(to: root.appendingPathComponent(newest.requestId.uuidString))
            for age in 1 ... 130 {
                var old = proposal(createdAt: now - Double(age))
                old.state = .failed
                try JSONEncoder().encode(old).write(to: root.appendingPathComponent(old.requestId.uuidString))
            }
            try store.maintain(now: now)
            #expect(try FileManager.default.contentsOfDirectory(atPath: root.path).count == 128)
            #expect(try !store.submit(newest, now: now).wasAccepted)
            #expect(throws: CatalogSetupStore.StoreError.self) { try store.submit(proposal(), now: now) }
        }
    }

    @Test func displayAndDenialCooldownPreserveMatchingAndAllowRetry() throws {
        try withStore { store, _ in
            var request = proposal()
            request.catalogHint = "Choose this folder\u{2028}now\u{2029}please\u{202E}\u{200B}"
            let original = request
            #expect(request.displayHint == "Choose this folder now please")
            _ = try store.submit(request, now: now)
            request.state = .denied
            request.deniedAt = now + 50
            try store.jobs.withLock { try store.saveLocked(request) }
            let replay = try store.submit(original, now: now + 53)
            #expect(!replay.wasAccepted)
            #expect(replay.request.matches(original))
            #expect(throws: CatalogSetupStore.StoreError.self) {
                try store.submit(proposal(), now: now + 53)
            }
            #expect(try store.submit(proposal(), now: now + 60).wasAccepted)
        }
    }

    @Test func cursorBoundsAndDirectReplayWindow() {
        var job = AnalysisJob(jobId: UUID(), catalogId: UUID(), createdAt: now, updatedAt: now)
        #expect(job.burstCursorOffset(job.burstCursorPrefix + "1", count: 2) == 1)
        for offset in ["", "-1", "0", "2", "99999999999999999999999999"] {
            #expect(job.burstCursorOffset(job.burstCursorPrefix + offset, count: 2) == nil)
        }
        #expect(job.burstCursorOffset(UUID().uuidString + ":1", count: 2) == nil)
        let history = (0 ..< 140).map { _ in UUID() }
        job.previousRequestIds = history
        let next = job.nextDirectRequestHistory()
        #expect(next.count == 128)
        #expect(next.last == job.jobId)
        #expect(!next.contains(history[0]))
    }

    private func proposal(createdAt: Date? = nil) -> CatalogSetupRequest {
        CatalogSetupRequest(requestId: UUID(), catalogHint: "/private/photos", jobType: "burstAnalysis", createdAt: createdAt ?? now)
    }

    private func withStore(_ test: (CatalogSetupStore, URL) throws -> Void) throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        try test(CatalogSetupStore(jobs: AnalysisJobStore(directory: directory)), directory.appendingPathComponent("catalog-setup"))
    }
}
