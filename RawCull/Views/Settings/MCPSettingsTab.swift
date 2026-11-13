import SwiftUI

struct MCPSettingsTab: View {
    let selectedCatalogName: String?
    let canAuthorizeAnalysis: Bool
    let authorizeCatalog: (Bool) throws -> CatalogGrant

    @State private var allowAnalysis = false
    @State private var grant: CatalogGrant?
    @State private var storageError: LocalizedStringResource?

    var body: some View {
        Form {
            Section {
                if let grant {
                    LabeledContent("Authorized catalog", value: grant.displayName)
                    if grant.analysisEnabled == true {
                        Text("Catalog analysis is authorized.")
                    }
                } else if storageError == nil {
                    Text("No catalog is authorized.")
                }

                if let selectedCatalogName {
                    LabeledContent("Selected catalog", value: selectedCatalogName)
                    Toggle("Allow MCP to start burst analysis", isOn: $allowAnalysis)
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
                .disabled(grant == nil && storageError == nil)

                if let storageError {
                    Text(storageError)
                        .foregroundStyle(.secondary)
                }
            } header: {
                Text("Catalog access")
            } footer: {
                Text("An MCP client can read saved catalog metadata while RawCull is closed. If you allow analysis, it can also open RawCull to scan this catalog and read ranked bursts. Authorizing again replaces the saved snapshot.")
            }
        }
        .formStyle(.grouped)
        .task {
            do {
                grant = try CatalogGrantStore.shared().authorizedCatalog()
                allowAnalysis = grant?.analysisEnabled == true
                storageError = nil
            } catch {
                storageError = "The MCP catalog authorization could not be read."
            }
        }
    }

    private func authorize() {
        do {
            grant = try authorizeCatalog(allowAnalysis)
            storageError = nil
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
            grant = nil
            storageError = nil
        } catch AnalysisJobStore.StoreError.busy {
            storageError = "MCP job storage is busy. Try revoking access again."
        } catch {
            storageError = "MCP access could not be revoked."
        }
    }
}
