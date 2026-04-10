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
    @State private var nsImage: NSImage?
    @State private var cgImage: CGImage?

    @State private var gridthumbnailviewmodel = GridThumbnailViewModel()
    @State private var viewModel = RawCullViewModel()

    var body: some Scene {
        Window("Photo Culling", id: "main-window") {
            RawCullMainView(
                viewModel: viewModel,
                nsImage: $nsImage,
                cgImage: $cgImage,
            )
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
        }

        Window("ZoomcgImage", id: "zoom-window-cgImage") {
            ZoomableFocusePeekCSImageView(
                cgImage: cgImage, // ← pass viewModel instead
            )
            .environment(viewModel)
            .onAppear { viewModel.zoomCGImageWindowFocused = true }
            .onDisappear { viewModel.zoomCGImageWindowFocused = false }
        }

        .defaultPosition(.center)
        .defaultSize(width: 800, height: 600)

        // If there is a extracted JPG image
        Window("ZoomnsImage", id: "zoom-window-nsImage") {
            ZoomableFocusePeekNSImageView(
                nsImage: nsImage,
            )
            .environment(viewModel)
            .onAppear { viewModel.zoomNSImageWindowFocused = true }
            .onDisappear { viewModel.zoomNSImageWindowFocused = false }
        }
        .defaultPosition(.center)
        .defaultSize(width: 800, height: 600)

        Window("Grid Tagged Images", id: "grid-tagged-thumbnails-window") {
            TaggedPhotoHorisontalGridView(
                viewModel: viewModel,
                catalogURL: viewModel.selectedSource?.url,
                onPhotoSelected: { file in
                    viewModel.selectedFileID = file.id
                    viewModel.selectedFile = file
                },
            )
        }
        .defaultPosition(.center)
        .defaultSize(width: 900, height: 700)
    }

    private func performCleanupTask() {
        Logger.process.debugMessageOnly("RawCullApp: performCleanupTask(), shutting down, doing clean up")
    }
}
