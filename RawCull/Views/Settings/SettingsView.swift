//
//  SettingsView.swift
//  RawCull
//
//  Created by Thomas Evensen on 05/02/2026.
//

import SwiftUI

struct SettingsView: View {
    @State private var settingsLoaded = false

    var body: some View {
        Group {
            if settingsLoaded {
                TabView {
                    CacheSettingsTab()
                        .tabItem {
                            Label("Cache", systemImage: "memorychip.fill")
                        }

                    ThumbnailSizesTab()
                        .tabItem {
                            Label("Thumbnails", systemImage: "photo.fill")
                        }

                    FocusSettingsTab()
                        .tabItem {
                            Label("Focus", systemImage: "viewfinder.circle")
                        }

                    MemoryTab()
                        .tabItem {
                            Label("Memory", systemImage: "rectangle.compress.vertical")
                        }
                }
            } else {
                ProgressView("Loading Settings...")
                    .controlSize(.small)
            }
        }
        .padding(20)
        .frame(width: 520, height: 600)
        .task {
            await SettingsViewModel.shared.ensureLoaded()
            settingsLoaded = true
        }
    }
}
