import SwiftUI

struct MCPSettingsTab: View {
    let selectedCatalogName: String?

    @State private var grant: CatalogGrant?
    @State private var storageError: LocalizedStringResource?

    var body: some View {
        Form {
            Section {
                if let grant {
                    LabeledContent("Authorized catalog", value: grant.displayName)
                } else if storageError == nil {
                    Text("No catalog is authorized.")
                }

                if let selectedCatalogName {
                    LabeledContent("Selected catalog", value: selectedCatalogName)
                    Button("Authorize Selected Catalog") {
                        authorize(selectedCatalogName)
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
                Text("An MCP client can list the authorized catalog’s name and ID while RawCull is closed. Authorizing a catalog replaces the previous authorization.")
            }
        }
        .formStyle(.grouped)
        .task {
            do {
                grant = try CatalogGrantStore.shared().authorizedCatalog()
                storageError = nil
            } catch {
                storageError = "The MCP catalog authorization could not be read."
            }
        }
    }

    private func authorize(_ name: String) {
        do {
            grant = try CatalogGrantStore.shared().authorize(displayName: name)
            storageError = nil
        } catch {
            storageError = "The selected catalog could not be authorized."
        }
    }

    private func revoke() {
        do {
            try CatalogGrantStore.shared().revoke()
            grant = nil
            storageError = nil
        } catch {
            storageError = "MCP access could not be revoked."
        }
    }
}
