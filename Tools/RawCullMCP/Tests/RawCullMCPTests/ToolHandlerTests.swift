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

    private func authorizePhotos(in store: CatalogGrantStore, catalogId: UUID = UUID()) throws -> UUID {
        let photos = [
            CatalogPhoto(name: "First\u{2028}Frame.raw", captureDate: nil, camera: "Camera\u{2029}Model"),
            CatalogPhoto(name: "Second.raw", captureDate: nil, camera: nil),
        ]
        let summary = CatalogSummary(
            photoCount: photos.count, earliestCaptureDate: nil, latestCaptureDate: nil,
            cameraCounts: [:], snapshotAt: "2026-11-14", photos: photos, scanId: UUID()
        )
        try store.authorize(.init(id: catalogId, displayName: "Photos", summary: summary, analysisEnabled: true))
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
