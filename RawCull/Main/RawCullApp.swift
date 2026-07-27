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
    @State private var viewModel: RawCullViewModel
    @State private var aiIntegration: RawCullAIIntegration
    @State private var aiSettingsModel: RawCullAISettingsModel

    init() {
        let integration = RawCullAIIntegration()
        let viewModel = RawCullViewModel(
            similarityService: integration.visionSimilarityService,
            semanticSearchCapability: integration.capabilities().semanticSearch,
            deepAIReviewFeature: integration.deepAIReviewFeature,
        )
        _viewModel = State(
            initialValue: viewModel,
        )
        _aiIntegration = State(initialValue: integration)
        _aiSettingsModel = State(
            initialValue: RawCullAISettingsModel(
                integration: integration,
                similarityServiceDidChange: { [weak viewModel] service in
                    viewModel?.setSimilarityService(service)
                },
                semanticSearchCapabilityDidChange: {
                    [weak viewModel] capability, service in
                    viewModel?.setSemanticSearchCapability(
                        capability,
                        service: service,
                    )
                },
            ),
        )
    }

    var body: some Scene {
        Window("Photo Culling", id: "main-window") {
            RawCullMainView(viewModel: viewModel)
                .background(.windowBackground)
                .environment(gridthumbnailviewmodel)
                .environment(viewModel)
                .task {
                    await viewModel.applyStoredScoringSettings()
                }
                .task {
                    await aiSettingsModel.refresh()
                }
                .onDisappear {
                    // Quit the app when the main window is closed
                    performCleanupTask()
                    NSApplication.shared.terminate(nil)
                }
        }
        .windowToolbarStyle(.unified)
        .commands {
            SidebarCommands()

            RawCullCommands()

            MenuCommands()
        }

        Settings {
            SettingsView(aiSettingsModel: aiSettingsModel)
                .environment(viewModel)
        }

        Window("Memory Console", id: "memory-diagnostics") {
            MemoryDiagnosticsView()
                .environment(viewModel)
        }
        .defaultSize(width: 720, height: 480)

        Window("Similarity Console", id: "similarity-diagnostics") {
            SimilarityDiagnosticsView()
        }
        .defaultSize(width: 860, height: 560)

        Window("About RawCull", id: "about-window") {
            AboutRawCullView()
                .background(.windowBackground)
        }
        .defaultSize(width: 840, height: 720)
    }

    private func performCleanupTask() {
        Logger.process.debugMessageOnly("RawCullApp: performCleanupTask(), shutting down, doing clean up")
        viewModel.stopActiveSecurityScopedAccess()
    }
}

private struct RawCullCommands: Commands {
    @Environment(\.openWindow) private var openWindow

    var body: some Commands {
        CommandGroup(replacing: .appInfo) {
            Button("About RawCull") {
                openWindow(id: "about-window")
            }
        }
    }
}
