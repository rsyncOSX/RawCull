import AppKit
import CoreGraphics
import Foundation
import OSLog
import RawCullCore

/// Photo-assessment follow-ups: admitting a queued assessment, running Qwen
/// on its photos and publishing the result or stop reason.
extension MCPAnalysisController {
    /// The follow-up source or the follow-up feature went away; the running
    /// assessment should stop. Kept as one `switch` rather than a multi-pattern
    /// `catch`, which the tree-sitter Swift grammar used by code tools cannot parse.
    static func isFollowUpUnavailable(_ error: any Error) -> Bool {
        switch error {
        case FollowUpSourceSnapshot.SourceError.unavailable,
             AnalysisJobStore.FollowUpError.unavailable,
             AnalysisJobStore.FollowUpError.disabled:
            true
        default:
            false
        }
    }

    func pollFollowUp(
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
                cancelFollowUp(reason: .executionTimeout)
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
            try jobs.finishFollowUp(worker, result: nil, errorCode: MCPAssessmentStopReason.busy.rawValue)
            return
        }
        let token = begin {
            .assessing(FollowUpActivity(token: $0, id: id, deadline: environment.instant().advanced(by: .seconds(180))))
        }
        lease.invalidateOwner = { [weak self] in
            self?.cancelFollowUp(reason: .modelChanged)
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
                                            errorCode: output.assessedCount == 0
                                                ? MCPAssessmentStopReason.allPhotosFailed.rawValue : nil)
                }
            } catch {
                let code = Self.stopReason(for: error, recorded: followUpStopReason(token))?.rawValue
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

    /// Maps how a follow-up ended to the code published to the helper. A reason
    /// the controller recorded (timeout, lease invalidation) wins; a plain
    /// cancellation publishes no code.
    static func stopReason(for error: any Error, recorded: MCPAssessmentStopReason?) -> MCPAssessmentStopReason? {
        if let recorded {
            return recorded
        }
        if error is CancellationError {
            return nil
        }
        if error is QwenInferenceRuntime.MCPAssessmentError {
            return .modelChanged
        }
        if case QwenModelError.modelUnavailable = error {
            return .modelUnavailable
        }
        if error is FollowUpCatalogError {
            return .reauthorizationRequired
        }
        return .assessmentFailed
    }

    func assessFollowUp(
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
}
