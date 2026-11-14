import SwiftUI

struct MCPSettingsTab: View {
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
                } else if !grantReadFailed {
                    Text("No catalog is authorized.")
                }

                if let selectedCatalogName {
                    LabeledContent("Selected catalog", value: selectedCatalogName)
                    Toggle("Allow MCP to start burst analysis", isOn: $allowAnalysis)
                    if allowAnalysis {
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

                Button("Revoke Access") {
                    revoke()
                }
                .disabled(grant == nil && !grantReadFailed)

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
        }
        .formStyle(.grouped)
        .onChange(of: selectedCatalogURL) {
            recurringFolder = false
        }
        .task { await observeSharing() }
    }

    private func observeSharing() async {
        let grants = CatalogGrantStore.shared()
        let jobs = AnalysisJobStore(directory: grants.directory)
        var grantRevision = grants.revision()
        var jobRevision = jobs.revision()
        refreshGrant()
        refreshResult()
        while !Task.isCancelled {
            do { try await Task.sleep(for: .seconds(1)) } catch { return }
            let nextGrant = grants.revision()
            let nextJob = jobs.revision()
            let grantChanged = nextGrant != grantRevision || grantReadFailed
            if grantChanged { refreshGrant() }
            if grantChanged || nextJob != jobRevision || resultReadFailed { refreshResult() }
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
            if let job = try jobs.read(), job.hasShareableResult,
               job.usesSetupApproval || (grant?.id == job.catalogId && grant?.analysisEnabled == true && !grantReadFailed) {
                let name = job.catalogDisplayName ?? (grant?.id == job.catalogId ? grant?.displayName : nil)
                sharedResult = SharedResult(id: job.jobId, catalogName: name, date: job.updatedAt)
            } else {
                sharedResult = nil
            }
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

private struct SharedResult {
    let id: UUID
    let catalogName: String?
    let date: Date
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
            Text("Clearing stops future reads of this result. An MCP client may keep copies it already received.")
        }
    }
}
