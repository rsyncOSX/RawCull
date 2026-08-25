//
//  RawCullApp.swift
//  RawCull
//
//  Created by Thomas Evensen on 19/01/2026.
//

import OSLog
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private weak var viewModel: RawCullViewModel?
    private var terminationTask: Task<Void, Never>?

    func configure(viewModel: RawCullViewModel) {
        self.viewModel = viewModel
    }

    func applicationShouldTerminateAfterLastWindowClosed(_: NSApplication) -> Bool {
        true
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard let viewModel else { return .terminateNow }
        guard terminationTask == nil else { return .terminateLater }

        terminationTask = Task {
            let didSave = await viewModel.cullingModel.flushPersistence()
            if didSave {
                viewModel.stopActiveSecurityScopedAccess()
            }
            terminationTask = nil
            sender.reply(toApplicationShouldTerminate: didSave)
        }
        return .terminateLater
    }
}

@main
struct RawCullApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    @State private var gridthumbnailviewmodel = GridThumbnailViewModel()
    @State private var viewModel: RawCullViewModel
    @State private var aiSettingsModel: RawCullAISettingsModel

    init() {
        let integration = RawCullAIIntegration()
        let viewModel = RawCullViewModel(
            similarityService: integration.visionSimilarityService,
            semanticSearchCapability: integration.capabilities()
                .semanticSearchStatus(for: .defaultSelection),
            deepAIReviewFeature: integration.deepAIReviewFeature,
        )
        _viewModel = State(
            initialValue: viewModel,
        )
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
                .onAppear {
                    appDelegate.configure(viewModel: viewModel)
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

        Window("About RawCull", id: "about-window") {
            AboutRawCullView()
                .background(.windowBackground)
                .environment(viewModel)
        }
        .defaultSize(width: 840, height: 720)
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
