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

        Window("ZoomcgImage", id: "zoom-window-cgImage") {
            ZoomableFocusePeekCSImageView(
                cgImage: cgImage, // ← pass viewModel instead
            )
            .background(.windowBackground)
            .environment(viewModel)
            .onAppear { viewModel.zoomCGImageWindowFocused = true }
            .onDisappear {
                viewModel.zoomCGImageWindowFocused = false
                viewModel.zoomExtractionTask?.cancel()
                viewModel.zoomExtractionTask = nil
                cgImage = nil
            }
        }

        .defaultPosition(.center)
        .defaultSize(width: 800, height: 600)

        // If there is a extracted JPG image
        Window("ZoomnsImage", id: "zoom-window-nsImage") {
            ZoomableFocusePeekNSImageView(
                nsImage: nsImage,
            )
            .background(.windowBackground)
            .environment(viewModel)
            .onAppear { viewModel.zoomNSImageWindowFocused = true }
            .onDisappear {
                viewModel.zoomNSImageWindowFocused = false
                viewModel.zoomExtractionTask?.cancel()
                viewModel.zoomExtractionTask = nil
                nsImage = nil
            }
        }
        .defaultPosition(.center)
        .defaultSize(width: 800, height: 600)

        Window("Thumbnail Grid", id: "grid-thumbnails-window") {
            GridThumbnailView(
                viewModel: viewModel,
                nsImage: $nsImage,
                cgImage: $cgImage,
            )
            .background(.windowBackground)
            .environment(viewModel)
            .environment(gridthumbnailviewmodel)
        }
        .defaultPosition(.center)
        .defaultSize(width: 1200, height: 800)

        Window("Grid Tagged Images", id: "grid-tagged-thumbnails-window") {
            TaggedPhotoHorisontalGridView(
                viewModel: viewModel,
                catalogURL: viewModel.selectedSource?.url,
                onPhotoSelected: { file in
                    viewModel.selectedFileID = file.id
                },
            )
            .background(.windowBackground)
        }
        .defaultPosition(.center)
        .defaultSize(width: 900, height: 700)
    }

    private func performCleanupTask() {
        Logger.process.debugMessageOnly("RawCullApp: performCleanupTask(), shutting down, doing clean up")
    }
}
