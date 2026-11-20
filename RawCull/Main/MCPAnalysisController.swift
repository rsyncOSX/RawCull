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
    private let environment: MCPAnalysisEnvironment
    private let grants: CatalogGrantStore
    private let jobs: AnalysisJobStore
    private var monitor: Task<Void, Never>?

    // MARK: State

    /// Identifies one activity, so a finished task can only end its own activity.
    private struct ActivityToken: Equatable {
        let value: UInt64
    }

    private struct SetupActivity {
        let token: ActivityToken
        var task: Task<Void, Never>?
        let deadline: Date
        var sheet: (parent: NSWindow, window: NSWindow)?
    }

    private struct AnalysisActivity {
        let token: ActivityToken
        var task: Task<Void, Never>?
        let job: AnalysisJob
    }

    private struct FollowUpActivity {
        let token: ActivityToken
        var task: Task<Void, Never>?
        let id: UUID
        let deadline: ContinuousClock.Instant
        /// Set when the controller stops the assessment for a known reason.
        var stopReason: String?
    }

    /// Catalog setup, catalog analysis and photo-assessment follow-ups never
    /// run at the same time.
    private enum Activity {
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

    private enum Lifecycle {
        case running
        /// The app asked to quit and is waiting on a save prompt; no new work starts.
        case terminationPending
        /// `stopForQuit()` ran; nothing is published after this.
        case quitting
    }

    private var activity: Activity = .idle
    private var lifecycle: Lifecycle = .running
    private var nextActivityToken: UInt64 = 0

    private struct SetupApproval {
        let id: UUID
        let url: URL
        let access: RawCullCatalogGrant
        let remember: Bool
        let expectedGrantID: UUID?
    }

    /// Created by an approved setup and consumed when the job it queued is
    /// claimed. It deliberately outlives the setup activity, so it is not part
    /// of `activity`.
    private var pendingApprovalForClaim: SetupApproval?

    /// Timers and caches of the polling loop.
    private struct PollBookkeeping {
        var inactiveRevision: AnalysisJobStore.Revision?
        var cachedGrant: (revision: AnalysisJobStore.Revision, catalogId: UUID?, analysisEnabled: Bool)?
        var nextHostPublication = Date.distantPast
        var nextSetupMaintenance = Date.distantPast
        var storageFailureSince: ContinuousClock.Instant?
    }

    private var bookkeeping = PollBookkeeping()

    private var isQuitting: Bool {
        lifecycle == .quitting
    }

    /// Termination is pending or the app is quitting: no new work starts.
    private var isTerminationPending: Bool {
        lifecycle != .running
    }

    private var isIdle: Bool {
        if case .idle = activity { true } else { false }
    }

    private var isSettingUp: Bool {
        if case .settingUp = activity { true } else { false }
    }

    private var isAnalyzing: Bool {
        if case .analyzing = activity { true } else { false }
    }

    private var isAssessing: Bool {
        if case .assessing = activity { true } else { false }
    }

    /// The job the running analysis works on.
    private var activeJob: AnalysisJob? {
        if case let .analyzing(analysis) = activity { analysis.job } else { nil }
    }

    /// Starts `next` (built with a fresh token) and returns that token.
    private func begin(_ next: (ActivityToken) -> Activity) -> ActivityToken {
        precondition(isIdle, "MCP activities never overlap")
        nextActivityToken &+= 1
        let token = ActivityToken(value: nextActivityToken)
        activity = next(token)
        return token
    }

    /// Attaches the task that runs the activity identified by `token`.
    private func attach(_ task: Task<Void, Never>, to token: ActivityToken) {
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
    private func end(_ token: ActivityToken) {
        guard activity.token == token else { return }
        activity = .idle
    }

    private func cancelAnalysis() {
        if case let .analyzing(analysis) = activity {
            analysis.task?.cancel()
        }
    }

    private func cancelFollowUp(reason: String? = nil) {
        guard case var .assessing(followUp) = activity else { return }
        if let reason {
            followUp.stopReason = reason
            activity = .assessing(followUp)
        }
        followUp.task?.cancel()
    }

    private func followUpStopReason(_ token: ActivityToken) -> String? {
        if case let .assessing(followUp) = activity, followUp.token == token { followUp.stopReason } else { nil }
    }

    /// What `start` was given; `tick()` reads it on every iteration.
    private struct MonitorContext {
        weak var viewModel: (any MCPAnalysisWorkspace)?
        let qwen: (any MCPPhotoAssessing)?
        let prepare: @MainActor () async -> Void
        let preparePhotoAssessment: @MainActor () async -> Void
        let canStart: @MainActor () -> Bool
    }

    private var context: MonitorContext?

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

    /// The follow-up source or the follow-up feature went away; the running
    /// assessment should stop. Kept as one `switch` rather than a multi-pattern
    /// `catch`, which the tree-sitter Swift grammar used by code tools cannot parse.
    private static func isFollowUpUnavailable(_ error: any Error) -> Bool {
        switch error {
        case FollowUpSourceSnapshot.SourceError.unavailable,
             AnalysisJobStore.FollowUpError.unavailable,
             AnalysisJobStore.FollowUpError.disabled:
            true
        default:
            false
        }
    }

    private func pollFollowUp(
        qwen: any MCPPhotoAssessing, viewModel: any MCPAnalysisWorkspace, prepare: @escaping @MainActor () async -> Void,
        canStart: @MainActor () -> Bool,
    ) throws {
        guard try jobs.followUpsEnabled() else {
            cancelFollowUp()
            return
        }
        if !isTerminationPending, environment.now() >= bookkeeping.nextHostPublication {
            try jobs.publishFollowUpHost(bundlePath: environment.hostBundlePath())
            bookkeeping.nextHostPublication = environment.now().addingTimeInterval(2)
        }
        if case let .assessing(running) = activity {
            let status: AnalysisJobStore.FollowUpRecord
            do { status = try jobs.followUpStatus(running.id) } catch where Self.isFollowUpUnavailable(error) {
                cancelFollowUp()
                return
            }
            if status.cancellationRequested {
                cancelFollowUp()
            } else if environment.instant() >= running.deadline {
                cancelFollowUp(reason: "executionTimeout")
            }
            return
        }
        guard !isTerminationPending, isIdle,
              let pending = try jobs.queuedFollowUp(), environment.now().timeIntervalSince(pending.createdAt) < 120,
              case let .started(worker) = try jobs.beginFollowUp(pending.request) else { return }

        let id = worker.request.id
        let lease = CombinedReviewLease.shared
        guard canStart(), !isWorkspaceLoading(viewModel), !viewModel.isDeepAIReviewBlockedByOtherWork,
              !viewModel.isPreparingBurstCatalog, (try? lease.acquire(id)) != nil
        else {
            try jobs.finishFollowUp(worker, result: nil, errorCode: "busy")
            return
        }
        let token = begin {
            .assessing(FollowUpActivity(token: $0, id: id, deadline: environment.instant().advanced(by: .seconds(180))))
        }
        lease.invalidateOwner = { [weak self] in
            self?.cancelFollowUp(reason: "modelChanged")
        }
        attach(Task {
            let activity = ProcessInfo.processInfo.beginActivity(
                options: [.userInitiatedAllowingIdleSystemSleep], reason: "RawCull MCP photo assessment",
            )
            defer {
                ProcessInfo.processInfo.endActivity(activity)
                lease.release(id)
                end(token)
            }
            do {
                if await qwen.assessmentIdentity() == nil {
                    await prepare()
                }
                try Task.checkCancellation()
                let output = try await assessFollowUp(worker, qwen: qwen)
                try await retryStorage {
                    try Task.checkCancellation()
                    try jobs.finishFollowUp(worker, result: JSONEncoder().encode(output),
                                            errorCode: output.assessedCount == 0 ? "allPhotosFailed" : nil)
                }
            } catch {
                let code: String? = if let stopReason = followUpStopReason(token) {
                    stopReason
                } else if error is CancellationError {
                    nil
                } else if error is QwenInferenceRuntime.MCPAssessmentError {
                    "modelChanged"
                } else if case QwenModelError.modelUnavailable = error {
                    "modelUnavailable"
                } else if error is FollowUpCatalogError {
                    "reauthorizationRequired"
                } else {
                    "assessmentFailed"
                }
                // Publish terminal state from a fresh task so a cancelled inference can still retry a busy store.
                await Task {
                    do {
                        try await retryStorage { try jobs.finishFollowUp(worker, result: nil, errorCode: code) }
                    } catch {
                        Logger.process.notice("MCP assessment ended without a publishable result.")
                    }
                }.value
            }
        }, to: token)
    }

    private func assessFollowUp(
        _ worker: AnalysisJobStore.FollowUpWorker, qwen: any MCPPhotoAssessing,
    ) async throws -> MCPPhotoAssessmentResult {
        guard let identity = await qwen.assessmentIdentity() else { throw QwenModelError.modelUnavailable }
        let access = try await retryStorage { try followUpCatalogAccess(for: worker.request) }
        defer { withExtendedLifetime(access) {} }
        let ids = try worker.request.target.photoIDs(in: worker.source)
        let burstID = worker.request.target.burstID
        let burst = try burstID.map { try worker.source.burst(id: $0) }
        var outcomes: [MCPPhotoAssessmentResult.Photo] = []
        for id in ids {
            try Task.checkCancellation()
            let sourceRank = burst?.ranks[id]
            guard let url = try? worker.source.resolve(photoID: id, in: access.url),
                  let image = await RawParserKitImageLoader.shared.thumbnailCGImage(for: url, maxPixelSize: 2048)
            else {
                outcomes.append(.init(photoId: id, errorCode: "unreadablePhoto", sourceRank: sourceRank))
                continue
            }
            do {
                let assessment = try await qwen.assessForMCP(rubric: worker.request.rubric, image: image, identity: identity)
                outcomes.append(.init(
                    photoId: id, assessedImage: .init(width: image.width, height: image.height),
                    findings: assessment.mcpFindings(for: worker.request.rubric), sourceRank: sourceRank,
                ))
            } catch QwenModelError.invalidStructuredResponse {
                outcomes.append(.init(photoId: id, errorCode: "invalidAssessment", sourceRank: sourceRank))
            } catch is CancellationError {
                guard await qwen.assessmentIdentity() == identity else {
                    throw QwenInferenceRuntime.MCPAssessmentError.modelChanged
                }
                throw CancellationError()
            } catch let error as QwenInferenceRuntime.MCPAssessmentError {
                throw error
            } catch {
                outcomes.append(.init(photoId: id, errorCode: "inferenceFailed", sourceRank: sourceRank))
            }
        }
        try Task.checkCancellation()
        guard await qwen.assessmentIdentity() == identity else { throw QwenInferenceRuntime.MCPAssessmentError.modelChanged }
        let assessed = outcomes.filter { $0.findings != nil }.count
        return .init(
            requestId: worker.request.id, sourceJobId: worker.request.sourceJobID, model: identity.name,
            assessedCount: assessed, failedCount: outcomes.count - assessed, photos: outcomes,
            burstId: burstID, burstFrameCount: burst?.photoIDs.count,
        )
    }

    private func cancelSetup() {
        guard case var .settingUp(setup) = activity else { return }
        setup.task?.cancel()
        if let sheet = setup.sheet, sheet.parent.sheets.contains(sheet.window) {
            setup.sheet = nil
            activity = .settingUp(setup)
            sheet.parent.endSheet(sheet.window, returnCode: .cancel)
        }
    }

    private func setSetupSheet(_ sheet: (parent: NSWindow, window: NSWindow)?) {
        guard case var .settingUp(setup) = activity else { return }
        setup.sheet = sheet
        activity = .settingUp(setup)
    }

    private func showSetupSheet(
        _ sheet: NSWindow, for request: CatalogSetupRequest, in parent: NSWindow,
        present: @MainActor () async -> NSApplication.ModalResponse,
    ) async throws -> NSApplication.ModalResponse {
        try Task.checkCancellation()
        guard !request.isExpired else { throw JobError("The catalog setup request expired. Start a new request.") }
        sheet.preventsApplicationTerminationWhenModal = false
        setSetupSheet((parent, sheet))
        defer { setSetupSheet(nil) }
        let response = if let presentSetupSheet = environment.presentSetupSheet {
            await presentSetupSheet(sheet, parent)
        } else {
            await present()
        }
        guard !request.isExpired else { throw JobError("The catalog setup request expired. Start a new request.") }
        try Task.checkCancellation()
        return response
    }

    private func poll(
        _ viewModel: any MCPAnalysisWorkspace,
        prepare: @escaping @MainActor () async -> Void,
        canStart: @escaping @MainActor () -> Bool,
    ) throws {
        let revision = jobs.revision()
        if let revision, revision == bookkeeping.inactiveRevision {
            return
        }
        bookkeeping.inactiveRevision = nil
        let storedJob: AnalysisJob?
        do {
            storedJob = try jobs.readRecovering()
        } catch AnalysisJobStore.StoreError.unsupportedFormat {
            bookkeeping.inactiveRevision = revision
            throw AnalysisJobStore.StoreError.unsupportedFormat
        }
        if let photoAccess = MCPJobPhotoAccess.saved(in: environment.defaults),
           storedJob?.jobId != photoAccess.jobID || storedJob?.hasShareableResult != true {
            MCPJobPhotoAccess.save(nil, in: environment.defaults)
        }
        guard let job = storedJob else {
            pendingApprovalForClaim = nil
            cancelAnalysis()
            return
        }
        if case let .analyzing(running) = activity {
            guard job.jobId == running.job.jobId, job.catalogId == running.job.catalogId,
                  job.state == .running, !job.cancellationRequested, try isAuthorized(job)
            else {
                cancelAnalysis()
                return
            }
            try updateProgress(job, viewModel: viewModel)
            return
        }
        guard job.state.isActive else {
            if pendingApprovalForClaim?.id == job.jobId {
                pendingApprovalForClaim = nil
            }
            bookkeeping.inactiveRevision = revision
            return
        }
        if job.usesWorkerLease || job.isExpired(at: .now) {
            _ = try jobs.expireInterruptedJob()
            return
        }
        guard job.state == .queued, isIdle, let lease = try jobs.acquireWorkerLease() else { return }

        var didClaim = false
        let claimed = try jobs.update { current in
            guard var current, current.jobId == job.jobId, current.catalogId == job.catalogId,
                  current.state == .queued, !current.isExpired(at: .now) else { return nil }
            current.claim()
            current.recordHeartbeat()
            current.stage = "openingCatalog"
            current.message = nil
            didClaim = true
            return current
        }
        guard didClaim, let claimed else { return }

        let token = begin { .analyzing(AnalysisActivity(token: $0, job: claimed)) }
        attach(Task { [weak self, weak viewModel, lease] in
            guard let self else { return }
            let processActivity = ProcessInfo.processInfo.beginActivity(
                options: .userInitiatedAllowingIdleSystemSleep, reason: "RawCull MCP catalog analysis",
            )
            defer {
                withExtendedLifetime(lease) {}
                ProcessInfo.processInfo.endActivity(processActivity)
                end(token)
            }
            guard let viewModel else {
                if !isQuitting {
                    await finish(claimed, as: .cancelled)
                }
                return
            }
            do {
                try await run(claimed, viewModel: viewModel, prepare: prepare, canStart: canStart)
            } catch is CancellationError {
                if !isQuitting {
                    await finish(claimed, as: .cancelled)
                }
            } catch let error as JobError {
                if !isQuitting {
                    await finish(claimed, as: .failed, message: error.message)
                }
            } catch where error is AnalysisJobStore.StoreError || AnalysisJobStore.StoreError.isRetryable(error) {
                if !isQuitting {
                    await finish(claimed, as: .failed, message: storageFailureMessage(error))
                }
            } catch {
                if !isQuitting {
                    await finish(
                        claimed, as: .failed,
                        message: "RawCull could not open or analyze the authorized catalog. Check access and authorize it again.",
                    )
                }
            }
        }, to: token)
    }

    private var setupStore: CatalogSetupStore {
        CatalogSetupStore(jobs: jobs)
    }

    private func respond(
        to request: CatalogSetupRequest, viewModel: any MCPAnalysisWorkspace, canStart: @MainActor () -> Bool,
    ) async {
        var response = request
        do {
            try Task.checkCancellation()
            guard !request.isExpired else { throw JobError("The catalog setup request expired. Start a new request.") }
            let saved = try savedCatalog()
            let match = matchingCatalog(for: request.catalogHint ?? "", viewModel: viewModel, saved: saved)
            if let saved, let match, sameFolder(match, saved.url), readableFolderAccess(saved.url, viewModel: viewModel) != nil {
                try await queueSetup(
                    request, url: saved.url, remember: false, savedGrantId: saved.grant.id,
                    viewModel: viewModel, canStart: canStart,
                )
                return
            }

            guard let window = environment.hostWindow() else {
                throw JobError("Open RawCull's main window and start a new request.")
            }

            environment.activateApp()

            // Keep the same scope from folder validation through the queued handoff.
            let url: URL
            let access: RawCullCatalogGrant
            if let match, let matchedAccess = readableFolderAccess(match, viewModel: viewModel) {
                url = match
                access = matchedAccess
            } else {
                url = try await chooseFolder(for: request, viewModel: viewModel, window: window)
                guard let pickedAccess = readableFolderAccess(url, viewModel: viewModel) else {
                    throw JobError("RawCull could not access the selected folder. Choose it again in the folder picker.")
                }
                access = pickedAccess
            }
            let confirmation = NSAlert()
            let existingGrant = try grants.authorizedCatalog()
            confirmation.messageText = String(localized: "Approve burst analysis?")
            let sharing = if try jobs.followUpsEnabled() {
                String(localized: "RawCull will analyze \(url.path(percentEncoded: false)) and share the ranked bursts with the MCP client. This also allows local assessment of photos from this job and shares text findings. The job and its photo access stay available after you quit, until you clear the result, revoke access, or replace the job.")
            } else {
                String(localized: "RawCull will analyze \(url.path(percentEncoded: false)) and share the ranked bursts with the MCP client. The rankings stay available after you quit, until you clear the result, revoke access, or replace the job. MCP photo assessments are off.")
            }
            let remembering = if let existingGrant {
                String(localized: "Approve and Remember also replaces the saved authorization for \(existingGrant.displayName) and allows future analysis of the newly approved catalog.")
            } else {
                String(localized: "Approve and Remember also saves authorization for future analysis of this catalog.")
            }
            confirmation.informativeText = sharing + "\n\n" + remembering
            confirmation.addButton(withTitle: String(localized: "Approve This Job"))
            confirmation.addButton(withTitle: String(localized: "Approve and Remember"))
            confirmation.addButton(withTitle: String(localized: "Deny")).keyEquivalent = "\u{1b}"
            let approval = try await showSetupSheet(confirmation.window, for: request, in: window) {
                await confirmation.beginSheetModal(for: window)
            }
            guard approval == .alertFirstButtonReturn || approval == .alertSecondButtonReturn else {
                throw CancellationError()
            }
            try Task.checkCancellation()
            try await queueSetup(
                request, url: url, remember: approval == .alertSecondButtonReturn, access: access,
                expectedGrantID: existingGrant?.id,
                viewModel: viewModel, canStart: canStart,
            )
            return
        } catch is CancellationError {
            response.state = .denied
            response.message = "Catalog setup was cancelled or denied in RawCull."
        } catch let error as JobError {
            response.state = .failed
            response.message = error.message
        } catch {
            response.state = .failed
            response.message = "RawCull could not open the selected catalog or queue the analysis."
        }
        // Task cancellation dismisses setup for quit or expiry. An explicit
        // denial also throws CancellationError, but leaves the task active.
        guard !Task.isCancelled else { return }
        do {
            try await withJobLockRetry {
                guard !Task.isCancelled, try setupStore.pendingLocked()?.requestId == request.requestId else { return }
                if response.state == .denied {
                    response.deniedAt = .now
                }
                try setupStore.saveLocked(response)
            }
        } catch is CancellationError {
            return
        } catch {
            Logger.process.error("Could not save the MCP catalog setup response.")
        }
    }

    private func savedCatalog() throws -> (grant: CatalogGrant, url: URL)? {
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

    /// Resolves the saved bookmark independently of the visible workspace.
    func resolveFollowUpTargets(
        for worker: AnalysisJobStore.FollowUpWorker,
    ) throws -> (photos: [URL], access: RawCullCatalogGrant) {
        let access = try followUpCatalogAccess(for: worker.request)
        return try (worker.resolveTargets(in: access.url), access)
    }

    func followUpCatalogAccess(for request: AnalysisJobStore.FollowUpRequest) throws -> RawCullCatalogGrant {
        _ = try jobs.readFollowUpSource(catalogID: request.catalogID, jobID: request.sourceJobID)
        let url: URL
        if let jobAccess = MCPJobPhotoAccess.saved(in: environment.defaults), jobAccess.jobID == request.sourceJobID {
            var stale = false
            guard let resolved = try? URL(
                resolvingBookmarkData: jobAccess.bookmark,
                options: [.withSecurityScope, .withoutUI, .withoutMounting],
                relativeTo: nil, bookmarkDataIsStale: &stale,
            ), !stale else { throw FollowUpCatalogError.reauthorizationRequired }
            url = resolved
        } else {
            guard let saved = try savedCatalog(), saved.grant.id == request.catalogID else {
                throw FollowUpCatalogError.reauthorizationRequired
            }
            url = saved.url
        }
        if let existing = RawCullCatalogAccess.shared.retainAccess(for: [url]).first,
           existing.url.standardizedFileURL == url.standardizedFileURL {
            return existing
        }
        guard url.startAccessingSecurityScopedResource() else { throw FollowUpCatalogError.reauthorizationRequired }
        let access = RawCullCatalogGrant(url: url) { $0.stopAccessingSecurityScopedResource() }
        RawCullCatalogAccess.shared.register(access)
        return access
    }

    enum FollowUpCatalogError: Error {
        case reauthorizationRequired
    }

    private func sameFolder(_ lhs: URL, _ rhs: URL) -> Bool {
        lhs.standardizedFileURL.path == rhs.standardizedFileURL.path
    }

    private func matchingCatalog(
        for hint: String, viewModel: any MCPAnalysisWorkspace, saved: (grant: CatalogGrant, url: URL)?,
    ) -> URL? {
        let query = hint.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return nil }
        let path = query.hasPrefix("/") ? URL(fileURLWithPath: query, isDirectory: true) : nil
        var candidates = viewModel.sources.map { (name: $0.name, url: $0.url) }
        if let selected = viewModel.selectedSource {
            candidates.append((selected.name, selected.url))
        }
        if let saved {
            candidates.append((saved.grant.displayName, saved.url))
        }
        var match: URL?
        for candidate in candidates {
            let matches = if let path {
                sameFolder(path, candidate.url)
            } else {
                candidate.name.compare(query, options: .caseInsensitive) == .orderedSame
                    || candidate.url.lastPathComponent.compare(query, options: .caseInsensitive) == .orderedSame
            }
            guard matches else { continue }
            if let match, !sameFolder(match, candidate.url) {
                return nil
            }
            match = candidate.url
        }
        return match
    }

    private func readableFolderAccess(_ url: URL, viewModel: any MCPAnalysisWorkspace) -> RawCullCatalogGrant? {
        guard let access = viewModel.retainSecurityScopedAccess(for: url),
              let values = try? url.resourceValues(forKeys: [.isDirectoryKey, .isReadableKey]),
              values.isDirectory == true, values.isReadable == true else { return nil }
        return access
    }

    private func chooseFolder(
        for request: CatalogSetupRequest, viewModel: any MCPAnalysisWorkspace, window: NSWindow,
    ) async throws -> URL {
        let chooser = NSAlert()
        chooser.messageText = String(localized: "Choose a catalog for burst analysis")
        let hint = request.displayHint
        let instructions = String(localized: "Select the folder you want RawCull to analyze. You will review the selected path before approving.")
        if hint.isEmpty {
            chooser.informativeText = instructions
        } else {
            let clientHint = String(localized: "Folder hint from the MCP client: “\(hint)”")
            chooser.informativeText = instructions + "\n\n" + clientHint
        }
        chooser.addButton(withTitle: String(localized: "Choose Folder…"))
        let current = viewModel.selectedSource
        if current != nil {
            chooser.addButton(withTitle: String(localized: "Use Current Catalog"))
        }
        chooser.addButton(withTitle: String(localized: "Deny")).keyEquivalent = "\u{1b}"
        let choice = try await showSetupSheet(chooser.window, for: request, in: window) {
            await chooser.beginSheetModal(for: window)
        }
        if choice == .alertFirstButtonReturn {
            let picker = NSOpenPanel()
            picker.canChooseDirectories = true
            picker.canChooseFiles = false
            picker.allowsMultipleSelection = false
            let hint = (request.catalogHint ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            if hint.hasPrefix("/") {
                picker.directoryURL = URL(fileURLWithPath: hint, isDirectory: true).deletingLastPathComponent()
            } else if let current {
                picker.directoryURL = current.url.deletingLastPathComponent()
            }
            let selection = try await showSetupSheet(picker, for: request, in: window) {
                await picker.beginSheetModal(for: window)
            }
            guard selection == .OK, let picked = picker.url else {
                throw CancellationError()
            }
            return picked
        } else if choice == .alertSecondButtonReturn, let current {
            return current.url
        } else {
            throw CancellationError()
        }
    }

    private func queueSetup(
        _ request: CatalogSetupRequest, url: URL, remember: Bool, savedGrantId: UUID? = nil, access: RawCullCatalogGrant? = nil,
        expectedGrantID: UUID? = nil,
        viewModel: any MCPAnalysisWorkspace, canStart: @MainActor () -> Bool,
    ) async throws {
        try await waitForWorkspaceLoad(viewModel: viewModel) {
            try Task.checkCancellation()
            try await retryStorage {
                guard !request.isExpired, try setupStore.pending()?.requestId == request.requestId else {
                    throw JobError("The catalog setup request expired. Start a new request.")
                }
            }
        }
        try requireAvailableWorkspace(for: url, viewModel: viewModel, canStart: canStart, allowSwitch: true)
        try await withJobLockRetry {
            try Task.checkCancellation()
            guard !request.isExpired, try setupStore.pendingLocked()?.requestId == request.requestId else {
                throw JobError("The catalog setup request expired. Start a new request.")
            }
            let now = Date.now
            if let savedGrantId {
                guard let grant = try grants.authorizedCatalog(), grant.id == savedGrantId,
                      grant.analysisEnabled == true
                else {
                    throw JobError("Catalog authorization changed. Start a new request.")
                }
            }
            if remember {
                try requireUnchangedGrant(expectedGrantID)
            }
            var job = AnalysisJob(jobId: UUID(), catalogId: savedGrantId ?? UUID(), createdAt: now, updatedAt: now)
            if savedGrantId != nil {
                job.usesSavedGrant = true
            }
            job.setupRequestId = request.requestId
            job.setupHintDigest = request.replayDigest
            _ = try jobs.updateLocked { current in
                guard current?.state.isActive != true else {
                    throw JobError("An analysis is already active. Wait for it to finish and try again.")
                }
                return job
            }
            if let access {
                pendingApprovalForClaim = SetupApproval(id: job.jobId, url: url, access: access,
                                              remember: remember, expectedGrantID: expectedGrantID)
            }
            var response = request
            response.state = .queued
            response.catalogId = job.catalogId
            response.jobId = job.jobId
            do {
                try setupStore.saveLocked(response)
            } catch {
                // The published job carries the request ID so the client can still find it.
                Logger.process.error("Could not save the queued MCP catalog setup response.")
            }
        }
    }

    /// Call under the job lock before publishing a job or replacing its grant.
    private func requireUnchangedGrant(_ expectedID: UUID?) throws {
        guard try grants.authorizedCatalog()?.id == expectedID else {
            throw JobError("The saved catalog authorization changed. Start a new request to review the change.")
        }
    }

    private func run(
        _ job: AnalysisJob,
        viewModel: any MCPAnalysisWorkspace,
        prepare: @MainActor () async -> Void,
        canStart: @MainActor () -> Bool,
    ) async throws {
        let url: URL
        let name: String
        let grant: CatalogGrant?
        let authorization: MCPAnalysisAuthorization?
        let setupApproval = pendingApprovalForClaim.flatMap { $0.id == job.jobId ? $0 : nil }
        defer {
            if pendingApprovalForClaim?.id == job.jobId {
                pendingApprovalForClaim = nil
            }
        }
        if job.usesSetupApproval {
            guard let setupApproval else {
                throw JobError("RawCull restarted before it could use the approved folder. Submit a new catalog setup request.")
            }
            url = setupApproval.url
            name = url.lastPathComponent
            grant = nil
            authorization = nil
        } else {
            guard let savedGrant = try grants.authorizedCatalog(), savedGrant.id == job.catalogId,
                  savedGrant.analysisEnabled == true, savedGrant.summary?.photos != nil,
                  let data = MCPAnalysisAuthorization.savedData(in: environment.defaults),
                  let savedAuthorization = try? JSONDecoder().decode(MCPAnalysisAuthorization.self, from: data),
                  savedAuthorization.catalogId == savedGrant.id
            else { throw JobError("Authorize the loaded catalog for analysis in RawCull's MCP settings.") }

            var stale = false
            url = try URL(
                resolvingBookmarkData: savedAuthorization.bookmark,
                options: [.withSecurityScope, .withoutUI, .withoutMounting],
                relativeTo: nil, bookmarkDataIsStale: &stale,
            )
            guard !stale else { throw JobError("The authorized catalog moved or its bookmark expired. Authorize it again.") }
            name = savedGrant.displayName
            grant = savedGrant
            authorization = savedAuthorization
        }
        try await waitForWorkspaceLoad(viewModel: viewModel) { try await checkCurrentWithRetry(job) }
        try requireAvailableWorkspace(for: url, viewModel: viewModel, canStart: canStart, allowSwitch: job.setupRequestId != nil)
        await prepare()
        try await waitForWorkspaceLoad(viewModel: viewModel) { try await checkCurrentWithRetry(job) }
        try requireAvailableWorkspace(for: url, viewModel: viewModel, canStart: canStart, allowSwitch: job.setupRequestId != nil)

        let index = viewModel.sources.firstIndex { sameFolder($0.url, url) }
        let selection = viewModel.selectedSource.flatMap {
            sameFolder($0.url, url) ? $0 : nil
        }
        let target = selection ?? index.map { viewModel.sources[$0] } ?? ARWSourceCatalog(name: name, url: url)
        if index == nil {
            viewModel.sources.append(target)
        }
        let needsCatalogLoad = grant?.recurringFolder == true
            || viewModel.loadedSource != target || viewModel.files.isEmpty
            || !viewModel.hasActiveSecurityScopedAccess(for: url)
        if viewModel.selectedSource != target {
            viewModel.selectedSource = target
        }
        if needsCatalogLoad {
            viewModel.startCatalogLoad(for: target, scopedURL: url, retainedAccess: setupApproval?.access)
            try await waitForCatalog(job, target: target, viewModel: viewModel)
        }
        let photoIds: [UUID: String]
        let refreshedSummary: CatalogSummary?
        if let grant, grant.recurringFolder == true {
            guard let summary = viewModel.mcpCatalogSummary(scanId: job.jobId) else {
                throw JobError("No supported photos were found in the authorized folder.")
            }
            let prefix = summary.photoIdPrefix(catalogId: grant.id)
            photoIds = Dictionary(uniqueKeysWithValues: viewModel.files.enumerated().map { offset, file in
                (file.id, "\(prefix)\(offset)")
            })
            refreshedSummary = summary
        } else if let photos = grant?.summary?.photos, let authorization {
            refreshedSummary = nil
            photoIds = try snapshotPhotoIds(files: viewModel.files, photos: photos, authorization: authorization)
        } else {
            refreshedSummary = nil
            photoIds = Dictionary(uniqueKeysWithValues: viewModel.files.enumerated().map { offset, file in
                (file.id, "\(job.catalogId.uuidString):\(offset)")
            })
            if let setupApproval, setupApproval.remember {
                try await withJobLockRetry {
                    try checkCurrent(job)
                    try requireUnchangedGrant(setupApproval.expectedGrantID)
                    try viewModel.authorizeCatalogForMCPJob(catalogId: job.catalogId)
                }
            }
        }
        try await checkCurrentWithRetry(job)
        if viewModel.isSemanticSearchActive {
            await viewModel.clearActiveSemanticSearchForMCP()
            try await checkCurrentWithRetry(job)
        }
        guard viewModel.selectedSource == target, viewModel.loadedSource == target,
              viewModel.hasActiveSecurityScopedAccess(for: url), canStart(),
              !viewModel.isDeepAIReviewBlockedByOtherWork, !viewModel.isPreparingBurstCatalog
        else { throw JobError("The catalog changed or another operation started. Start a new job.") }

        let orderedFiles = viewModel.fullCatalogBurstAnalysisFiles
        let generation = viewModel.burstAnalysisGeneration &+ 1
        let similaritySignature = viewModel.currentBurstSimilaritySignature
        let sharpnessSignature = viewModel.currentSharpnessScoringSignature
        let result = await viewModel.startBurstAnalysis(catalog: target.url, files: orderedFiles)
        try await checkCurrentWithRetry(job)
        guard viewModel.selectedSource == target, viewModel.burstAnalysisGeneration == generation,
              viewModel.currentBurstSimilaritySignature == similaritySignature,
              viewModel.currentSharpnessScoringSignature == sharpnessSignature,
              let result else { throw JobError("The catalog or analysis settings changed during the job.") }
        guard !result.diagnostics.contains(.cacheSaveFailed) else {
            throw JobError("RawCull could not save the ranked bursts to its analysis cache.")
        }

        let output = makeResults(result, job: job, photoIds: photoIds, viewModel: viewModel)
        let source = makeFollowUpSource(result, job: job, catalog: url, files: orderedFiles, photoIDs: photoIds)
        let oneTimeApproval = setupApproval?.remember == false
        let jobPhotoAccess: Data?
        if oneTimeApproval {
            let bookmark: Data?
            do {
                bookmark = try url.bookmarkData(
                    options: [.withSecurityScope, .securityScopeAllowOnlyReadAccess],
                    includingResourceValuesForKeys: nil, relativeTo: nil,
                )
            } catch {
                bookmark = nil
                Logger.process.error(
                    "Could not save read-only access for MCP photo assessments: \(error.localizedDescription, privacy: .public)",
                )
            }
            jobPhotoAccess = try bookmark.map {
                try JSONEncoder().encode(MCPJobPhotoAccess(jobID: job.jobId, bookmark: $0))
            }
        } else {
            jobPhotoAccess = nil
        }
        try await updateWithRetry { current in
            try Task.checkCancellation()
            guard var current, current.canPublish(for: job), try isAuthorized(job) else { throw CancellationError() }
            if let refreshedSummary {
                try grants.refreshRecurringLocked(catalogID: job.catalogId, summary: refreshedSummary)
            }
            let savedGrant = try grants.authorizedCatalog()
            if let source, jobPhotoAccess != nil || (savedGrant?.id == job.catalogId && savedGrant?.analysisEnabled == true) {
                do {
                    try jobs.stageFollowUpSourceLocked(source)
                    if let jobPhotoAccess {
                        MCPJobPhotoAccess.save(jobPhotoAccess, in: environment.defaults)
                        current.allowsJobPhotoAccess = true
                    }
                } catch {
                    Logger.process.error("Could not save the MCP follow-up source snapshot.")
                }
            }
            current.catalogDisplayName = name
            current.coverage = output.coverage
            current.bursts = output.bursts
            current.filesScanned = photoIds.count
            current.filesAnalyzed = photoIds.count - output.coverage.unevaluatedCount
            current.finish(.completed)
            return current
        }
        if needsCatalogLoad, grant?.recurringFolder != true || selection == nil {
            viewModel.presentBurstResultsAfterMCPJob()
        }
    }

    private func isWorkspaceLoading(_ viewModel: any MCPAnalysisWorkspace) -> Bool {
        viewModel.isMCPWorkspaceLoading
    }

    private func waitForWorkspaceLoad(
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

    private func requireAvailableWorkspace(
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

    private func waitForCatalog(
        _ job: AnalysisJob, target: ARWSourceCatalog, viewModel: any MCPAnalysisWorkspace,
    ) async throws {
        do {
            try await waitForCatalogLoad(job, target: target, viewModel: viewModel)
        } catch is CancellationError {
            if viewModel.selectedSource == target {
                viewModel.cancelCatalogLoad()
            }
            throw CancellationError()
        }
    }

    private func waitForCatalogLoad(
        _ job: AnalysisJob, target: ARWSourceCatalog, viewModel: any MCPAnalysisWorkspace,
    ) async throws {
        while viewModel.isCatalogTransitionActive {
            try await checkCurrentWithRetry(job)
            guard viewModel.selectedSource == target else { throw CancellationError() }
            try await Task.sleep(for: .milliseconds(250))
        }
        try await checkCurrentWithRetry(job)
        guard viewModel.catalogPersistenceError == nil else {
            throw JobError("RawCull could not load or save culling data. Resolve the error in RawCull, then start a new request.")
        }
        guard viewModel.selectedSource == target else {
            throw JobError("The catalog selection changed while loading. Select the requested folder and start a new request.")
        }
        switch viewModel.catalogLoadFailure {
        case .folderAccess:
            throw JobError("RawCull could not access the selected folder. Check that it is available and select it again.")

        case .noPhotos:
            throw JobError("RawCull found no supported photos in the selected folder. Check that it is readable and contains supported photos.")

        case nil:
            break
        }
        guard viewModel.loadedSource == target, !viewModel.isScanningCatalog,
              viewModel.hasActiveSecurityScopedAccess(for: target.url), !viewModel.files.isEmpty
        else { throw JobError("RawCull did not finish loading the selected catalog. Open it in RawCull and try again.") }
    }

    private func snapshotPhotoIds(
        files: [FileItem], photos: [CatalogPhoto], authorization: MCPAnalysisAuthorization,
    ) throws -> [UUID: String] {
        let byName = Dictionary(files.map { ($0.url.lastPathComponent, $0.id) }, uniquingKeysWith: { first, _ in first })
        guard photos.count == files.count, byName.count == files.count,
              try MCPAnalysisAuthorization.fingerprint(for: files) == authorization.fingerprint
        else { throw JobError("The catalog changed since authorization. Reload it and authorize it again.") }
        var ids: [UUID: String] = [:]
        for (offset, photo) in photos.enumerated() {
            guard let id = byName[photo.name], ids[id] == nil else {
                throw JobError("The catalog no longer matches the authorized photo list.")
            }
            ids[id] = "\(authorization.catalogId.uuidString):\(offset)"
        }
        return ids
    }

    private func makeFollowUpSource(
        _ result: BurstAnalysisPipelineResult, job: AnalysisJob, catalog: URL,
        files: [FileItem], photoIDs: [UUID: String],
    ) -> FollowUpSourceSnapshot? {
        let root = catalog.standardizedFileURL.pathComponents
        var photos: [String: FollowUpSourceSnapshot.Photo] = [:]
        for file in files {
            guard let photoID = photoIDs[file.id] else { continue }
            let path = file.url.standardizedFileURL.pathComponents
            guard path.count > root.count, path.starts(with: root) else { return nil }
            photos[photoID] = .init(
                relativePath: path.dropFirst(root.count).joined(separator: "/"),
                size: file.size,
                modified: file.dateModified,
            )
        }
        var bursts: [String: FollowUpSourceSnapshot.Burst] = [:]
        for ranking in result.rankings {
            let members = ranking.fileIDs.compactMap { photoIDs[$0] }
            guard members.count == ranking.fileIDs.count,
                  members.allSatisfy({ photos[$0] != nil }) else { return nil }
            var ranks: [String: Int] = [:]
            for (index, candidate) in ranking.candidates.enumerated() {
                if let photoID = photoIDs[candidate.fileID] {
                    ranks[photoID] = index + 1
                }
            }
            bursts[sharedBurstID(job: job, groupID: ranking.groupID)] = .init(
                photoIDs: members,
                ranks: ranks,
                recommendedPhotoID: ranking.recommendedFileID.flatMap { photoIDs[$0] },
                alternatePhotoID: ranking.secondBestFileID.flatMap { photoIDs[$0] },
            )
        }
        return .init(jobID: job.jobId, catalogID: job.catalogId, photos: photos, bursts: bursts)
    }

    private func sharedBurstID(job: AnalysisJob, groupID: Int) -> String {
        "\(job.catalogId.uuidString):\(job.jobId.uuidString):\(groupID)"
    }

    private func makeResults(
        _ result: BurstAnalysisPipelineResult, job: AnalysisJob,
        photoIds: [UUID: String], viewModel: any MCPAnalysisWorkspace,
    ) -> (coverage: AnalysisJob.Coverage, bursts: [AnalysisJob.Burst]) {
        let names = Dictionary(uniqueKeysWithValues: viewModel.files.map { ($0.id, $0.url.lastPathComponent) })
        let scores = viewModel.currentSharpnessScores
        let embeddings = viewModel.currentSimilarityEmbeddings
        let grouped = Set(result.groups.flatMap(\.fileIDs))
        var skipped: [String: Int] = [:]
        var backendCounts: [String: Int] = [:]
        for id in photoIds.keys {
            if let backend = embeddings[id]?.descriptor.backend {
                backendCounts[backend, default: 0] += 1
            }
            let reason: String
            switch (scores[id] != nil, embeddings[id] != nil) {
            case (false, false): reason = "missingSharpnessAndSimilarity"
            case (false, true): reason = "missingSharpness"
            case (true, false): reason = "missingSimilarity"

            case (true, true):
                guard !grouped.contains(id) else { continue }
                reason = "notGrouped"
            }
            skipped[reason, default: 0] += 1
        }

        let bursts = result.rankings.map { ranking in
            let preferred = [ranking.recommendedFileID, ranking.secondBestFileID].compactMap { $0 }
            let preferredSet = Set(preferred)
            let byId = Dictionary(ranking.candidates.map { ($0.fileID, $0) }, uniquingKeysWith: { first, _ in first })
            let candidates = preferred.compactMap { byId[$0] }
                + ranking.candidates.lazy.filter { !preferredSet.contains($0.fileID) }.prefix(5)
            return AnalysisJob.Burst(
                id: sharedBurstID(job: job, groupID: ranking.groupID),
                frameCount: ranking.fileIDs.count,
                recommendedPhotoId: ranking.recommendedFileID.flatMap { photoIds[$0] },
                alternatePhotoId: ranking.secondBestFileID.flatMap { photoIds[$0] },
                confidence: ranking.confidence.rawValue,
                reasons: ranking.reasons,
                cautions: ranking.cautions,
                candidates: candidates.prefix(5).compactMap { candidate in
                    guard let id = photoIds[candidate.fileID], let name = names[candidate.fileID] else { return nil }
                    return AnalysisJob.Candidate(
                        photoId: id, name: name,
                        score: candidate.overallScore.isFinite ? Double(candidate.overallScore) : nil,
                        confidence: candidate.confidence.rawValue,
                        reasons: candidate.reasons, cautions: candidate.cautions,
                    )
                },
            )
        }
        let singletons = result.groups.reduce(into: 0) { count, group in
            if group.fileIDs.count == 1 || group.id == -1 {
                count += group.fileIDs.count
            }
        }
        let coverage = AnalysisJob.Coverage(
            photoCount: photoIds.count, burstCount: bursts.count, singletonCount: singletons,
            unevaluatedCount: skipped.values.reduce(0, +), skippedByReason: skipped,
            similarityBackends: backendCounts,
        )
        return (coverage, bursts)
    }

    private func isAuthorized(_ job: AnalysisJob) throws -> Bool {
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

    private func checkCurrent(_ job: AnalysisJob) throws {
        try Task.checkCancellation()
        do {
            guard let current = try jobs.read(), current.canPublish(for: job), try isAuthorized(job) else {
                throw CancellationError()
            }
        } catch is DecodingError {
            throw AnalysisJobStore.StoreError.damagedActiveJob
        }
    }

    private func checkCurrentWithRetry(_ job: AnalysisJob) async throws {
        try await retryStorage { try checkCurrent(job) }
    }

    private func storageFailureMessage(_ error: Error) -> String {
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

    private func updateProgress(_ job: AnalysisJob, viewModel: any MCPAnalysisWorkspace) throws {
        let progress = viewModel.burstAnalysisProgress
        let scanned = viewModel.scanDiscoveredCount
        try jobs.update { current in
            guard var current, current.jobId == job.jobId, current.catalogId == job.catalogId,
                  current.state == .running, !current.cancellationRequested else { return nil }
            current.stage = progress.isRunning ? progress.step.rawValue : "openingCatalog"
            current.recordHeartbeat()
            current.filesScanned = current.stage == "openingCatalog" ? scanned : viewModel.files.count
            if progress.step == .grouping || progress.step == .ranking || progress.step == .savingCache {
                current.filesAnalyzed = viewModel.currentSimilarityEmbeddings.keys.lazy
                    .filter { viewModel.currentSharpnessScores[$0] != nil }.count
            }
            current.stageTotal = progress.isCountBased ? progress.total : nil
            current.stageCompleted = switch progress.step {
            case .scoringSharpness: viewModel.sharpnessScoringProgress
            case .indexingSimilarity: viewModel.similarityIndexingProgress
            default: nil
            }
            return current
        }
    }

    private func updateWithRetry(
        _ change: (AnalysisJob?) throws -> AnalysisJob?,
    ) async throws {
        try await withJobLockRetry { _ = try jobs.updateLocked(change) }
    }

    private func withJobLockRetry(_ operation: () throws -> Void) async throws {
        try await retryStorage { try jobs.withLock(operation) }
    }

    @discardableResult
    private func retryStorage<Result>(_ operation: () throws -> Result) async throws -> Result {
        let deadline = ContinuousClock.now + .seconds(2)
        while true {
            do {
                return try operation()
            } catch where AnalysisJobStore.StoreError.isRetryable(error) && ContinuousClock.now < deadline {
                try await Task.sleep(for: .milliseconds(50))
            }
        }
    }

    private func finish(_ job: AnalysisJob, as state: AnalysisJob.State, message: String? = nil) async {
        // A cancelled worker still needs to persist its final state.
        await Task { await persistFinish(job, as: state, message: message) }.value
    }

    private func persistFinish(_ job: AnalysisJob, as state: AnalysisJob.State, message: String?) async {
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

    private struct JobError: Error {
        let message: String

        init(_ message: String) {
            self.message = message
        }
    }
}
