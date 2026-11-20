import AppKit
import Foundation
import OSLog
import RawCullCore

/// Catalog setup: answering a setup request from the MCP helper, choosing and
/// approving a folder, and queueing the analysis job.
extension MCPAnalysisController {
    func cancelSetup() {
        guard case var .settingUp(setup) = activity else { return }
        setup.task?.cancel()
        if let sheet = setup.sheet, sheet.parent.sheets.contains(sheet.window) {
            setup.sheet = nil
            activity = .settingUp(setup)
            sheet.parent.endSheet(sheet.window, returnCode: .cancel)
        }
    }

    func setSetupSheet(_ sheet: (parent: NSWindow, window: NSWindow)?) {
        guard case var .settingUp(setup) = activity else { return }
        setup.sheet = sheet
        activity = .settingUp(setup)
    }

    func showSetupSheet(
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

    func respond(
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

    func matchingCatalog(
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

    func readableFolderAccess(_ url: URL, viewModel: any MCPAnalysisWorkspace) -> RawCullCatalogGrant? {
        guard let access = viewModel.retainSecurityScopedAccess(for: url),
              let values = try? url.resourceValues(forKeys: [.isDirectoryKey, .isReadableKey]),
              values.isDirectory == true, values.isReadable == true else { return nil }
        return access
    }

    func chooseFolder(
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

    func queueSetup(
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
    func requireUnchangedGrant(_ expectedID: UUID?) throws {
        guard try grants.authorizedCatalog()?.id == expectedID else {
            throw JobError("The saved catalog authorization changed. Start a new request to review the change.")
        }
    }
}
