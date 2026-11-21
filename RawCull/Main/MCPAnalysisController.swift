import AppKit
import CryptoKit
import Foundation
import OSLog
import RawCullCore

/// The shared grant contains only metadata. The bookmark and source fingerprint
/// are stored in RawCull's own preferences.
struct MCPAnalysisAuthorization: Codable {
    private static let preferenceKey = "MCPAnalysisAuthorization"

    let catalogId: UUID
    let bookmark: Data
    let fingerprint: Data

    static var savedData: Data? {
        savedData(in: .standard)
    }

    static func savedData(in defaults: UserDefaults) -> Data? {
        defaults.data(forKey: preferenceKey)
    }

    static func save(_ data: Data?, in defaults: UserDefaults = .standard) {
        defaults.set(data, forKey: preferenceKey)
    }

    static func fingerprint(for files: [FileItem]) throws -> Data {
        let entries = files.map {
            SnapshotFile(name: $0.url.lastPathComponent, size: $0.size, modified: $0.dateModified)
        }.sorted { $0.name < $1.name }
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        return try Data(SHA256.hash(data: encoder.encode(entries)))
    }

    private struct SnapshotFile: Encodable {
        let name: String
        let size: Int64
        let modified: Date
    }
}

/// A one-time approval keeps its bookmark private and tied to the current shared result.
struct MCPJobPhotoAccess: Codable {
    private static let preferenceKey = "MCPJobPhotoAccess"

    let jobID: UUID
    let bookmark: Data

    static var saved: Self? {
        saved(in: .standard)
    }

    static func saved(in defaults: UserDefaults) -> Self? {
        guard let data = defaults.data(forKey: preferenceKey) else { return nil }
        return try? JSONDecoder().decode(Self.self, from: data)
    }

    static func save(_ data: Data?, in defaults: UserDefaults = .standard) {
        defaults.set(data, forKey: preferenceKey)
    }
}

/// The Qwen surface MCP photo assessments use; `QwenInferenceRuntime` in the app.
nonisolated protocol MCPPhotoAssessing: Sendable {
    func assessmentIdentity() async -> QwenInferenceRuntime.Identity?
    func assessForMCP(
        rubric: [String], image: CGImage, identity: QwenInferenceRuntime.Identity,
    ) async throws -> QwenPhotoAssessment
}

extension QwenInferenceRuntime: MCPPhotoAssessing {}

/// Everything `MCPAnalysisController` reads from outside the workspace. The
/// defaults are the live app values; tests substitute temporary stores, clocks
/// and sheet presentation so they never touch the shared app group, the user's
/// preferences or real windows.
struct MCPAnalysisEnvironment {
    var grants: CatalogGrantStore
    /// `nil` uses `AnalysisJobStore(directory: grants.directory)`.
    var jobs: AnalysisJobStore?
    var defaults: UserDefaults
    var now: @MainActor () -> Date
    var instant: @MainActor () -> ContinuousClock.Instant
    var hostBundlePath: @MainActor () -> String
    var hostWindow: @MainActor () -> NSWindow?
    var activateApp: @MainActor () -> Void
    /// Presents a setup sheet and returns its response. `nil` uses AppKit.
    var presentSetupSheet: (@MainActor (_ sheet: NSWindow, _ parent: NSWindow) async -> NSApplication.ModalResponse)?

    static var live: Self {
        Self(
            grants: .shared(),
            jobs: nil,
            defaults: .standard,
            now: { .now },
            instant: { .now },
            hostBundlePath: { Bundle.main.bundleURL.resolvingSymlinksInPath().standardizedFileURL.path },
            hostWindow: { NSApp.keyWindow ?? NSApp.mainWindow ?? NSApp.windows.first(where: \.isVisible) },
            activateApp: { NSApp.activate() },
            presentSetupSheet: nil,
        )
    }
}

@MainActor
final class MCPAnalysisController {
    let environment: MCPAnalysisEnvironment
    let grants: CatalogGrantStore
    let jobs: AnalysisJobStore
    var monitor: Task<Void, Never>?

    // MARK: State

    /// Identifies one activity, so a finished task can only end its own activity.
    struct ActivityToken: Equatable {
        let value: UInt64
    }

    struct SetupActivity {
        let token: ActivityToken
        var task: Task<Void, Never>?
        let deadline: Date
        var sheet: (parent: NSWindow, window: NSWindow)?
    }

    struct AnalysisActivity {
        let token: ActivityToken
        var task: Task<Void, Never>?
        let job: AnalysisJob
    }

    struct FollowUpActivity {
        let token: ActivityToken
        var task: Task<Void, Never>?
        let id: UUID
        let deadline: ContinuousClock.Instant
        /// Set when the controller stops the assessment for a known reason.
        var stopReason: MCPAssessmentStopReason?
    }

    /// Catalog setup, catalog analysis and photo-assessment follow-ups never
    /// run at the same time.
    enum Activity {
        case idle
        case settingUp(SetupActivity)
        case analyzing(AnalysisActivity)
        case assessing(FollowUpActivity)

        var token: ActivityToken? {
            switch self {
            case .idle: nil
            case let .settingUp(activity): activity.token
            case let .analyzing(activity): activity.token
            case let .assessing(activity): activity.token
            }
        }

        var task: Task<Void, Never>? {
            switch self {
            case .idle: nil
            case let .settingUp(activity): activity.task
            case let .analyzing(activity): activity.task
            case let .assessing(activity): activity.task
            }
        }
    }

    enum Lifecycle {
        case running
        /// The app asked to quit and is waiting on a save prompt; no new work starts.
        case terminationPending
        /// `stopForQuit()` ran; nothing is published after this.
        case quitting
    }

    var activity: Activity = .idle
    var lifecycle: Lifecycle = .running
    var nextActivityToken: UInt64 = 0

    struct SetupApproval {
        let id: UUID
        let url: URL
        let access: RawCullCatalogGrant
        let remember: Bool
        let expectedGrantID: UUID?
    }

    /// Created by an approved setup and consumed when the job it queued is
    /// claimed. It deliberately outlives the setup activity, so it is not part
    /// of `activity`.
    var pendingApprovalForClaim: SetupApproval?

    /// Timers and caches of the polling loop.
    struct PollBookkeeping {
        var inactiveRevision: AnalysisJobStore.Revision?
        var cachedGrant: (revision: AnalysisJobStore.Revision, catalogId: UUID?, analysisEnabled: Bool)?
        var nextHostPublication = Date.distantPast
        var nextSetupMaintenance = Date.distantPast
        var storageFailureSince: ContinuousClock.Instant?
    }

    var bookkeeping = PollBookkeeping()

    var isQuitting: Bool {
        lifecycle == .quitting
    }

    /// Termination is pending or the app is quitting: no new work starts.
    var isTerminationPending: Bool {
        lifecycle != .running
    }

    var isIdle: Bool {
        if case .idle = activity {
            true
        } else {
            false
        }
    }

    var isSettingUp: Bool {
        if case .settingUp = activity {
            true
        } else {
            false
        }
    }

    var isAnalyzing: Bool {
        if case .analyzing = activity {
            true
        } else {
            false
        }
    }

    var isAssessing: Bool {
        if case .assessing = activity {
            true
        } else {
            false
        }
    }

    /// The job the running analysis works on.
    var activeJob: AnalysisJob? {
        if case let .analyzing(analysis) = activity {
            analysis.job
        } else {
            nil
        }
    }

    /// Starts `next` (built with a fresh token) and returns that token.
    func begin(_ next: (ActivityToken) -> Activity) -> ActivityToken {
        precondition(isIdle, "MCP activities never overlap")
        nextActivityToken &+= 1
        let token = ActivityToken(value: nextActivityToken)
        activity = next(token)
        return token
    }

    /// Attaches the task that runs the activity identified by `token`.
    func attach(_ task: Task<Void, Never>, to token: ActivityToken) {
        switch activity {
        case var .settingUp(setup) where setup.token == token:
            setup.task = task
            activity = .settingUp(setup)

        case var .analyzing(analysis) where analysis.token == token:
            analysis.task = task
            activity = .analyzing(analysis)

        case var .assessing(followUp) where followUp.token == token:
            followUp.task = task
            activity = .assessing(followUp)

        default:
            break
        }
    }

    /// Ends the activity only if `token` still identifies it, so a stale
    /// task's cleanup can never clear a newer activity.
    func end(_ token: ActivityToken) {
        guard activity.token == token else { return }
        activity = .idle
    }

    func cancelAnalysis() {
        if case let .analyzing(analysis) = activity {
            analysis.task?.cancel()
        }
    }

    func cancelFollowUp(reason: MCPAssessmentStopReason? = nil) {
        guard case var .assessing(followUp) = activity else { return }
        if let reason {
            followUp.stopReason = reason
            activity = .assessing(followUp)
        }
        followUp.task?.cancel()
    }

    func followUpStopReason(_ token: ActivityToken) -> MCPAssessmentStopReason? {
        if case let .assessing(followUp) = activity, followUp.token == token {
            followUp.stopReason
        } else {
            nil
        }
    }

    /// What `start` was given; `tick()` reads it on every iteration.
    struct MonitorContext {
        weak var viewModel: (any MCPAnalysisWorkspace)?
        let qwen: (any MCPPhotoAssessing)?
        let prepare: @MainActor () async -> Void
        let preparePhotoAssessment: @MainActor () async -> Void
        let canStart: @MainActor () -> Bool
    }

    var context: MonitorContext?

    init(environment: MCPAnalysisEnvironment = .live) {
        self.environment = environment
        grants = environment.grants
        jobs = environment.jobs ?? AnalysisJobStore(directory: environment.grants.directory)
    }

    func start(
        viewModel: any MCPAnalysisWorkspace,
        qwen: (any MCPPhotoAssessing)? = nil,
        prepare: @escaping @MainActor () async -> Void,
        preparePhotoAssessment: @escaping @MainActor () async -> Void = {},
        canStart: @escaping @MainActor () -> Bool,
    ) {
        guard monitor == nil, grants.directory != nil else { return }
        attach(viewModel: viewModel, qwen: qwen, prepare: prepare,
               preparePhotoAssessment: preparePhotoAssessment, canStart: canStart)
        monitor = Task { [weak self] in
            while !Task.isCancelled, let self, self.context?.viewModel != nil {
                await tick()
                try? await Task.sleep(for: .seconds(1))
            }
        }
    }

    /// Binds the workspace without starting the polling loop. Tests call this
    /// and then drive the controller with `tick()`.
    func attach(
        viewModel: any MCPAnalysisWorkspace,
        qwen: (any MCPPhotoAssessing)? = nil,
        prepare: @escaping @MainActor () async -> Void,
        preparePhotoAssessment: @escaping @MainActor () async -> Void = {},
        canStart: @escaping @MainActor () -> Bool,
    ) {
        context = MonitorContext(viewModel: viewModel, qwen: qwen, prepare: prepare,
                                 preparePhotoAssessment: preparePhotoAssessment, canStart: canStart)
    }

    /// One iteration of the polling loop.
    func tick() async {
        guard let context, let viewModel = context.viewModel else { return }
        let prepare = context.prepare
        let canStart = context.canStart
        if case let .settingUp(setup) = activity, environment.now() >= setup.deadline {
            cancelSetup()
        }
        do {
            if let qwen = context.qwen {
                try pollFollowUp(qwen: qwen, viewModel: viewModel, prepare: context.preparePhotoAssessment,
                                 canStart: canStart)
            }
            if !isAssessing {
                try poll(viewModel, prepare: prepare, canStart: canStart)
            }
            bookkeeping.storageFailureSince = nil
            if !isSettingUp, !isAnalyzing, environment.now() >= bookkeeping.nextSetupMaintenance {
                bookkeeping.nextSetupMaintenance = environment.now().addingTimeInterval(60)
                try setupStore.maintain()
            }
            if !isTerminationPending, isIdle, let request = try setupStore.pending() {
                let token = begin { .settingUp(SetupActivity(token: $0, deadline: request.expiresAt)) }
                attach(Task { [weak self, weak viewModel] in
                    guard let self else { return }
                    defer { end(token) }
                    guard let viewModel else { return }
                    await respond(to: request, viewModel: viewModel, canStart: canStart)
                }, to: token)
            }
        } catch AnalysisJobStore.StoreError.unsupportedFormat {
            Logger.process.error("MCP analysis job uses an unsupported format. Use the helper bundled with this RawCull installation.")
            cancelAnalysis()
        } catch where AnalysisJobStore.StoreError.isRetryable(error) {
            let now = environment.instant()
            let since = bookkeeping.storageFailureSince ?? now
            bookkeeping.storageFailureSince = since
            if let job = activeJob, now - since >= .seconds(5) {
                await finish(job, as: .failed, message: storageFailureMessage(error))
                if activeJob?.jobId == job.jobId {
                    cancelAnalysis()
                }
            }
        } catch {
            Logger.process.error("Could not update the MCP analysis job.")
            if let job = activeJob {
                await finish(job, as: .failed, message: storageFailureMessage(error))
            }
            cancelAnalysis()
        }
    }

    func setTerminationPending(_ pending: Bool) {
        if lifecycle != .quitting {
            lifecycle = pending ? .terminationPending : .running
        }
        // Suspend setup before the asynchronous quit save. If quitting is
        // cancelled, the monitor can present the same stored request again.
        if pending {
            cancelSetup()
        }
    }

    func stopForQuit() async {
        lifecycle = .quitting
        monitor?.cancel()
        monitor = nil
        cancelAnalysis()
        if case let .assessing(followUp) = activity {
            followUp.task?.cancel()
            await followUp.task?.value
        }
        cancelSetup()
        if let job = activeJob {
            await finish(job, as: .cancelled, message: "RawCull quit.")
        }
    }

    var setupStore: CatalogSetupStore {
        CatalogSetupStore(jobs: jobs)
    }

    func savedCatalog() throws -> (grant: CatalogGrant, url: URL)? {
        guard let grant = try grants.authorizedCatalog(), grant.analysisEnabled == true,
              grant.summary?.photos != nil, let data = MCPAnalysisAuthorization.savedData(in: environment.defaults),
              let authorization = try? JSONDecoder().decode(MCPAnalysisAuthorization.self, from: data),
              authorization.catalogId == grant.id else { return nil }

        var stale = false
        guard let url = try? URL(
            resolvingBookmarkData: authorization.bookmark,
            options: [.withSecurityScope, .withoutUI, .withoutMounting],
            relativeTo: nil, bookmarkDataIsStale: &stale,
        ), !stale else { return nil }
        return (grant, url)
    }

    func sameFolder(_ lhs: URL, _ rhs: URL) -> Bool {
        lhs.standardizedFileURL.path == rhs.standardizedFileURL.path
    }

    func isWorkspaceLoading(_ viewModel: any MCPAnalysisWorkspace) -> Bool {
        viewModel.isMCPWorkspaceLoading
    }

    func waitForWorkspaceLoad(
        viewModel: any MCPAnalysisWorkspace, checkRequest: () async throws -> Void,
    ) async throws {
        let clock = SuspendingClock()
        let deadline = clock.now.advanced(by: .seconds(120))
        while isWorkspaceLoading(viewModel) {
            try await checkRequest()
            guard clock.now < deadline else {
                throw JobError("RawCull is still loading a catalog after two minutes. Wait for the catalog and thumbnails to finish loading, then start a new request.")
            }
            try await Task.sleep(for: .milliseconds(250))
        }
        try await checkRequest()
    }

    func requireAvailableWorkspace(
        for url: URL, viewModel: any MCPAnalysisWorkspace, canStart: @MainActor () -> Bool, allowSwitch: Bool = false,
    ) throws {
        if viewModel.isMCPTerminationPending {
            throw JobError("RawCull is waiting to quit. Resolve any save prompt in RawCull, then start a new request.")
        }
        if isWorkspaceLoading(viewModel) {
            throw JobError("RawCull is loading a catalog. Wait for the catalog and thumbnails to finish loading, then start a new request.")
        }
        if !canStart() || viewModel.isDeepAIReviewBlockedByOtherWork || viewModel.isPreparingBurstCatalog
            || viewModel.isSharpnessCalibrationRunning {
            throw JobError("RawCull is running analysis or preparing burst results. Wait for that operation to finish, then start a new request.")
        }

        let selectedMatches = viewModel.selectedSource.map { sameFolder($0.url, url) } ?? true
        let loadedMatches = viewModel.loadedSource.map { sameFolder($0.url, url) } ?? true
        guard allowSwitch || (selectedMatches && loadedMatches) else {
            throw JobError("RawCull has another catalog open. Select the authorized catalog in RawCull, then start a new job.")
        }
    }

    func isAuthorized(_ job: AnalysisJob) throws -> Bool {
        if job.usesSetupApproval {
            return pendingApprovalForClaim?.id == job.jobId
        }
        let revision = grants.revision()
        if let revision, let cachedGrant = bookkeeping.cachedGrant, cachedGrant.revision == revision {
            return cachedGrant.catalogId == job.catalogId && cachedGrant.analysisEnabled
        }
        bookkeeping.cachedGrant = nil
        let grant = try grants.authorizedCatalog()
        if let revision, grants.revision() == revision {
            bookkeeping.cachedGrant = (revision, grant?.id, grant?.analysisEnabled == true)
        }
        return grant?.id == job.catalogId && grant?.analysisEnabled == true
    }

    func checkCurrent(_ job: AnalysisJob) throws {
        try Task.checkCancellation()
        do {
            guard let current = try jobs.read(), current.canPublish(for: job), try isAuthorized(job) else {
                throw CancellationError()
            }
        } catch is DecodingError {
            throw AnalysisJobStore.StoreError.damagedActiveJob
        }
    }

    func checkCurrentWithRetry(_ job: AnalysisJob) async throws {
        try await retryStorage { try checkCurrent(job) }
    }

    func storageFailureMessage(_ error: Error) -> String {
        switch error {
        case AnalysisJobStore.StoreError.busy:
            "MCP job storage stayed busy. Start a new request."

        case AnalysisJobStore.StoreError.unsupportedFormat:
            "The MCP job uses an unsupported format. Use the helper bundled with this RawCull installation."

        case AnalysisJobStore.StoreError.damagedActiveJob:
            "The active MCP job record is damaged. Start a new request after RawCull releases it."

        case AnalysisJobStore.StoreError.recoveredDamagedJob:
            "The damaged MCP job record was set aside. Start a new request."

        default:
            "RawCull could not read or save the MCP job. Start a new request."
        }
    }

    func updateWithRetry(
        _ change: (AnalysisJob?) throws -> AnalysisJob?,
    ) async throws {
        try await withJobLockRetry { _ = try jobs.updateLocked(change) }
    }

    func withJobLockRetry(_ operation: () throws -> Void) async throws {
        try await retryStorage { try jobs.withLock(operation) }
    }

    @discardableResult
    func retryStorage<Result>(_ operation: () throws -> Result) async throws -> Result {
        let deadline = ContinuousClock.now + .seconds(2)
        while true {
            do {
                return try operation()
            } catch where AnalysisJobStore.StoreError.isRetryable(error) && ContinuousClock.now < deadline {
                try await Task.sleep(for: .milliseconds(50))
            }
        }
    }

    func finish(_ job: AnalysisJob, as state: AnalysisJob.State, message: String? = nil) async {
        // A cancelled worker still needs to persist its final state.
        await Task { await persistFinish(job, as: state, message: message) }.value
    }

    func persistFinish(_ job: AnalysisJob, as state: AnalysisJob.State, message: String?) async {
        do {
            try await updateWithRetry { current in
                guard var current, current.jobId == job.jobId, current.catalogId == job.catalogId,
                      current.state == .running else { return nil }
                if isQuitting {
                    current.finish(.cancelled, message: "RawCull quit.")
                } else if current.cancellationRequested, state != .cancelled {
                    current.finish(.cancelled)
                } else {
                    current.finish(state, message: message)
                }
                return current
            }
        } catch {
            Logger.process.error("Could not finish the MCP analysis job.")
        }
    }

    struct JobError: Error {
        let message: String

        init(_ message: String) {
            self.message = message
        }
    }
}
