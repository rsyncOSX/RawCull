//
//  SettingsView.swift
//  RawCull
//
//  Created by Thomas Evensen on 05/02/2026.
//

import SwiftUI

struct SettingsView: View {
    @Environment(SettingsViewModel.self) var settingsManager

    @State private var showResetConfirmation = false

    var body: some View {
        TabView {
            CacheSettingsTab()
                .environment(settingsManager)
                .tabItem {
                    Label("Cache", systemImage: "memorychip.fill")
                }

            ThumbnailSizesTab()
                .environment(settingsManager)
                .tabItem {
                    Label("Thumbnails", systemImage: "photo.fill")
                }

            MemoryTab()
                .environment(settingsManager)
                .tabItem {
                    Label("Memory", systemImage: "rectangle.compress.vertical")
                }
        }
        .padding(20)
        .frame(width: 550, height: 540)
    }
}
