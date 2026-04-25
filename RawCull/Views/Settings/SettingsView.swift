//
//  SettingsView.swift
//  RawCull
//
//  Created by Thomas Evensen on 05/02/2026.
//

import SwiftUI

struct SettingsView: View {
    var body: some View {
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
        .padding(20)
        .frame(width: 550, height: 700)
    }
}
