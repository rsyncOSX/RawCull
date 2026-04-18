//
//  RawCullApp.swift
//  RawCull
//
//  Created by Thomas Evensen on 19/01/2026.
//

import OSLog
import SwiftUI

class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationShouldTerminateAfterLastWindowClosed(_: NSApplication) -> Bool {
        true
    }

    func applicationWillTerminate(_: Notification) {}
}

@main
struct RawCullApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    @State private var gridthumbnailviewmodel = GridThumbnailViewModel()
    @State private var viewModel = RawCullViewModel()

    var body: some Scene {
        Window("Photo Culling", id: "main-window") {
            RawCullMainView(viewModel: viewModel)
                .background(.windowBackground)
                .environment(gridthumbnailviewmodel)
                .environment(viewModel)
                .task {
                    await viewModel.applyStoredScoringSettings()
                }
                .onDisappear {
                    // Quit the app when the main window is closed
                    performCleanupTask()
                    NSApplication.shared.terminate(nil)
                }
        }
        .commands {
            SidebarCommands()

            MenuCommands()
        }

        Settings {
            SettingsView()
                .environment(viewModel)
        }
    }

    private func performCleanupTask() {
        Logger.process.debugMessageOnly("RawCullApp: performCleanupTask(), shutting down, doing clean up")
    }
}
