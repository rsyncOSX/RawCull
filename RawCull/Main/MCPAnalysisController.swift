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
    private var setup: Task<Void, Never>?
    private var approvedSetup: (id: UUID, url: URL, access: RawCullCatalogGrant, remember: Bool)?
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
                    if setup == nil, analysis == nil, let request = try setupStore.pending() {
                        setup = Task { [weak self, weak viewModel] in
                            guard let self else { return }
                            defer { setup = nil }
                            guard let viewModel else { return }
                            await respond(to: request, viewModel: viewModel, canStart: canStart)
                        }
                    }
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
        setup?.cancel()
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
            approvedSetup = nil
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
            if approvedSetup?.id == job.jobId { approvedSetup = nil }
            inactiveRevision = revision
            return
        }
        if job.isExpired(at: .now) {
            _ = try jobs.expireInterruptedJob()
            return
        }
        guard job.state == .queued, setup == nil else { return }

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

    private var setupStore: CatalogSetupStore { CatalogSetupStore(jobs: jobs) }

    private func respond(
        to request: CatalogSetupRequest, viewModel: RawCullViewModel, canStart: @MainActor () -> Bool
    ) async {
        var response = request
        do {
            guard !request.isExpired else { throw JobError("The catalog setup request expired. Start a new request.") }
            let saved = try savedCatalog()
            let match = matchingCatalog(for: request.catalogHint, viewModel: viewModel, saved: saved)
            if let saved, let match, sameFolder(match, saved.url), readableFolderAccess(saved.url, viewModel: viewModel) != nil {
                try await queueSetup(
                    request, url: saved.url, remember: false, savedGrantId: saved.grant.id,
                    viewModel: viewModel, canStart: canStart
                )
                return
            }

            guard let window = NSApp.keyWindow ?? NSApp.mainWindow ?? NSApp.windows.first(where: \.isVisible) else {
                throw JobError("Open RawCull's main window and start a new request.")
            }

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
            confirmation.messageText = String(localized: "Approve burst analysis?")
            confirmation.informativeText = String(localized: "RawCull will analyze \(url.path(percentEncoded: false)) and share its ranked bursts with the MCP client.")
            confirmation.addButton(withTitle: String(localized: "Approve This Job"))
            confirmation.addButton(withTitle: String(localized: "Approve and Remember"))
            confirmation.addButton(withTitle: String(localized: "Deny")).keyEquivalent = "\u{1b}"
            let approval = await confirmation.beginSheetModal(for: window)
            guard approval == .alertFirstButtonReturn || approval == .alertSecondButtonReturn else {
                throw CancellationError()
            }
            try Task.checkCancellation()
            try await queueSetup(
                request, url: url, remember: approval == .alertSecondButtonReturn, access: access,
                viewModel: viewModel, canStart: canStart
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
        do {
            try await withJobLockRetry {
                guard try setupStore.pending()?.requestId == request.requestId else { return }
                try setupStore.saveLocked(response)
            }
        } catch {
            Logger.process.error("Could not save the MCP catalog setup response.")
        }
    }

    private func savedCatalog() throws -> (grant: CatalogGrant, url: URL)? {
        guard let grant = try grants.authorizedCatalog(), grant.analysisEnabled == true,
              grant.summary?.photos != nil, let data = MCPAnalysisAuthorization.savedData,
              let authorization = try? JSONDecoder().decode(MCPAnalysisAuthorization.self, from: data),
              authorization.catalogId == grant.id else { return nil }

        var stale = false
        guard let url = try? URL(
            resolvingBookmarkData: authorization.bookmark,
            options: [.withSecurityScope, .withoutUI, .withoutMounting],
            relativeTo: nil, bookmarkDataIsStale: &stale
        ), !stale else { return nil }
        return (grant, url)
    }

    private func sameFolder(_ lhs: URL, _ rhs: URL) -> Bool {
        lhs.standardizedFileURL.path == rhs.standardizedFileURL.path
    }

    private func matchingCatalog(
        for hint: String, viewModel: RawCullViewModel, saved: (grant: CatalogGrant, url: URL)?
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
            if let match, !sameFolder(match, candidate.url) { return nil }
            match = candidate.url
        }
        return match
    }

    private func readableFolderAccess(_ url: URL, viewModel: RawCullViewModel) -> RawCullCatalogGrant? {
        guard let access = viewModel.catalogLifecycle.retainSecurityScopedAccess(for: url),
              let values = try? url.resourceValues(forKeys: [.isDirectoryKey, .isReadableKey]),
              values.isDirectory == true, values.isReadable == true else { return nil }
        return access
    }

    private func chooseFolder(
        for request: CatalogSetupRequest, viewModel: RawCullViewModel, window: NSWindow
    ) async throws -> URL {
        let chooser = NSAlert()
        chooser.messageText = String(localized: "Choose a catalog for burst analysis")
        chooser.informativeText = request.catalogHint
        chooser.addButton(withTitle: String(localized: "Choose Folder…"))
        let current = viewModel.selectedSource
        if current != nil {
            chooser.addButton(withTitle: String(localized: "Use Current Catalog"))
        }
        chooser.addButton(withTitle: String(localized: "Deny")).keyEquivalent = "\u{1b}"
        let choice = await chooser.beginSheetModal(for: window)
        if choice == .alertFirstButtonReturn {
            let picker = NSOpenPanel()
            picker.canChooseDirectories = true
            picker.canChooseFiles = false
            picker.allowsMultipleSelection = false
            let hint = request.catalogHint.trimmingCharacters(in: .whitespacesAndNewlines)
            if hint.hasPrefix("/") {
                picker.directoryURL = URL(fileURLWithPath: hint, isDirectory: true).deletingLastPathComponent()
            } else if let current {
                picker.directoryURL = current.url.deletingLastPathComponent()
            }
            guard await picker.beginSheetModal(for: window) == .OK, let picked = picker.url else {
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
        viewModel: RawCullViewModel, canStart: @MainActor () -> Bool
    ) async throws {
        try await waitForWorkspaceLoad(viewModel: viewModel) {
            try Task.checkCancellation()
            guard !request.isExpired, try setupStore.pending()?.requestId == request.requestId else {
                throw JobError("The catalog setup request expired. Start a new request.")
            }
        }
        try requireAvailableWorkspace(for: url, viewModel: viewModel, canStart: canStart, allowSwitch: true)
        try await withJobLockRetry {
            try Task.checkCancellation()
            guard !request.isExpired, try setupStore.pending()?.requestId == request.requestId else {
                throw JobError("The catalog setup request expired. Start a new request.")
            }
            let now = Date.now
            if let savedGrantId {
                guard let grant = try grants.authorizedCatalog(), grant.id == savedGrantId,
                      grant.analysisEnabled == true else {
                    throw JobError("Catalog authorization changed. Start a new request.")
                }
            }
            var job = AnalysisJob(jobId: UUID(), catalogId: savedGrantId ?? UUID(), createdAt: now, updatedAt: now)
            if savedGrantId != nil { job.usesSavedGrant = true }
            job.setupRequestId = request.requestId
            try jobs.updateLocked { current in
                guard current?.state.isActive != true else {
                    throw JobError("An analysis is already active. Wait for it to finish and try again.")
                }
                return job
            }
            if let access { approvedSetup = (job.jobId, url, access, remember) }
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

    private func run(
        _ job: AnalysisJob,
        viewModel: RawCullViewModel,
        prepare: @MainActor () async -> Void,
        canStart: @MainActor () -> Bool,
    ) async throws {
        let url: URL
        let name: String
        let grant: CatalogGrant?
        let authorization: MCPAnalysisAuthorization?
        let setupApproval = approvedSetup.flatMap { $0.id == job.jobId ? $0 : nil }
        defer {
            if approvedSetup?.id == job.jobId { approvedSetup = nil }
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
                  let data = MCPAnalysisAuthorization.savedData,
                  let savedAuthorization = try? JSONDecoder().decode(MCPAnalysisAuthorization.self, from: data),
                  savedAuthorization.catalogId == savedGrant.id
            else { throw JobError("Authorize the loaded catalog for analysis in RawCull's MCP settings.") }

            var stale = false
            url = try URL(
                resolvingBookmarkData: savedAuthorization.bookmark,
                options: [.withSecurityScope, .withoutUI, .withoutMounting],
                relativeTo: nil, bookmarkDataIsStale: &stale
            )
            guard !stale else { throw JobError("The authorized catalog moved or its bookmark expired. Authorize it again.") }
            name = savedGrant.displayName
            grant = savedGrant
            authorization = savedAuthorization
        }
        try await waitForWorkspaceLoad(viewModel: viewModel) { try checkCurrent(job) }
        try requireAvailableWorkspace(for: url, viewModel: viewModel, canStart: canStart, allowSwitch: job.setupRequestId != nil)
        await prepare()
        try await waitForWorkspaceLoad(viewModel: viewModel) { try checkCurrent(job) }
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
            || viewModel.catalogLifecycle.currentSource != target || viewModel.files.isEmpty
            || !viewModel.hasActiveSecurityScopedAccess(for: url)
        if viewModel.selectedSource != target { viewModel.selectedSource = target }
        if needsCatalogLoad {
            viewModel.startCatalogLoad(for: target, scopedURL: url, retainedAccess: setupApproval?.access)
            try await waitForCatalog(job, target: target, viewModel: viewModel)
        }
        let photoIds: [UUID: String]
        let refreshedGrant: CatalogGrant?
        if let grant, grant.recurringFolder == true {
            guard let summary = viewModel.mcpCatalogSummary(scanId: job.jobId) else {
                throw JobError("No supported photos were found in the authorized folder.")
            }
            let prefix = summary.photoIdPrefix(catalogId: grant.id)
            photoIds = Dictionary(uniqueKeysWithValues: viewModel.files.enumerated().map { offset, file in
                (file.id, "\(prefix)\(offset)")
            })
            refreshedGrant = CatalogGrant(
                id: grant.id, displayName: grant.displayName, summary: summary,
                analysisEnabled: true, recurringFolder: true
            )
        } else if let photos = grant?.summary?.photos, let authorization {
            refreshedGrant = nil
            photoIds = try snapshotPhotoIds(files: viewModel.files, photos: photos, authorization: authorization)
        } else {
            refreshedGrant = nil
            photoIds = Dictionary(uniqueKeysWithValues: viewModel.files.enumerated().map { offset, file in
                (file.id, "\(job.catalogId.uuidString):\(offset)")
            })
            if setupApproval?.remember == true {
                try await withJobLockRetry {
                    try checkCurrent(job)
                    try viewModel.authorizeMCPCatalog(allowAnalysis: true, catalogId: job.catalogId, preservingJob: true)
                }
            }
        }
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
            if let refreshedGrant { try grants.writeLocked(refreshedGrant) }
            current.coverage = output.coverage
            current.bursts = output.bursts
            current.filesScanned = photoIds.count
            current.filesAnalyzed = photoIds.count - output.coverage.unevaluatedCount
            current.finish(.completed)
            return current
        }
        if needsCatalogLoad, grant?.recurringFolder != true || selection == nil {
            viewModel.showsDetailedBurstComparison = false
            viewModel.useExistingBurstGroupIndex()
        }
    }

    private func isWorkspaceLoading(_ viewModel: RawCullViewModel) -> Bool {
        viewModel.catalogLifecycle.transitionTask != nil || viewModel.catalogLifecycle.loadTask != nil
            || viewModel.scanning || viewModel.isCreatingThumbnails
    }

    private func waitForWorkspaceLoad(
        viewModel: RawCullViewModel, checkRequest: () throws -> Void
    ) async throws {
        let clock = SuspendingClock()
        let deadline = clock.now.advanced(by: .seconds(120))
        while isWorkspaceLoading(viewModel) {
            try checkRequest()
            guard clock.now < deadline else {
                throw JobError("RawCull is still loading a catalog after two minutes. Wait for the catalog and thumbnails to finish loading, then start a new request.")
            }
            try await Task.sleep(for: .milliseconds(250))
        }
        try checkRequest()
    }

    private func requireAvailableWorkspace(
        for url: URL, viewModel: RawCullViewModel, canStart: @MainActor () -> Bool, allowSwitch: Bool = false
    ) throws {
        if viewModel.cullingModel.isTerminationPending {
            throw JobError("RawCull is waiting to quit. Resolve any save prompt in RawCull, then start a new request.")
        }
        if isWorkspaceLoading(viewModel) {
            throw JobError("RawCull is loading a catalog. Wait for the catalog and thumbnails to finish loading, then start a new request.")
        }
        if !canStart() || viewModel.isDeepAIReviewBlockedByOtherWork || viewModel.isPreparingBurstCatalog
            || viewModel.sharpnessModel.isCalibratingSharpnessScoring
        {
            throw JobError("RawCull is running analysis or preparing burst results. Wait for that operation to finish, then start a new request.")
        }

        let selectedMatches = viewModel.selectedSource.map { sameFolder($0.url, url) } ?? true
        let loadedMatches = viewModel.catalogLifecycle.currentSource.map { sameFolder($0.url, url) } ?? true
        guard allowSwitch || (selectedMatches && loadedMatches) else {
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
        guard viewModel.cullingModel.persistenceError == nil else {
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
        guard viewModel.catalogLifecycle.currentSource == target, !viewModel.scanning,
              viewModel.hasActiveSecurityScopedAccess(for: target.url), !viewModel.files.isEmpty
        else { throw JobError("RawCull did not finish loading the selected catalog. Open it in RawCull and try again.") }
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
        if job.usesSetupApproval { return approvedSetup?.id == job.jobId }
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
        try await withJobLockRetry { try jobs.updateLocked(change) }
    }

    private func withJobLockRetry(_ operation: () throws -> Void) async throws {
        let deadline = ContinuousClock.now + .seconds(2)
        while true {
            do {
                try jobs.withLock(operation)
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
