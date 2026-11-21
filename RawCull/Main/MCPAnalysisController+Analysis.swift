import AppKit
import Foundation
import OSLog
import RawCullCore

/// Catalog analysis: claiming a queued job, running burst analysis in the
/// workspace and publishing the ranked bursts.
extension MCPAnalysisController {
    func poll(
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

    func run(
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

    func waitForCatalog(
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

    func waitForCatalogLoad(
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

    func snapshotPhotoIds(
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

    func makeFollowUpSource(
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

    func sharedBurstID(job: AnalysisJob, groupID: Int) -> String {
        "\(job.catalogId.uuidString):\(job.jobId.uuidString):\(groupID)"
    }

    func makeResults(
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

    func updateProgress(_ job: AnalysisJob, viewModel: any MCPAnalysisWorkspace) throws {
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
}
