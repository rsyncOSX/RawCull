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

    static var savedData: Data? { UserDefaults.standard.data(forKey: preferenceKey) }

    static func save(_ data: Data?) {
        UserDefaults.standard.set(data, forKey: preferenceKey)
    }

    static func fingerprint(for files: [FileItem]) throws -> Data {
        let entries = files.map {
            SnapshotFile(name: $0.url.lastPathComponent, size: $0.size, modified: $0.dateModified)
        }.sorted { $0.name < $1.name }
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        return Data(SHA256.hash(data: try encoder.encode(entries)))
    }

    private struct SnapshotFile: Encodable {
        let name: String
        let size: Int64
        let modified: Date
    }
}

@MainActor
final class MCPAnalysisController {
    private let grants = CatalogGrantStore.shared()
    private lazy var jobs = AnalysisJobStore(directory: grants.directory)
    private var activeJob: AnalysisJob?
    private var analysis: Task<Void, Never>?
    private var monitor: Task<Void, Never>?
    private var isQuitting = false
    private var inactiveRevision: AnalysisJobStore.Revision?

    func start(
        viewModel: RawCullViewModel,
        prepare: @escaping @MainActor () async -> Void,
        canStart: @escaping @MainActor () -> Bool,
    ) {
        guard monitor == nil, grants.directory != nil else { return }
        monitor = Task { [weak self, weak viewModel] in
            while !Task.isCancelled, let self, let viewModel {
                do {
                    try poll(viewModel, prepare: prepare, canStart: canStart)
                } catch AnalysisJobStore.StoreError.unsupportedFormat {
                    Logger.process.error("MCP analysis job uses an unsupported format. Reauthorize the catalog to clear it.")
                    analysis?.cancel()
                } catch AnalysisJobStore.StoreError.busy {
                    // The next poll retries a claim or heartbeat.
                } catch {
                    Logger.process.error("Could not update the MCP analysis job.")
                    analysis?.cancel()
                }
                try? await Task.sleep(for: .seconds(1))
            }
        }
    }

    func stopForQuit() async {
        isQuitting = true
        monitor?.cancel()
        monitor = nil
        analysis?.cancel()
        if let job = activeJob { await finish(job, as: .cancelled, message: "RawCull quit.") }
    }

    private func poll(
        _ viewModel: RawCullViewModel,
        prepare: @escaping @MainActor () async -> Void,
        canStart: @escaping @MainActor () -> Bool,
    ) throws {
        let revision = jobs.revision()
        if let revision, revision == inactiveRevision { return }
        inactiveRevision = nil
        let storedJob: AnalysisJob?
        do {
            storedJob = try jobs.readRecovering()
        } catch AnalysisJobStore.StoreError.unsupportedFormat {
            inactiveRevision = revision
            throw AnalysisJobStore.StoreError.unsupportedFormat
        }
        guard let job = storedJob else {
            analysis?.cancel()
            return
        }
        if analysis != nil {
            guard job.jobId == activeJob?.jobId, job.catalogId == activeJob?.catalogId,
                  job.state == .running, !job.cancellationRequested, try isAuthorized(job)
            else {
                analysis?.cancel()
                return
            }
            try updateProgress(job, viewModel: viewModel)
            return
        }
        guard job.state.isActive else {
            inactiveRevision = revision
            return
        }
        if job.isExpired(at: .now) {
            _ = try jobs.expireInterruptedJob()
            return
        }
        guard job.state == .queued else { return }

        var didClaim = false
        let claimed = try jobs.update { current in
            guard var current, current.jobId == job.jobId, current.catalogId == job.catalogId,
                  current.state == .queued, !current.isExpired(at: .now) else { return nil }
            current.state = .running
            current.recordHeartbeat()
            current.stage = "openingCatalog"
            current.message = nil
            didClaim = true
            return current
        }
        guard didClaim, let claimed else { return }

        activeJob = claimed
        analysis = Task { [weak self, weak viewModel] in
            guard let self else { return }
            let activity = ProcessInfo.processInfo.beginActivity(
                options: .userInitiatedAllowingIdleSystemSleep, reason: "RawCull MCP catalog analysis"
            )
            defer {
                ProcessInfo.processInfo.endActivity(activity)
                activeJob = nil
                analysis = nil
            }
            guard let viewModel else {
                if !isQuitting { await finish(claimed, as: .cancelled) }
                return
            }
            do {
                try await run(claimed, viewModel: viewModel, prepare: prepare, canStart: canStart)
            } catch is CancellationError {
                if !isQuitting { await finish(claimed, as: .cancelled) }
            } catch let error as JobError {
                if !isQuitting { await finish(claimed, as: .failed, message: error.message) }
            } catch {
                if !isQuitting {
                    await finish(
                        claimed, as: .failed,
                        message: "RawCull could not open or analyze the authorized catalog. Check access and authorize it again."
                    )
                }
            }
        }
    }

    private func run(
        _ job: AnalysisJob,
        viewModel: RawCullViewModel,
        prepare: @MainActor () async -> Void,
        canStart: @MainActor () -> Bool,
    ) async throws {
        guard let grant = try grants.authorizedCatalog(), grant.id == job.catalogId,
              grant.analysisEnabled == true, let photos = grant.summary?.photos,
              let data = MCPAnalysisAuthorization.savedData,
              let authorization = try? JSONDecoder().decode(MCPAnalysisAuthorization.self, from: data),
              authorization.catalogId == grant.id
        else { throw JobError("Authorize the loaded catalog for analysis in RawCull's MCP settings.") }

        var stale = false
        let url = try URL(
            resolvingBookmarkData: authorization.bookmark,
            options: [.withSecurityScope, .withoutUI, .withoutMounting],
            relativeTo: nil,
            bookmarkDataIsStale: &stale
        )
        guard !stale else { throw JobError("The authorized catalog moved or its bookmark expired. Authorize it again.") }
        try requireAvailableWorkspace(for: url, viewModel: viewModel, canStart: canStart)
        await prepare()
        try checkCurrent(job)
        try requireAvailableWorkspace(for: url, viewModel: viewModel, canStart: canStart)

        let index = viewModel.sources.firstIndex { $0.url.standardizedFileURL == url.standardizedFileURL }
        let target = viewModel.selectedSource
            ?? index.map { viewModel.sources[$0] }
            ?? ARWSourceCatalog(name: grant.displayName, url: url)
        if index == nil {
            viewModel.sources.append(target)
        }
        if viewModel.selectedSource != target { viewModel.selectedSource = target }
        if viewModel.catalogLifecycle.currentSource != target || viewModel.files.isEmpty
            || !viewModel.hasActiveSecurityScopedAccess(for: url) {
            viewModel.startCatalogLoad(for: target, scopedURL: url)
            try await waitForCatalog(job, target: target, viewModel: viewModel)
        }
        let photoIds = try snapshotPhotoIds(
            files: viewModel.files, photos: photos, authorization: authorization
        )
        try checkCurrent(job)
        if viewModel.similarityModel.semanticSearchState != .idle {
            await viewModel.semanticSearchFeature.clear()
            try checkCurrent(job)
        }
        guard viewModel.selectedSource == target, viewModel.catalogLifecycle.currentSource == target,
              viewModel.hasActiveSecurityScopedAccess(for: url), canStart(),
              !viewModel.isDeepAIReviewBlockedByOtherWork, !viewModel.isPreparingBurstCatalog
        else { throw JobError("The catalog changed or another operation started. Start a new job.") }

        let orderedFiles = viewModel.fullCatalogBurstAnalysisFiles
        let generation = viewModel.burstAnalysisGeneration &+ 1
        let similaritySignature = viewModel.currentBurstSimilaritySignature
        let sharpnessSignature = viewModel.sharpnessModel.scoringSignature
        let result = await viewModel.startBurstAnalysis(catalog: target.url, files: orderedFiles)
        try checkCurrent(job)
        guard viewModel.selectedSource == target, viewModel.burstAnalysisGeneration == generation,
              viewModel.currentBurstSimilaritySignature == similaritySignature,
              viewModel.sharpnessModel.scoringSignature == sharpnessSignature,
              let result else { throw JobError("The catalog or analysis settings changed during the job.") }
        guard !result.diagnostics.contains(.cacheSaveFailed) else {
            throw JobError("RawCull could not save the ranked bursts to its analysis cache.")
        }

        let output = makeResults(result, job: job, photoIds: photoIds, viewModel: viewModel)
        try await updateWithRetry { current in
            try Task.checkCancellation()
            guard var current, current.jobId == job.jobId, current.catalogId == job.catalogId,
                  current.state == .running else { throw CancellationError() }
            guard !current.cancellationRequested, try isAuthorized(job) else { throw CancellationError() }
            current.coverage = output.coverage
            current.bursts = output.bursts
            current.filesScanned = photoIds.count
            current.filesAnalyzed = photoIds.count - output.coverage.unevaluatedCount
            current.finish(.completed)
            return current
        }
        viewModel.showsDetailedBurstComparison = false
        viewModel.useExistingBurstGroupIndex()
    }

    private func requireAvailableWorkspace(
        for url: URL, viewModel: RawCullViewModel, canStart: @MainActor () -> Bool
    ) throws {
        guard canStart(), !viewModel.cullingModel.isTerminationPending,
              !viewModel.isDeepAIReviewBlockedByOtherWork, !viewModel.isPreparingBurstCatalog,
              !viewModel.sharpnessModel.isCalibratingSharpnessScoring,
              !viewModel.scanning, !viewModel.isCreatingThumbnails,
              viewModel.catalogLifecycle.transitionTask == nil, viewModel.catalogLifecycle.loadTask == nil
        else { throw JobError("RawCull is busy. Let the current operation finish, then start a new job.") }

        let requested = url.standardizedFileURL
        let selected = viewModel.selectedSource?.url.standardizedFileURL
        let loaded = viewModel.catalogLifecycle.currentSource?.url.standardizedFileURL
        guard (selected == nil || selected == requested), (loaded == nil || loaded == requested) else {
            throw JobError("RawCull has another catalog open. Select the authorized catalog in RawCull, then start a new job.")
        }
    }

    private func waitForCatalog(
        _ job: AnalysisJob, target: ARWSourceCatalog, viewModel: RawCullViewModel
    ) async throws {
        do {
            try await waitForCatalogLoad(job, target: target, viewModel: viewModel)
        } catch is CancellationError {
            if viewModel.selectedSource == target { viewModel.cancelCatalogLoad() }
            throw CancellationError()
        }
    }

    private func waitForCatalogLoad(
        _ job: AnalysisJob, target: ARWSourceCatalog, viewModel: RawCullViewModel
    ) async throws {
        while viewModel.catalogLifecycle.transitionTask != nil || viewModel.catalogLifecycle.loadTask != nil {
            try checkCurrent(job)
            guard viewModel.selectedSource == target else { throw CancellationError() }
            try await Task.sleep(for: .milliseconds(250))
        }
        try checkCurrent(job)
        guard viewModel.selectedSource == target, viewModel.catalogLifecycle.currentSource == target,
              !viewModel.scanning, viewModel.hasActiveSecurityScopedAccess(for: target.url),
              !viewModel.files.isEmpty
        else { throw JobError("RawCull could not load the authorized catalog. Check that the source is connected and authorize it again.") }
    }

    private func snapshotPhotoIds(
        files: [FileItem], photos: [CatalogPhoto], authorization: MCPAnalysisAuthorization
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

    private func makeResults(
        _ result: BurstAnalysisPipelineResult, job: AnalysisJob,
        photoIds: [UUID: String], viewModel: RawCullViewModel
    ) -> (coverage: AnalysisJob.Coverage, bursts: [AnalysisJob.Burst]) {
        let names = Dictionary(uniqueKeysWithValues: viewModel.files.map { ($0.id, $0.url.lastPathComponent) })
        let scores = viewModel.sharpnessModel.scores
        let embeddings = viewModel.similarityModel.embeddings
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
                id: "\(job.catalogId.uuidString):\(job.jobId.uuidString):\(ranking.groupID)",
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
                        reasons: candidate.reasons, cautions: candidate.cautions
                    )
                }
            )
        }
        let singletons = result.groups.reduce(into: 0) { count, group in
            if group.fileIDs.count == 1 || group.id == -1 { count += group.fileIDs.count }
        }
        let coverage = AnalysisJob.Coverage(
            photoCount: photoIds.count, burstCount: bursts.count, singletonCount: singletons,
            unevaluatedCount: skipped.values.reduce(0, +), skippedByReason: skipped,
            similarityBackends: backendCounts
        )
        return (coverage, bursts)
    }

    private func isAuthorized(_ job: AnalysisJob) throws -> Bool {
        let grant = try grants.authorizedCatalog()
        return grant?.id == job.catalogId && grant?.analysisEnabled == true
    }

    private func checkCurrent(_ job: AnalysisJob) throws {
        try Task.checkCancellation()
        guard let current = try jobs.read(), current.jobId == job.jobId, current.catalogId == job.catalogId,
              current.state == .running, !current.cancellationRequested, try isAuthorized(job)
        else { throw CancellationError() }
    }

    private func updateProgress(_ job: AnalysisJob, viewModel: RawCullViewModel) throws {
        let progress = viewModel.burstAnalysisProgress
        let scanned = viewModel.scanDiscoveredCount
        try jobs.update { current in
            guard var current, current.jobId == job.jobId, current.catalogId == job.catalogId,
                  current.state == .running, !current.cancellationRequested else { return nil }
            current.stage = progress.isRunning ? progress.step.rawValue : "openingCatalog"
            current.recordHeartbeat()
            current.filesScanned = current.stage == "openingCatalog" ? scanned : viewModel.files.count
            if progress.step == .grouping || progress.step == .ranking || progress.step == .savingCache {
                current.filesAnalyzed = viewModel.similarityModel.embeddings.keys.lazy
                    .filter { viewModel.sharpnessModel.scores[$0] != nil }.count
            }
            current.stageTotal = progress.isCountBased ? progress.total : nil
            current.stageCompleted = switch progress.step {
            case .scoringSharpness: viewModel.sharpnessModel.scoringProgress
            case .indexingSimilarity: viewModel.similarityModel.indexingProgress
            default: nil
            }
            return current
        }
    }

    private func updateWithRetry(
        _ change: (AnalysisJob?) throws -> AnalysisJob?
    ) async throws {
        let deadline = ContinuousClock.now + .seconds(2)
        while true {
            do {
                try jobs.update(change)
                return
            } catch AnalysisJobStore.StoreError.busy where ContinuousClock.now < deadline {
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
                } else if current.cancellationRequested && state != .cancelled {
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
