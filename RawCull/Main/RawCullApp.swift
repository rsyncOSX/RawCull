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
    @State private var zoomCGImageWindowFocused: Bool = false
    @State private var zoomNSImageWindowFocused: Bool = false
    @State private var gridThumbnailWindowFocused: Bool = false
    @State private var settingsviewmodel = SettingsViewModel.shared
    @State private var gridthumbnailviewmodel = GridThumbnailViewModel()

    var body: some Scene {
        Window("Photo Culling", id: "main-window") {
            RawCullView(
                nsImage: $nsImage,
                cgImage: $cgImage,
                zoomCGImageWindowFocused: $zoomCGImageWindowFocused,
                zoomNSImageWindowFocused: $zoomNSImageWindowFocused
            )
            .environment(settingsviewmodel)
            .environment(gridthumbnailviewmodel)
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
                .environment(settingsviewmodel)
        }

        Window("ZoomcgImage", id: "zoom-window-cgImage") {
            ZoomableCSImageView(cgImage: cgImage)
                .onAppear {
                    zoomCGImageWindowFocused = true
                }
                .onDisappear {
                    zoomCGImageWindowFocused = false
                }
        }
        .defaultPosition(.center)
        .defaultSize(width: 800, height: 600)

        // If there is a extracted JPG image
        Window("ZoomnsImage", id: "zoom-window-nsImage") {
            ZoomableNSImageView(nsImage: nsImage)
                .onAppear {
                    zoomNSImageWindowFocused = true
                }
                .onDisappear {
                    zoomNSImageWindowFocused = false
                }
        }
        .defaultPosition(.center)
        .defaultSize(width: 800, height: 600)

        Window("Grid Thumbnails", id: "grid-thumbnails-window") {
            GridThumbnailView()
                .environment(settingsviewmodel)
                .environment(gridthumbnailviewmodel)
                .onAppear {
                    gridThumbnailWindowFocused = true
                }
                .onDisappear {
                    gridThumbnailWindowFocused = false
                }
        }
        .defaultPosition(.center)
        .defaultSize(width: 900, height: 700)
    }

    private func performCleanupTask() {
        Logger.process.debugMessageOnly("RawCullApp: performCleanupTask(), shutting down, doing clean up")
    }
}

enum WindowIdentifier: String {
    case main = "main-window"
    case zoomcgImage = "zoom-window-cgImage"
    case zoomnsImage = "zoom-window-nsImage"
    case gridThumbnails = "grid-thumbnails-window"
}

enum SupportedFileType: String, CaseIterable {
    case arw
    case tiff, tif
    case jpeg, jpg

    var extensions: [String] {
        switch self {
        case .arw: return ["arw"]
        case .tiff: return ["tiff"]
        case .jpeg: return ["jpeg"]
        case .tif: return ["tif"]
        case .jpg: return ["jpg"]
        }
    }
}
