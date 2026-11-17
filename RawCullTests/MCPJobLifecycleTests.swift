import Darwin
import Foundation
@testable import RawCull
import Testing

@Suite("MCP job lifecycle")
struct MCPJobLifecycleTests {
    private let now = Date(timeIntervalSince1970: 1000)

    @Test func `live worker survives stale heartbeat and owns cancellation`() throws {
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

    @Test func `interrupted worker fails immediately`() throws {
        try withStore { store, _ in
            var job = AnalysisJob(jobId: UUID(), catalogId: UUID(), createdAt: now, updatedAt: now)
            job.claim()
            try store.update { _ in job }
            let recovered = try #require(try store.expireInterruptedJob(now: now))
            #expect(recovered.state == .failed)
            #expect(recovered.message?.contains("worker exited") == true)
        }
    }

    @Test func `legacy heartbeat uses awake uptime and falls back on reboot`() {
        var job = AnalysisJob(jobId: UUID(), catalogId: UUID(), createdAt: now, updatedAt: now)
        job.state = .running
        job.heartbeatAt = now
        job.heartbeatUptime = 10_000_000_000
        job.heartbeatBootID = "boot"
        #expect(!job.isExpired(at: now + 120, uptime: 12_000_000_000, bootID: "boot"))
        #expect(job.isExpired(at: now + 120, uptime: 12_000_000_000, bootID: "reboot"))
    }

    @Test func `publication checks ownership and cancellation`() {
        var job = AnalysisJob(jobId: UUID(), catalogId: UUID(), createdAt: now, updatedAt: now)
        job.claim()
        var current = job
        #expect(current.canPublish(for: job))
        current.cancellationRequested = true
        #expect(!current.canPublish(for: job))
        let replacement = AnalysisJob(jobId: UUID(), catalogId: job.catalogId, createdAt: now, updatedAt: now)
        #expect(!current.canPublish(for: replacement))
    }

    @Test func `lock contention is retryable`() throws {
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

    @Test func `malformed record is protected while worker owns slot`() throws {
        try withStore { store, file in
            try Data("{".utf8).write(to: file)
            do {
                let lease = try #require(try store.acquireWorkerLease())
                #expect(throws: AnalysisJobStore.StoreError.damagedActiveJob) { try store.readRecovering() }
                #expect(FileManager.default.fileExists(atPath: file.path))
                withExtendedLifetime(lease) {}
            }
            #expect(throws: AnalysisJobStore.StoreError.recoveredDamagedJob) { try store.readRecovering() }
            #expect(!FileManager.default.fileExists(atPath: file.path))
            let damaged = file.deletingLastPathComponent().appendingPathComponent("analysis-job.damaged")
            #expect(try Data(contentsOf: damaged) == Data("{".utf8))
        }
    }

    @Test func `unsupported format and IO failure are preserved`() throws {
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

    @Test(arguments: [false, true])
    func `follow up source requires published result and current consent`(oneTimeApproval: Bool) throws {
        try withStore { store, jobFile in
            let catalogID = UUID()
            let jobID = UUID()
            let grantStore = CatalogGrantStore(directory: store.directory)
            if !oneTimeApproval {
                // Existing analysis grants may predate the follow-up consent flag.
                try grantStore.authorize(CatalogGrant(
                    id: catalogID, displayName: "Fixture", summary: nil, analysisEnabled: true,
                ))
            }
            var job = AnalysisJob(jobId: jobID, catalogId: catalogID, createdAt: now, updatedAt: now)
            job.setupRequestId = UUID()
            job.claim()
            try store.update { _ in job }
            let memberIDs = (0 ..< 7).map { "photo-\($0)" }
            let snapshot = FollowUpSourceSnapshot(jobID: jobID, catalogID: catalogID, photos: [
                memberIDs[6]: .init(relativePath: "fixture.ARW", size: 1, modified: now)
            ], bursts: [
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
            if oneTimeApproval {
                #expect(throws: FollowUpSourceSnapshot.SourceError.unavailable) {
                    try store.readFollowUpSource(catalogID: catalogID, jobID: jobID)
                }
                job.allowsJobPhotoAccess = true
                try store.update { _ in job }
            }
            let source = try store.readFollowUpSource(catalogID: catalogID, jobID: jobID)
            #expect(try source.burst(id: "burst").photoIDs == memberIDs)
            #expect(try source.burst(id: "burst").ranks[memberIDs[6]] == 1)
            #expect(throws: FollowUpSourceSnapshot.SourceError.unavailable) {
                try store.readFollowUpSource(catalogID: catalogID, jobID: UUID())
            }

            if !oneTimeApproval {
                let disabled = CatalogGrant(id: catalogID, displayName: "Fixture", summary: nil, analysisEnabled: false)
                try store.withLock { try grantStore.writeLocked(disabled) }
                #expect(throws: FollowUpSourceSnapshot.SourceError.unavailable) {
                    try store.readFollowUpSource(catalogID: catalogID, jobID: jobID)
                }
                let enabled = CatalogGrant(id: catalogID, displayName: "Fixture", summary: nil, analysisEnabled: true)
                try store.withLock { try grantStore.writeLocked(enabled) }
            }

            let assessment = AnalysisJobStore.FollowUpRequest(
                id: UUID(), catalogID: catalogID, sourceJobID: jobID,
                target: .burst("burst"), rubric: ["exposure"],
            )
            #expect(try store.enqueueFollowUp(assessment).state == .queued)
            #expect(try store.replayFollowUp(assessment)?.state == .queued)
            let other = AnalysisJobStore.FollowUpRequest(
                id: UUID(), catalogID: catalogID, sourceJobID: jobID,
                target: .burst("burst"), rubric: ["composition"],
            )
            #expect(throws: AnalysisJobStore.StoreError.busy) {
                try store.enqueueFollowUp(other)
            }
            let worker = try startFollowUp(assessment, in: store)
            #expect(try worker.request.target.photoIDs(in: worker.source) == [memberIDs[6]])
            try store.finishFollowUp(worker, result: nil, errorCode: "fixture")

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

    @Test(arguments: [
        (0, 6), (0, nil), (nil, 6), (0, 0), (nil, nil)
    ] as [(Int?, Int?)])
    func `burst target uses only saved picks`(recommendation: Int?, alternate: Int?) throws {
        let ids = (0 ..< 7).map { "photo-\($0)" }
        let photos = Dictionary(uniqueKeysWithValues: ids.map {
            ($0, FollowUpSourceSnapshot.Photo(relativePath: "\($0).ARW", size: 1, modified: now))
        })
        let burstID = "current-burst"
        let source = FollowUpSourceSnapshot(
            jobID: UUID(), catalogID: UUID(), photos: photos,
            bursts: [burstID: .init(photoIDs: ids, ranks: [ids[0]: 1, ids[6]: 2],
                                    recommendedPhotoID: recommendation.map { ids[$0] },
                                    alternatePhotoID: alternate.map { ids[$0] })],
        )
        let target = AnalysisJobStore.FollowUpRequest.Target.burst(burstID)
        let expected = [recommendation, recommendation == alternate ? nil : alternate].compactMap { $0 }
        if expected.isEmpty {
            #expect(throws: AnalysisJobStore.FollowUpError.invalidRequest) {
                try target.photoIDs(in: source)
            }
        } else {
            #expect(try target.photoIDs(in: source) == expected.map { ids[$0] })
        }
        #expect(throws: FollowUpSourceSnapshot.SourceError.invalidTarget) {
            try AnalysisJobStore.FollowUpRequest.Target.burst("previous-job-burst").photoIDs(in: source)
        }
    }

    @Test func `burst assessment requires host support while explicit photos accept legacy host`() throws {
        try withStore { store, jobFile in
            let bundlePath = "/fixture/RawCull.app"
            let hostFile = jobFile.deletingLastPathComponent().appendingPathComponent("follow-up-host.json")
            let legacyHost = AnalysisJobStore.FollowUpHost(
                version: 1, pid: getpid(), bundlePath: bundlePath, timestamp: .now, supportsBurstAssessment: nil,
            )
            try JSONEncoder().encode(legacyHost).write(to: hostFile)
            #expect(store.hasFollowUpHost(bundlePath: bundlePath))
            #expect(!store.hasFollowUpHost(bundlePath: bundlePath, requiresBurstAssessment: true))

            try store.publishFollowUpHost(bundlePath: bundlePath)
            #expect(store.hasFollowUpHost(bundlePath: bundlePath, requiresBurstAssessment: true))
        }
    }

    @Test func `follow up photo resolution rejects changes and symlink escape`() throws {
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

    @Test func `follow up resolution preserves unicode path and catalog identity`() throws {
        try withStore { store, jobFile in
            let request = try seedFollowUpSource(in: store)
            let root = jobFile.deletingLastPathComponent()
            let catalog = root.appendingPathComponent("catalog")
            let otherCatalog = root.appendingPathComponent("other-catalog")
            try FileManager.default.createDirectory(at: otherCatalog, withIntermediateDirectories: false)
            let original = catalog.appendingPathComponent("Cafe\u{301}.ARW")
            let sameName = otherCatalog.appendingPathComponent(original.lastPathComponent)
            try FileManager.default.copyItem(at: original, to: sameName)
            let worker = try startFollowUp(request, in: store)
            #expect(try worker.resolveTargets(in: catalog).map(\.path) == [
                original.resolvingSymlinksInPath().path
            ])
            #expect(throws: FollowUpSourceSnapshot.SourceError.unavailable) {
                try store.readFollowUpSource(catalogID: UUID(), jobID: request.sourceJobID)
            }
        }
    }

    @Test func `follow up reservation excludes other workers and keeps source readable`() throws {
        try withStore { store, _ in
            let request = try seedFollowUpSource(in: store)
            let worker = try startFollowUp(request, in: store)
            #expect(try store.acquireWorkerLease() == nil)
            #expect(try store.readFollowUpSource(catalogID: request.catalogID, jobID: request.sourceJobID).jobID
                == request.sourceJobID)
            let replacement = AnalysisJob(jobId: UUID(), catalogId: request.catalogID, createdAt: now, updatedAt: now)
            #expect(throws: AnalysisJobStore.StoreError.busy) {
                try store.update { _ in replacement }
            }
            guard case let .replay(active) = try store.beginFollowUp(request, now: now) else {
                Issue.record("An identical request started a second worker.")
                return
            }
            #expect(active.state == .running)
            let result = Data("{}".utf8)
            try store.finishFollowUp(worker, result: result, now: now)
            #expect(try store.readFollowUpResult(request.id, now: now) == result)
            #expect(throws: AnalysisJobStore.FollowUpError.expiredResult) {
                try store.readFollowUpResult(request.id, now: now + 24 * 60 * 60)
            }
            #expect(throws: AnalysisJobStore.FollowUpError.expiredResult) {
                try store.replayFollowUp(request, now: now + 24 * 60 * 60)
            }
            #expect(throws: AnalysisJobStore.FollowUpError.expiredResult) {
                try store.enqueueFollowUp(request, now: now + 24 * 60 * 60)
            }
            #expect(try store.replayFollowUp(request, now: now + 7 * 24 * 60 * 60) == nil)
        }
    }

    @Test(arguments: ["clear", "revoke", "cancel"])
    func `follow up invalidation prevents late publication`(_ action: String) throws {
        try withStore { store, _ in
            let request = try seedFollowUpSource(in: store)
            let worker = try startFollowUp(request, in: store)
            switch action {
            case "clear":
                #expect(try store.clearResult(expectedJobID: request.sourceJobID))

            case "revoke":
                try CatalogGrantStore(directory: store.directory).revoke()

            default:
                try store.cancelFollowUp(request.id)
            }
            let result = Data("{}".utf8)
            if action == "cancel" {
                try store.finishFollowUp(worker, result: result, now: now)
            } else {
                #expect(throws: AnalysisJobStore.FollowUpError.unavailable) {
                    try store.finishFollowUp(worker, result: result, now: now)
                }
            }
            #expect(throws: AnalysisJobStore.FollowUpError.unavailable) {
                try store.readFollowUpResult(request.id, now: now)
            }
        }
    }

    @Test func `abandoned follow up does not publish staged result`() throws {
        try withStore { store, jobFile in
            let request = try seedFollowUpSource(in: store)
            do {
                let worker = try startFollowUp(request, in: store)
                let stagedResult = jobFile.deletingLastPathComponent()
                    .appendingPathComponent("follow-up-requests")
                    .appendingPathComponent(request.id.uuidString)
                    .appendingPathComponent("result.json")
                try Data("{}".utf8).write(to: stagedResult)
                #expect(throws: AnalysisJobStore.FollowUpError.unavailable) {
                    try store.readFollowUpResult(request.id, now: now)
                }
                withExtendedLifetime(worker) {}
            }
            let recovered = try store.followUpStatus(request.id)
            #expect(recovered.state == .interrupted)
            #expect(recovered.finishedAt != nil)
            #expect(try store.replayFollowUp(request) == recovered)
            #expect(throws: AnalysisJobStore.FollowUpError.unavailable) {
                try store.readFollowUpResult(request.id, now: now + 1)
            }
        }
    }

    @Test(arguments: ["queued", "running", "completed"])
    func `disabling assessments invalidates requests and preserves burst`(state: String) throws {
        try withStore { store, _ in
            let request = try seedFollowUpSource(in: store)
            let source = try store.readFollowUpSource(catalogID: request.catalogID, jobID: request.sourceJobID)
            let worker: AnalysisJobStore.FollowUpWorker?
            if state == "queued" {
                _ = try store.enqueueFollowUp(request)
                worker = nil
            } else {
                worker = try startFollowUp(request, in: store)
                if state == "completed", let worker {
                    try store.finishFollowUp(worker, result: Data("{}".utf8))
                }
            }

            try store.setFollowUpsEnabled(false)
            #expect(try !store.followUpsEnabled())
            #expect(try store.queuedFollowUp() == nil)
            #expect(try store.recentFollowUps().isEmpty)
            #expect(try store.read()?.hasShareableResult == true)
            #expect(try CatalogGrantStore(directory: store.directory).authorizedCatalog()?.id == request.catalogID)
            #expect(throws: AnalysisJobStore.FollowUpError.disabled) { try store.enqueueFollowUp(request) }
            #expect(throws: AnalysisJobStore.FollowUpError.disabled) { try store.followUpStatus(request.id) }
            #expect(throws: AnalysisJobStore.FollowUpError.disabled) { try store.readFollowUpResult(request.id) }
            if let worker {
                #expect(throws: AnalysisJobStore.FollowUpError.disabled) {
                    try store.finishFollowUp(worker, result: Data("{}".utf8))
                }
            }

            try store.withLock { try store.stageFollowUpSourceLocked(source) }
            try store.setFollowUpsEnabled(true)
            #expect(try store.followUpsEnabled())
            #expect(throws: FollowUpSourceSnapshot.SourceError.unavailable) { try store.enqueueFollowUp(request) }
            if let worker {
                #expect(throws: AnalysisJobStore.FollowUpError.unavailable) {
                    try store.finishFollowUp(worker, result: Data("{}".utf8))
                }
            }
        }
    }

    @Test func `process exit releases follow up worker lock`() throws {
        try withStore { store, jobFile in
            let request = try seedFollowUpSource(in: store)
            do {
                let worker = try startFollowUp(request, in: store)
                withExtendedLifetime(worker) {}
            }
            let lock = jobFile.deletingLastPathComponent().appendingPathComponent("analysis-worker.lock")
            let process = Process()
            let ready = Pipe()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/perl")
            process.arguments = ["-MFcntl=:flock", "-e", """
            open(my $lock, "+<", $ARGV[0]) or die $!;
            flock($lock, LOCK_EX | LOCK_NB) or die $!;
            $| = 1;
            print "R";
            sleep while 1;
            """, lock.path]
            process.standardOutput = ready
            try process.run()
            defer {
                if process.isRunning {
                    kill(process.processIdentifier, SIGKILL)
                    process.waitUntilExit()
                }
            }
            let received = try ready.fileHandleForReading.read(upToCount: 1)
            try #require(received == Data([82]))
            #expect(try store.acquireWorkerLease() == nil)
            kill(process.processIdentifier, SIGKILL)
            process.waitUntilExit()
            #expect(process.terminationReason == .uncaughtSignal)
            guard case let .replay(recovered) = try store.beginFollowUp(request, now: now) else {
                Issue.record("Recovery must recognize the existing request.")
                return
            }
            #expect(recovered.state == .interrupted)
        }
    }

    @Test func `recurring refresh preserves follow up consent`() throws {
        try withStore { store, _ in
            let request = try seedFollowUpSource(in: store)
            let grants = CatalogGrantStore(directory: store.directory)
            let scanID = UUID()
            let updated = CatalogSummary(
                photoCount: 1, earliestCaptureDate: nil, latestCaptureDate: nil, cameraCounts: [:],
                snapshotAt: "2026-11-16", photos: [], scanId: scanID,
            )
            try store.withLock {
                try grants.refreshRecurringLocked(catalogID: request.catalogID, summary: updated)
            }
            let grant = try #require(try grants.authorizedCatalog())
            #expect(grant.followUpEnabled == true)
            #expect(grant.summary?.scanId == scanID)
        }
    }

    @Test func `queued assessment replays and claims exactly once`() throws {
        try withStore { store, _ in
            let request = try seedFollowUpSource(in: store)
            let queued = try store.enqueueFollowUp(request)
            #expect(queued.state == .queued)
            #expect(try store.replayFollowUp(request) == queued)
            let conflicting = AnalysisJobStore.FollowUpRequest(
                id: request.id, catalogID: request.catalogID, sourceJobID: request.sourceJobID,
                target: request.target, rubric: ["exposure"],
            )
            #expect(throws: AnalysisJobStore.FollowUpError.conflict) {
                try store.replayFollowUp(conflicting)
            }
            let worker = try startFollowUp(request, in: store)
            #expect(try store.queuedFollowUp() == nil)
            #expect(try store.followUpStatus(request.id).state == .running)
            let replacement = AnalysisJob(jobId: UUID(), catalogId: request.catalogID, createdAt: now, updatedAt: now)
            #expect(throws: AnalysisJobStore.StoreError.busy) {
                try store.update { _ in replacement }
            }
            let output = Data("{}".utf8)
            try store.finishFollowUp(worker, result: output)
            #expect(try store.followUpStatus(request.id).state == .completed)
            #expect(try store.readFollowUpResult(request.id) == output)
            try store.clearFollowUpResult(request.id)
            #expect(try store.followUpStatus(request.id).resultCleared == true)
            #expect(throws: AnalysisJobStore.FollowUpError.unavailable) {
                try store.readFollowUpResult(request.id)
            }
        }
    }

    @Test func `cancelling queued assessment leaves replay receipt`() throws {
        try withStore { store, _ in
            let request = try seedFollowUpSource(in: store)
            _ = try store.enqueueFollowUp(request)
            try store.cancelFollowUp(request.id)
            #expect(try store.queuedFollowUp() == nil)
            #expect(try store.followUpStatus(request.id).state == .cancelled)
            #expect(try store.replayFollowUp(request)?.state == .cancelled)
        }
    }

    @Test func `assessment projection preserves unknowns and excludes unrequested fields`() throws {
        let assessment = try QwenPhotoAssessment.decodeResponse("""
        {"schemaVersion":2,"subject":"private subject","compositionScore":3,
         "compositionEvidence":"Useful framing\\nDetail","exposureScore":null,"exposureEvidence":null,
         "subjectVisibilityScore":4,"subjectVisibilityEvidence":"private evidence","eyesOpen":null,
         "problems":[],"strengths":[],"confidence":0.5}
        """)
        let output = MCPPhotoAssessmentResult(
            requestId: UUID(), sourceJobId: UUID(), model: "Qwen fixture", assessedCount: 1, failedCount: 1,
            photos: [
                .init(photoId: "supported", assessedImage: .init(width: 2048, height: 1365),
                      findings: assessment.mcpFindings(for: ["composition", "exposure"])),
                .init(photoId: "unreadable", errorCode: "unreadablePhoto")
            ],
        )
        let json = try String(decoding: JSONEncoder().encode(output), as: UTF8.self)
        #expect(json.contains("Useful framing Detail"))
        #expect(json.contains("\"score\":null"))
        #expect(json.contains("\"evidence\":null"))
        #expect(json.contains("unreadablePhoto"))
        #expect(!json.contains("private"))
        #expect(!json.contains("subjectVisibility"))
        #expect(!json.contains("burstId"))
        #expect(!json.contains("sourceRank"))

        let burst = MCPPhotoAssessmentResult(
            requestId: output.requestId, sourceJobId: output.sourceJobId, model: output.model,
            assessedCount: 0, failedCount: 1, photos: [.init(photoId: "unreadable", errorCode: "unreadablePhoto", sourceRank: 2)],
            burstId: "fixture-burst", burstFrameCount: 7,
        )
        let burstJSON = try String(decoding: JSONEncoder().encode(burst), as: UTF8.self)
        #expect(burstJSON.contains("\"burstId\":\"fixture-burst\""))
        #expect(burstJSON.contains("\"burstFrameCount\":7"))
        #expect(burstJSON.contains("\"sourceRank\":2"))
    }

    private func seedFollowUpSource(in store: AnalysisJobStore) throws -> AnalysisJobStore.FollowUpRequest {
        let catalogID = UUID()
        let jobID = UUID()
        let request = AnalysisJobStore.FollowUpRequest(
            id: UUID(), catalogID: catalogID, sourceJobID: jobID, target: .photos(["photo"]), rubric: ["composition"],
        )
        let grants = CatalogGrantStore(directory: store.directory)
        try grants.authorize(.init(
            id: catalogID, displayName: "Fixture", summary: nil, analysisEnabled: true,
            recurringFolder: true, followUpEnabled: true,
        ))
        var job = AnalysisJob(jobId: jobID, catalogId: catalogID, createdAt: now, updatedAt: now)
        job.claim()
        try store.update { _ in job }
        job.coverage = .init(photoCount: 1, burstCount: 0, singletonCount: 1,
                             unevaluatedCount: 0, skippedByReason: [:], similarityBackends: [:])
        job.bursts = []
        job.finish(.completed)
        let directory = try #require(store.directory)
        let catalog = directory.appendingPathComponent("catalog")
        try FileManager.default.createDirectory(at: catalog, withIntermediateDirectories: false)
        let file = catalog.appendingPathComponent("Cafe\u{301}.ARW")
        try Data([1]).write(to: file)
        let modified = try #require(try file.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate)
        try store.withLock {
            try store.stageFollowUpSourceLocked(.init(jobID: jobID, catalogID: catalogID, photos: [
                "photo": .init(relativePath: file.lastPathComponent, size: 1, modified: modified)
            ], bursts: [:]))
            _ = try store.updateLocked { _ in job }
        }
        return request
    }

    private func startFollowUp(
        _ request: AnalysisJobStore.FollowUpRequest, in store: AnalysisJobStore,
    ) throws -> AnalysisJobStore.FollowUpWorker {
        let admission = try store.beginFollowUp(request, now: now)
        guard case let .started(worker) = admission else {
            throw AnalysisJobStore.FollowUpError.conflict
        }
        return worker
    }

    private func withStore(_ test: (AnalysisJobStore, URL) throws -> Void) throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        try test(AnalysisJobStore(directory: directory), directory.appendingPathComponent("analysis-job.json"))
    }
}
