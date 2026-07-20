//
//  SettingsView.swift
//  RawCull
//
//  Created by Thomas Evensen on 05/02/2026.
//

import SwiftUI

struct SettingsView: View {
    let aiSettingsModel: RawCullAISettingsModel

    @State private var settingsLoaded = false

    var body: some View {
        Group {
            if settingsLoaded {
                TabView {
                    Tab("Cache", systemImage: "memorychip.fill") {
                        CacheSettingsTab()
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
                }
            } else {
                ProgressView("Loading Settings...")
                    .controlSize(.small)
            }
        }
        .padding(20)
        .frame(width: 680, height: 700)
        .task {
            await SettingsViewModel.shared.ensureLoaded()
            settingsLoaded = true
        }
    }
}
