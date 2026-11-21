import AppKit
import Foundation
import PhotoAIContracts
@testable import RawCull
import RawCullCore
import Testing

/// A scriptable `MCPAnalysisWorkspace`. Every requirement is a plain stored
/// value, so a test sets the state it wants and inspects what the controller did.
@MainActor
final class FakeMCPWorkspace: MCPAnalysisWorkspace {
    var sources: [ARWSourceCatalog] = []
    var selectedSource: ARWSourceCatalog?
    var loadedSource: ARWSourceCatalog?
    var files: [FileItem] = []
    var scanDiscoveredCount = 0
    var catalogLoadFailure: CatalogLoadFailure?
    var catalogPersistenceError: String?
    var isCatalogTransitionActive = false
    var isScanningCatalog = false
    var isMCPWorkspaceLoading = false

    var accessibleURLs: Set<URL> = []
    func hasActiveSecurityScopedAccess(for url: URL) -> Bool {
        accessibleURLs.contains(url.standardizedFileURL)
    }

    func retainSecurityScopedAccess(for url: URL) -> RawCullCatalogGrant? {
        RawCullCatalogGrant(url: url) { _ in }
    }

    private(set) var catalogLoads: [ARWSourceCatalog?] = []
    /// Called by `startCatalogLoad`; the default finishes the load at once.
    var onCatalogLoad: (@MainActor (FakeMCPWorkspace, ARWSourceCatalog?, URL?) -> Void)? = { workspace, source, url in
        workspace.loadedSource = source
        if let url {
            workspace.accessibleURLs.insert(url.standardizedFileURL)
        }
    }

    func startCatalogLoad(for source: ARWSourceCatalog?, scopedURL: URL?, retainedAccess _: RawCullCatalogGrant?) {
        catalogLoads.append(source)
        onCatalogLoad?(self, source, scopedURL)
    }

    private(set) var cancelledCatalogLoads = 0
    func cancelCatalogLoad() {
        cancelledCatalogLoads += 1
    }

    var isMCPTerminationPending = false
    var isDeepAIReviewBlockedByOtherWork = false
    var isPreparingBurstCatalog = false
    var isSharpnessCalibrationRunning = false

    func mcpCatalogSummary(scanId _: UUID?) -> CatalogSummary? {
        nil
    }

    private(set) var authorizedCatalogIDs: [UUID] = []
    func authorizeCatalogForMCPJob(catalogId: UUID) throws {
        authorizedCatalogIDs.append(catalogId)
    }

    var isSemanticSearchActive = false
    func clearActiveSemanticSearchForMCP() async {
        isSemanticSearchActive = false
    }

    var fullCatalogBurstAnalysisFiles: [FileItem] {
        files
    }

    var burstAnalysisGeneration = 0
    var burstAnalysisProgress = BurstAnalysisProgress()
    var currentBurstSimilaritySignature: BurstSimilaritySignature
    var currentSharpnessScoringSignature: SharpnessScoringSignature

    private(set) var burstAnalysisRuns = 0
    /// The analysis result; the default is an empty result. Runs after the
    /// generation is advanced, like the live workspace.
    var analyze: @MainActor (FakeMCPWorkspace) async -> BurstAnalysisPipelineResult? = { _ in
        BurstAnalysisPipelineResult(groups: [], rankings: [], restoredReviewStates: [:], cacheOutcome: .miss, diagnostics: [])
    }

    func startBurstAnalysis(catalog _: URL, files _: [FileItem]) async -> BurstAnalysisPipelineResult? {
        burstAnalysisRuns += 1
        burstAnalysisGeneration += 1
        return await analyze(self)
    }

    var currentSharpnessScores: [UUID: Float] = [:]
    var currentSimilarityEmbeddings: [UUID: SimilarityArtifact] = [:]
    var sharpnessScoringProgress = 0
    var similarityIndexingProgress = 0

    private(set) var presentedBurstResults = 0
    func presentBurstResultsAfterMCPJob() {
        presentedBurstResults += 1
    }

    init() {
        let live = makeRawCullViewModel()
        currentBurstSimilaritySignature = live.currentBurstSimilaritySignature
        currentSharpnessScoringSignature = live.currentSharpnessScoringSignature
    }
}

/// A temporary MCP store directory with an environment that never touches the
/// shared app group, `UserDefaults.standard` or real windows.
@MainActor
final class MCPControllerFixture {
    let directory: URL
    let defaults: UserDefaults
    private let defaultsSuite: String
    var now = Date()
    var instant = ContinuousClock.now
    let window = NSWindow(contentRect: .init(x: 0, y: 0, width: 200, height: 200), styleMask: [], backing: .buffered, defer: true)
    /// Setup sheets presented so far, in order.
    private(set) var presentedSheets: [NSWindow] = []
    /// Setup sheets whose presentation has returned (answered or dismissed).
    private(set) var finishedSheets = 0
    /// Answers each setup sheet. The default waits until the setup task is cancelled.
    var answerSheet: @MainActor (NSWindow) async -> NSApplication.ModalResponse = { _ in
        while !Task.isCancelled {
            try? await Task.sleep(for: .milliseconds(10))
        }
        return .cancel
    }

    init() throws {
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("MCPControllerTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defaultsSuite = "MCPControllerTests-\(UUID().uuidString)"
        defaults = try #require(UserDefaults(suiteName: defaultsSuite))
    }

    deinit {
        try? FileManager.default.removeItem(at: directory)
        UserDefaults().removePersistentDomain(forName: defaultsSuite)
    }

    var jobs: AnalysisJobStore {
        AnalysisJobStore(directory: directory)
    }

    var grants: CatalogGrantStore {
        CatalogGrantStore(directory: directory)
    }

    var setupStore: CatalogSetupStore {
        CatalogSetupStore(jobs: jobs)
    }

    func makeController() -> MCPAnalysisController {
        MCPAnalysisController(environment: MCPAnalysisEnvironment(
            grants: grants,
            jobs: jobs,
            defaults: defaults,
            now: { [unowned self] in now },
            instant: { [unowned self] in instant },
            hostBundlePath: { "/Applications/RawCull.app" },
            hostWindow: { [unowned self] in window },
            activateApp: {},
            presentSetupSheet: { [unowned self] sheet, _ in
                presentedSheets.append(sheet)
                let response = await answerSheet(sheet)
                finishedSheets += 1
                return response
            },
        ))
    }

    /// A readable catalog folder with one photo, inside the fixture directory.
    func makeCatalog(name: String = "Fixture") throws -> (source: ARWSourceCatalog, files: [FileItem]) {
        let folder = directory.appendingPathComponent(name, isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let photo = folder.appendingPathComponent("photo.ARW")
        try Data([0]).write(to: photo)
        let file = FileItem(
            id: UUID(), url: photo, name: "photo.ARW", size: 1,
            dateModified: .distantPast, exifData: nil, afFocusNormalized: nil,
        )
        return (ARWSourceCatalog(name: name, url: folder), [file])
    }

    func submitSetup(hint: String = "Fixture", createdAt: Date = .now) throws -> CatalogSetupRequest {
        let request = CatalogSetupRequest(
            requestId: UUID(), catalogHint: hint, jobType: "burstAnalysis", createdAt: createdAt, usesExactHint: true,
        )
        #expect(try setupStore.submit(request).wasAccepted)
        return request
    }

    /// Publishes a completed one-time-approval job with a follow-up source and
    /// queues an assessment of its only burst.
    func queueFollowUp() throws -> AnalysisJobStore.FollowUpRequest {
        let catalogID = UUID()
        let jobID = UUID()
        let now = Date()
        var job = AnalysisJob(jobId: jobID, catalogId: catalogID, createdAt: now, updatedAt: now)
        job.setupRequestId = UUID()
        job.claim()
        try jobs.update { _ in job }
        let snapshot = FollowUpSourceSnapshot(jobID: jobID, catalogID: catalogID, photos: [
            "photo-0": .init(relativePath: "photo.ARW", size: 1, modified: now)
        ], bursts: [
            "burst": .init(photoIDs: ["photo-0"], ranks: ["photo-0": 1], recommendedPhotoID: "photo-0", alternatePhotoID: nil)
        ])
        try jobs.withLock { try jobs.stageFollowUpSourceLocked(snapshot) }
        job.coverage = .init(photoCount: 1, burstCount: 1, singletonCount: 0,
                             unevaluatedCount: 0, skippedByReason: [:], similarityBackends: [:])
        job.bursts = []
        job.finish(.completed)
        job.allowsJobPhotoAccess = true
        try jobs.update { _ in job }
        let request = AnalysisJobStore.FollowUpRequest(
            id: UUID(), catalogID: catalogID, sourceJobID: jobID, target: .burst("burst"), rubric: ["exposure"],
        )
        #expect(try jobs.enqueueFollowUp(request).state == .queued)
        return request
    }

    /// Lets tasks the controller started run until `condition` holds.
    func settle(
        timeout: Duration = .seconds(5),
        until condition: @MainActor () throws -> Bool,
    ) async throws -> Bool {
        let deadline = ContinuousClock.now + timeout
        while ContinuousClock.now < deadline {
            if try condition() {
                return true
            }
            try await Task.sleep(for: .milliseconds(10))
        }
        return try condition()
    }
}

/// A scriptable Qwen surface for MCP photo assessment.
nonisolated struct FakeMCPPhotoAssessor: MCPPhotoAssessing {
    let identity: QwenInferenceRuntime.Identity?

    init(identity: QwenInferenceRuntime.Identity? = nil) {
        self.identity = identity
    }

    func assessmentIdentity() async -> QwenInferenceRuntime.Identity? {
        identity
    }

    func assessForMCP(
        rubric _: [String], image _: CGImage, identity _: QwenInferenceRuntime.Identity,
    ) async throws -> QwenPhotoAssessment {
        throw QwenModelError.invalidStructuredResponse
    }
}
