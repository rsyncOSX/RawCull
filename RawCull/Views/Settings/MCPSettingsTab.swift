import OSLog
import SwiftUI

struct MCPSettingsTab: View {
    private static let sharingLog = Logger(subsystem: "no.blogspot.RawCull", category: "MCPSettings")

    let selectedCatalogName: String?
    let selectedCatalogURL: URL?
    let canAuthorizeAnalysis: Bool
    let authorizeCatalog: (Bool, Bool) throws -> CatalogGrant


    @State private var allowAnalysis = false
    @State private var recurringFolder = false
    @State private var grant: CatalogGrant?
    @State private var storageError: LocalizedStringResource?
    @State private var grantReadFailed = false
    @State private var sharedResult: SharedResult?
    @State private var resultReadFailed = false
    @State private var assessments: [AnalysisJobStore.FollowUpRecord] = []
    @State private var assessmentError = false
    @State private var followUpsEnabled: Bool?
    @State private var followUpSettingError = false
    @State private var clearError: LocalizedStringResource?

    var body: some View {
        Form {
            Section {
                if let grant {
                    LabeledContent("Authorized catalog", value: grant.displayName)
                    if grant.recurringFolder == true {
                        Text("Automatic analysis is authorized for future photos in this folder.")
                    } else if grant.analysisEnabled == true {
                        Text("Catalog analysis is authorized.")
                    }
                    if grant.analysisEnabled == true, followUpsEnabled == true {
                        Text("Follow-up photo analysis is authorized.")
                    }
                } else if !grantReadFailed {
                    Text("No catalog is authorized.")
                }

                if let selectedCatalogName {
                    LabeledContent("Selected catalog", value: selectedCatalogName)
                    Toggle("Allow MCP burst analysis and photo assessments", isOn: $allowAnalysis)
                    if allowAnalysis {
                        Text("Follow-up analysis uses photo previews locally and shares text findings with the MCP client when supported.")
                            .font(.footnote)
                        Toggle("Allow analysis of future photos in this folder", isOn: $recurringFolder)
                        if recurringFolder {
                            Text("MCP can start analysis without asking again. RawCull rescans this folder for each new job and shares the updated photo list and ranked bursts with the MCP client.")
                                .font(.footnote)
                        }
                    }
                    Button("Authorize Selected Catalog", action: authorize)
                        .disabled(allowAnalysis && !canAuthorizeAnalysis)
                    if allowAnalysis, !canAuthorizeAnalysis {
                        Text("Wait for the catalog to finish loading before authorizing analysis.")
                    }
                } else {
                    Text("Select a catalog in RawCull to authorize it.")
                }

                Button("Revoke Access", role: .destructive) {
                    revoke()
                }
                .buttonStyle(.bordered)
                .disabled(grant == nil && sharedResult == nil && !grantReadFailed)

                if grantReadFailed {
                    Text("The MCP catalog authorization could not be read.")
                        .foregroundStyle(.secondary)
                }

                if let storageError {
                    Text(storageError)
                        .foregroundStyle(.secondary)
                }
            } header: {
                Text("Catalog access")
            } footer: {
                Text("An MCP client can read saved catalog metadata while RawCull is closed. If you allow analysis, it can also open RawCull to scan this catalog and read ranked bursts. Revoking access removes the saved authorization and the current job, including any shared result.")
            }
            SharedResultSection(result: sharedResult, readFailed: resultReadFailed, error: clearError, clear: clearResult)
            MCPPhotoAssessmentSetting(enabled: followUpsEnabled, failed: followUpSettingError,
                                      setEnabled: setFollowUpsEnabled)
            if !assessments.isEmpty || assessmentError {
                Section("Photo assessments") {
                    ForEach(assessments, id: \.request.id) { record in
                        assessmentRow(record)
                    }
                    if assessmentError {
                        Text("RawCull could not update the assessment. Try again.")
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .formStyle(.grouped)
        .onChange(of: selectedCatalogURL) {
            recurringFolder = false
        }
        .task { await observeSharing() }
    }

    private func assessmentRow(_ record: AnalysisJobStore.FollowUpRecord) -> some View {
        HStack {
            VStack(alignment: .leading) {
                if case let .photos(ids) = record.request.target {
                    Text("Photos assessed or requested: \(ids.count)")
                }
                Text(record.createdAt, format: .dateTime.month().day().hour().minute())
                Text(record.request.rubric.map { field in
                    switch field {
                    case "composition": String(localized: "Composition")
                    case "exposure": String(localized: "Exposure")
                    default: String(localized: "Subject visibility")
                    }
                }.formatted(.list(type: .and)))
                Text(assessmentState(record))
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if record.state == .running || record.state == .queued {
                Button("Cancel") { updateAssessment(record.request.id, clear: false) }
                    .disabled(record.cancellationRequested)
            } else if record.state == .completed || record.state == .failed {
                Button("Clear") { updateAssessment(record.request.id, clear: true) }
            }
        }
    }

    private func assessmentState(_ record: AnalysisJobStore.FollowUpRecord) -> LocalizedStringResource {
        if record.cancellationRequested, record.state == .running {
            return "Cancelling"
        }
        switch record.state {
        case .queued: return "Queued"
        case .running: return "Analyzing photo previews"
        case .completed: return "Shared with MCP"
        case .cancelled: return "Cancelled"
        case .interrupted: return "Interrupted"
        case .failed: return "Failed"
        }
    }

    private func updateAssessment(_ id: UUID, clear: Bool) {
        let jobs = AnalysisJobStore(directory: CatalogGrantStore.shared().directory)
        do {
            if clear {
                try jobs.clearFollowUpResult(id)
            } else {
                try jobs.cancelFollowUp(id)
            }
            assessmentError = false
            refreshAssessments(jobs)
        } catch {
            assessmentError = true
        }
    }

    private func refreshAssessments(_ jobs: AnalysisJobStore) {
        if let latest = try? jobs.recentFollowUps(), latest != assessments {
            assessments = latest
        }
    }

    private func setFollowUpsEnabled(_ enabled: Bool) {
        let jobs = AnalysisJobStore(directory: CatalogGrantStore.shared().directory)
        do {
            try jobs.setFollowUpsEnabled(enabled)
            followUpsEnabled = enabled
            followUpSettingError = false
            refreshAssessments(jobs)
        } catch {
            followUpsEnabled = try? jobs.followUpsEnabled()
            followUpSettingError = true
        }
    }

    private func observeSharing() async {
        let grants = CatalogGrantStore.shared()
        let jobs = AnalysisJobStore(directory: grants.directory)
        var grantRevision = grants.revision()
        var jobRevision = jobs.revision()
        refreshGrant()
        refreshResult()
        refreshAssessments(jobs)
        followUpsEnabled = try? jobs.followUpsEnabled()
        followUpSettingError = followUpsEnabled == nil
        while !Task.isCancelled {
            do { try await Task.sleep(for: .seconds(1)) } catch { return }
            let nextGrant = grants.revision()
            let nextJob = jobs.revision()
            let grantChanged = nextGrant != grantRevision || grantReadFailed
            if grantChanged {
                refreshGrant()
            }
            if grantChanged || nextJob != jobRevision || resultReadFailed {
                refreshResult()
            }
            refreshAssessments(jobs)
            grantRevision = nextGrant
            jobRevision = nextJob
        }
    }

    private func refreshGrant() {
        do {
            let current = try CatalogGrantStore.shared().authorizedCatalog()
            if current?.id != grant?.id {
                allowAnalysis = current?.analysisEnabled == true
                recurringFolder = false
            }
            grant = current
            grantReadFailed = false
        } catch {
            grantReadFailed = true
        }
    }

    private func refreshResult() {
        do {
            let jobs = AnalysisJobStore(directory: CatalogGrantStore.shared().directory)
            sharedResult = try jobs.read().flatMap { SharedResult(job: $0, grant: grantReadFailed ? nil : grant) }
            resultReadFailed = false
        } catch {
            sharedResult = nil
            resultReadFailed = true
        }
    }

    private func clearResult(_ id: UUID) {
        do {
            let jobs = AnalysisJobStore(directory: CatalogGrantStore.shared().directory)
            if try jobs.clearResult(expectedJobID: id) {
                MCPJobPhotoAccess.save(nil)
                Self.sharingLog.notice("Cleared the last shared MCP result.")
                clearError = nil
            } else {
                clearError = "The shared result changed. Review the current result before clearing it."
            }
        } catch AnalysisJobStore.StoreError.busy {
            clearError = "MCP job storage is busy. Try clearing the result again."
        } catch {
            clearError = "The shared result could not be cleared."
        }
        refreshGrant()
        refreshResult()
    }

    private func authorize() {
        do {
            grant = try authorizeCatalog(allowAnalysis, allowAnalysis && recurringFolder)
            storageError = nil
            refreshGrant()
            refreshResult()
        } catch AnalysisJobStore.StoreError.busy {
            storageError = "MCP job storage is busy. Try authorizing again."
        } catch {
            storageError = "The selected catalog could not be authorized."
        }
    }

    private func revoke() {
        do {
            try CatalogGrantStore.shared().revoke()
            MCPAnalysisAuthorization.save(nil)
            MCPJobPhotoAccess.save(nil)
            Self.sharingLog.notice("Revoked saved MCP catalog access.")
            allowAnalysis = false
            recurringFolder = false
            grant = nil
            storageError = nil
            refreshGrant()
            refreshResult()
        } catch AnalysisJobStore.StoreError.busy {
            storageError = "MCP job storage is busy. Try revoking access again."
        } catch {
            storageError = "MCP access could not be revoked."
        }
    }
}

private struct MCPPhotoAssessmentSetting: View {
    let enabled: Bool?
    let failed: Bool
    let setEnabled: (Bool) -> Void

    var body: some View {
        Section {
            Toggle("Enable MCP photo assessments", isOn: Binding(get: { enabled == true }, set: setEnabled))
                .disabled(enabled == nil)
            if failed {
                Text("RawCull could not update the photo assessment setting. Try again.")
                    .foregroundStyle(.secondary)
            }
        } footer: {
            Text("Turning this off cancels current assessments and clears their shared findings. Catalog access and burst rankings remain available. Run a new burst analysis after turning assessments back on.")
        }
    }
}

nonisolated struct SharedResult {
    let id: UUID
    let catalogName: String?
    let date: Date

    init?(job: AnalysisJob, grant: CatalogGrant?) {
        let matchingGrant = grant?.id == job.catalogId ? grant : nil
        guard job.hasShareableResult, job.usesSetupApproval || matchingGrant?.analysisEnabled == true else { return nil }
        id = job.jobId
        catalogName = job.catalogDisplayName ?? matchingGrant?.displayName
        date = job.updatedAt
    }
}

private struct SharedResultSection: View {
    let result: SharedResult?
    let readFailed: Bool
    let error: LocalizedStringResource?
    let clear: (UUID) -> Void

    var body: some View {
        Section {
            if let result {
                if let name = result.catalogName {
                    LabeledContent("Catalog", value: name)
                }
                LabeledContent("Completed", value: result.date.formatted(date: .abbreviated, time: .shortened))
                Button("Clear Last Shared Result", role: .destructive) { clear(result.id) }
                    .buttonStyle(.bordered)
            } else if readFailed {
                Text("The last shared result could not be read.")
            } else {
                Text("No burst analysis result is available to MCP clients.")
            }
            if let error {
                Text(error).foregroundStyle(.secondary)
            }
        } header: {
            Text("Last shared result")
        } footer: {
            Text("Clearing removes the shared rankings and coverage and keeps any saved catalog authorization and photo metadata. An MCP client may keep copies it already received.")
        }
    }
}
