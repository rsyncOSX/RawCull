import Foundation
import MCP
@testable import RawCullMCP
import Testing

@Suite("MCP tool handlers")
struct ToolHandlerTests {
    @Test func photoPagesUseSnapshotCursorAndCleanMetadata() async throws {
        let store = try makeStore()
        defer { removeStore(store) }
        let catalogId = try authorizePhotos(in: store)
        let first = try await photos(in: store, catalogId: catalogId, options: ["limit": .int(1)])
        let page = try #require(first["photos"]?.arrayValue)
        #expect(page.count == 1)
        #expect(page.first?.objectValue?["name"] == .string("First Frame.raw"))
        #expect(page.first?.objectValue?["camera"] == .string("Camera Model"))
        let cursor = try #require(first["nextCursor"]?.stringValue)
        let second = try await photos(in: store, catalogId: catalogId, options: ["cursor": .string(cursor)])
        #expect(second["photos"]?.arrayValue?.first?.objectValue?["name"] == .string("Second.raw"))
        #expect(second["nextCursor"] == .null)

        _ = try authorizePhotos(in: store, catalogId: catalogId)
        await #expect(throws: MCPError.self) {
            try await photos(in: store, catalogId: catalogId, options: ["cursor": .string(cursor)])
        }
    }

    @Test(arguments: [Value.int(0), .int(101), .double(1.5), .string("1"), .null])
    func rejectsInvalidPhotoLimit(_ limit: Value) async throws {
        let store = try makeStore()
        defer { removeStore(store) }
        let catalogId = try authorizePhotos(in: store)
        await #expect(throws: MCPError.self) {
            try await photos(in: store, catalogId: catalogId, options: ["limit": limit])
        }
    }

    @Test(arguments: ["", "0", "-1", "2", "999999999999999999999999999999"])
    func rejectsInvalidPhotoOffset(_ offset: String) async throws {
        let store = try makeStore()
        defer { removeStore(store) }
        let catalogId = try authorizePhotos(in: store)
        let catalog = try #require(try store.authorizedCatalog())
        let summary = try #require(catalog.summary)
        let cursor = summary.photoIdPrefix(catalogId: catalogId) + offset
        await #expect(throws: MCPError.self) {
            try await photos(in: store, catalogId: catalogId, options: ["cursor": .string(cursor)])
        }
    }

    @Test func pendingSetupRetryReopensAppAndResolvedRetryDoesNot() async throws {
        let store = try makeStore()
        defer { removeStore(store) }
        let app = URL(fileURLWithPath: "/Applications/RawCull.app")
        let id = UUID()
        let hint = "/photos/Exact\u{2028}Name"
        let params = setupParameters(id: id, hint: hint)
        var opened: [URL] = []
        let first = try await AnalysisTools.callSetup(params, grantStore: store, application: app) { url in
            opened.append(url)
            return false
        }
        #expect(first.structuredContent?.objectValue?["message"]?.stringValue?.contains("Open RawCull") == true)
        #expect(first.structuredContent?.objectValue?["catalogHint"] == .string("/photos/Exact Name"))

        let replay = try await AnalysisTools.callSetup(params, grantStore: store, application: app) { url in
            opened.append(url)
            return true
        }
        #expect(replay.structuredContent?.objectValue?["state"] == .string("pendingApproval"))
        #expect(opened == [app, app])

        let setup = CatalogSetupStore(jobs: AnalysisJobStore(directory: store.directory))
        var request = try #require(try setup.request(id))
        #expect(request.catalogHint == hint)
        request.state = .denied
        let denied = request
        try setup.jobs.withLock { try setup.saveLocked(denied) }
        let resolved = try await AnalysisTools.callSetup(params, grantStore: store, application: app) { url in
            opened.append(url)
            return true
        }
        #expect(resolved.structuredContent?.objectValue?["state"] == .string("denied"))
        #expect(opened == [app, app])
    }

    @Test func oversizedSetupHintFailsWithoutLaunchingOrSaving() async throws {
        let store = try makeStore()
        defer { removeStore(store) }
        let id = UUID()
        let limit = CatalogSetupRequest.maximumHintScalars
        let params = setupParameters(id: id, hint: "/" + String(repeating: "é", count: limit))
        let app = URL(fileURLWithPath: "/Applications/RawCull.app")
        await #expect(throws: MCPError.self) {
            try await AnalysisTools.callSetup(params, grantStore: store, application: app) { _ in
                Issue.record("An oversized hint must fail before launching RawCull.")
                return true
            }
        }
        let setup = CatalogSetupStore(jobs: AnalysisJobStore(directory: store.directory))
        #expect(try setup.request(id) == nil)
    }

    @Test func analysisStatusRequiresTheCurrentJobAndGrant() async throws {
        let store = try makeStore()
        defer { removeStore(store) }
        let catalogId = try authorizePhotos(in: store)
        let jobId = UUID()
        let now = Date.now
        let job = AnalysisJob(jobId: jobId, catalogId: catalogId, createdAt: now, updatedAt: now)
        let jobs = AnalysisJobStore(directory: store.directory)
        try jobs.update { _ in job }
        let params = CallTool.Parameters(name: "get_analysis_status", arguments: [
            "catalogId": .string(catalogId.uuidString), "jobId": .string(jobId.uuidString),
        ])
        let result = try await callKnownTool(params, grantStore: store)
        #expect(result.structuredContent?.objectValue?["jobId"] == .string(jobId.uuidString))

        try store.revoke()
        await #expect(throws: MCPError.self) {
            try await callKnownTool(params, grantStore: store)
        }
    }

    @Test func clearingRecurringResultPreservesCatalogUntilRevoked() async throws {
        let store = try makeStore()
        defer { removeStore(store) }
        let catalogId = try authorizePhotos(in: store, recurringFolder: true)
        let jobs = AnalysisJobStore(directory: store.directory)
        let jobId = UUID()
        let now = Date.now
        var job = AnalysisJob(jobId: jobId, catalogId: catalogId, createdAt: now, updatedAt: now)
        job.coverage = .init(photoCount: 2, burstCount: 0, singletonCount: 2, unevaluatedCount: 0,
                             skippedByReason: [:], similarityBackends: [:])
        job.bursts = []
        job.finish(.completed)
        try jobs.update { _ in job }

        let catalogs = CallTool.Parameters(name: "list_catalogs")
        let catalogArguments = ["catalogId": Value.string(catalogId.uuidString)]
        let summary = CallTool.Parameters(name: "catalog_summary", arguments: catalogArguments)
        var jobArguments = catalogArguments
        jobArguments["jobId"] = .string(jobId.uuidString)
        let status = CallTool.Parameters(name: "get_analysis_status", arguments: jobArguments)
        let bursts = CallTool.Parameters(name: "list_bursts", arguments: jobArguments)

        let before = try await callKnownTool(summary, grantStore: store)
        #expect(before.structuredContent?.objectValue?["analysisCoverage"] != nil)
        _ = try await callKnownTool(bursts, grantStore: store)

        try #require(try jobs.clearResult(expectedJobID: jobId))
        let listed = try await callKnownTool(catalogs, grantStore: store)
        let grant = try #require(listed.structuredContent?.objectValue?["catalogs"]?.arrayValue?.first?.objectValue)
        #expect(grant["id"] == .string(catalogId.uuidString))
        #expect(grant["analysisEnabled"] == .bool(true))
        #expect(grant["recurringFolder"] == .bool(true))
        let cleared = try await callKnownTool(summary, grantStore: store)
        #expect(cleared.structuredContent?.objectValue?["photoCount"] == .int(2))
        #expect(cleared.structuredContent?.objectValue?["analysisCoverage"] == nil)
        for params in [status, bursts] {
            await #expect(throws: MCPError.self) { try await callKnownTool(params, grantStore: store) }
        }

        try store.revoke()
        let revoked = try await callKnownTool(catalogs, grantStore: store)
        #expect(revoked.structuredContent?.objectValue?["catalogs"] == .array([]))
        for params in [summary, status, bursts] {
            await #expect(throws: MCPError.self) { try await callKnownTool(params, grantStore: store) }
        }
    }

    @Test func assessmentRejectsUnsupportedRubricMissingSourceAndRevokedAccess() async throws {
        let store = try makeStore()
        defer { removeStore(store) }
        let catalogID = try authorizePhotos(in: store)
        var args: [String: Value] = [
            "requestId": .string(UUID().uuidString), "catalogId": .string(catalogID.uuidString),
            "sourceJobId": .string(UUID().uuidString), "photoIds": .array([.string("photo")]),
            "rubric": .array([.string("expression")])
        ]
        let invalid = try await callKnownTool(.init(name: "start_photo_assessment", arguments: args), grantStore: store)
        #expect(invalid.isError == true)
        #expect(invalid.structuredContent?.objectValue?["errorCode"] == .string("invalidRequest"))

        args["rubric"] = .array([.string("composition")])
        let assessment = CallTool.Parameters(name: "start_photo_assessment", arguments: args)
        let stale = try await callKnownTool(assessment, grantStore: store)
        #expect(stale.isError == true)
        #expect(stale.structuredContent?.objectValue?["errorCode"] == .string("staleSource"))

        try store.revoke()
        let denied = try await callKnownTool(assessment, grantStore: store)
        #expect(denied.isError == true)
        #expect(denied.structuredContent?.objectValue?["errorCode"] == .string("permissionRequired"))
        #expect(try AnalysisJobStore(directory: store.directory).queuedFollowUp() == nil)
    }

    @Test func burstAssessmentValidatesSelectorsAndReplaysQueuedRequest() async throws {
        let grants = try makeStore()
        defer { removeStore(grants) }
        let catalogID = try authorizePhotos(in: grants)
        let jobs = AnalysisJobStore(directory: grants.directory)
        let jobID = UUID()
        let burstID = "\(catalogID):\(jobID):0"
        var job = AnalysisJob(jobId: jobID, catalogId: catalogID, createdAt: .now, updatedAt: .now)
        job.claim()
        try jobs.update { _ in job }
        job.coverage = .init(photoCount: 1, burstCount: 1, singletonCount: 0,
                             unevaluatedCount: 0, skippedByReason: [:], similarityBackends: [:])
        job.bursts = []
        job.finish(.completed)
        try jobs.withLock {
            try jobs.stageFollowUpSourceLocked(.init(jobID: jobID, catalogID: catalogID, photos: [
                "photo": .init(relativePath: "fixture.ARW", size: 1, modified: .now)
            ], bursts: [
                burstID: .init(photoIDs: ["photo"], ranks: ["photo": 1],
                               recommendedPhotoID: "photo", alternatePhotoID: nil)
            ]))
            _ = try jobs.updateLocked { _ in job }
        }
        let requestID = UUID()
        let common: [String: Value] = [
            "requestId": .string(requestID.uuidString), "catalogId": .string(catalogID.uuidString),
            "sourceJobId": .string(jobID.uuidString), "rubric": .array([.string("exposure")])
        ]
        func submit(_ selectors: [String: Value]) async throws -> [String: Value] {
            let args = common.merging(selectors) { _, selected in selected }
            let reply = try await callKnownTool(.init(name: "start_photo_assessment", arguments: args), grantStore: grants)
            return try #require(reply.structuredContent?.objectValue)
        }
        let photos = ["photoIds": Value.array([.string("photo")])]
        let burst = ["burstId": Value.string(burstID)]
        #expect(try await submit([:])["errorCode"] == .string("invalidRequest"))
        #expect(try await submit(photos.merging(burst) { first, _ in first })["errorCode"] == .string("invalidRequest"))
        #expect(try await submit(["burstId": .int(1)])["errorCode"] == .string("invalidRequest"))
        #expect(try await submit(["burstId": .string("")])["errorCode"] == .string("invalidRequest"))
        #expect(try await submit(["burstId": .string("\(catalogID):\(UUID()):0")])["errorCode"] == .string("invalidTarget"))
        #expect(try jobs.queuedFollowUp() == nil)

        let request = AnalysisJobStore.FollowUpRequest(id: requestID, catalogID: catalogID, sourceJobID: jobID,
                                                       target: .burst(burstID), rubric: ["exposure"])
        _ = try jobs.enqueueFollowUp(request)
        let replay = try await submit(burst)
        #expect(replay["state"] == .string("queued"))
        #expect(replay["requestId"] == .string(requestID.uuidString))
        #expect(try await submit(photos)["errorCode"] == .string("conflictingReplay"))

        try jobs.setFollowUpsEnabled(false)
        #expect(try await submit(burst)["errorCode"] == .string("assessmentDisabled"))
        let status = try await callKnownTool(.init(name: "rawcull_status"), grantStore: grants)
        #expect(status.structuredContent?.objectValue?["photoAssessmentsEnabled"] == .bool(false))
        let rankings = try await callKnownTool(.init(name: "list_bursts", arguments: [
            "catalogId": .string(catalogID.uuidString), "jobId": .string(jobID.uuidString)
        ]), grantStore: grants)
        #expect(rankings.isError != true)
    }

    private func setupParameters(id: UUID, hint: String) -> CallTool.Parameters {
        .init(name: "request_catalog_setup", arguments: [
            "requestId": .string(id.uuidString), "catalogHint": .string(hint), "jobType": .string("burstAnalysis"),
        ])
    }

    private func photos(
        in store: CatalogGrantStore, catalogId: UUID, options: [String: Value]
    ) async throws -> [String: Value] {
        var arguments = options
        arguments["catalogId"] = .string(catalogId.uuidString)
        let params = CallTool.Parameters(name: "list_photos", arguments: arguments)
        let result = try await callKnownTool(params, grantStore: store)
        return try #require(result.structuredContent?.objectValue)
    }

    private func authorizePhotos(
        in store: CatalogGrantStore, catalogId: UUID = UUID(), recurringFolder: Bool? = nil
    ) throws -> UUID {
        let photos = [
            CatalogPhoto(name: "First\u{2028}Frame.raw", captureDate: nil, camera: "Camera\u{2029}Model"),
            CatalogPhoto(name: "Second.raw", captureDate: nil, camera: nil),
        ]
        let summary = CatalogSummary(
            photoCount: photos.count, earliestCaptureDate: nil, latestCaptureDate: nil,
            cameraCounts: [:], snapshotAt: "2026-11-14", photos: photos, scanId: UUID()
        )
        try store.authorize(.init(id: catalogId, displayName: "Photos", summary: summary,
                                  analysisEnabled: true, recurringFolder: recurringFolder))
        return catalogId
    }

    private func makeStore() throws -> CatalogGrantStore {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return CatalogGrantStore(directory: directory)
    }

    private func removeStore(_ store: CatalogGrantStore) {
        if let directory = store.directory { try? FileManager.default.removeItem(at: directory) }
    }
}
