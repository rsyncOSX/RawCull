//
//  SettingsView.swift
//  RawCull
//
//  Created by Thomas Evensen on 05/02/2026.
//

import SwiftUI

struct SettingsView: View {
    @Environment(CatalogWorkspace.self) private var catalog
    @Environment(CatalogController.self) private var catalogController
    let aiSettingsModel: RawCullAISettingsModel
    let combinedReviewFeature: CombinedReviewFeature

    @State private var settingsLoaded = false

    var body: some View {
        @Bindable var settings = SettingsViewModel.shared
        Group {
            if settingsLoaded {
                TabView {
                    Tab("Cache", systemImage: "memorychip.fill") {
                        CacheSettingsTab(aiSettingsModel: aiSettingsModel, combinedReviewFeature: combinedReviewFeature)
                    }

                    Tab("Thumbnails", systemImage: "photo.fill") {
                        ThumbnailSizesTab()
                    }

                    Tab("Focus", systemImage: "viewfinder.circle") {
                        FocusSettingsTab()
                    }

                    Tab("AI", systemImage: "sparkles") {
                        AISettingsTab(model: aiSettingsModel)
                    }

                    Tab("Memory", systemImage: "rectangle.compress.vertical") {
                        MemoryTab()
                    }

                    Tab("MCP", systemImage: "link") {
                        MCPSettingsTab(
                            selectedCatalogName: catalog.selectedSource?.name,
                            selectedCatalogURL: catalog.selectedSource?.url,
                            canAuthorizeAnalysis: !catalog.scanning && !catalog.files.isEmpty,
                            authorizeCatalog: catalogController.authorizeMCPCatalog,
                        )
                    }
                }
            } else {
                ProgressView("Loading Settings...")
                    .controlSize(.small)
            }
        }
        .padding(20)
        .frame(width: 680, height: 760)
        .alert("Settings Storage Error", item: $settings.persistenceFailure) { failure in
            Button("Retry") {
                Task { await settings.retryPersistence(failure.operation) }
            }
            Button("Cancel", role: .cancel) {}
        } message: { failure in
            Text(failure.message)
            if failure.operation == .save {
                Text("Your changes remain in memory and have not been saved to disk.")
            } else {
                Text("Saved settings could not be loaded. Retrying reloads settings from disk and replaces the current values.")
            }
        }
        .task {
            await SettingsViewModel.shared.ensureLoaded()
            settingsLoaded = true
        }
    }
}
