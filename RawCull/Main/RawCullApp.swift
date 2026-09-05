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
        return beginTermination(
            flush: { await viewModel.cullingModel.flushPersistence() },
            chooseRecovery: { Self.showQuitRecovery(error: viewModel.cullingModel.persistenceError) },
            setPending: { viewModel.cullingModel.isTerminationPending = $0 },
            releaseAccess: { viewModel.stopActiveSecurityScopedAccess() },
            reply: { sender.reply(toApplicationShouldTerminate: $0) },
        )
    }

    enum QuitRecoveryChoice {
        case retry, cancel, discard
    }

    // Keep exactly one deferred termination request alive through retries.
    // Closures let tests exercise the real lifecycle without terminating the test host.
    func beginTermination(
        flush: @escaping @MainActor () async -> Bool,
        chooseRecovery: @escaping @MainActor () -> QuitRecoveryChoice,
        setPending: @escaping @MainActor (Bool) -> Void,
        releaseAccess: @escaping @MainActor () -> Void,
        reply: @escaping @MainActor (Bool) -> Void,
    ) -> NSApplication.TerminateReply {
        guard terminationTask == nil else { return .terminateLater }
        setPending(true)
        terminationTask = Task {
            var shouldQuit = false
            saveAttempts: while true {
                if await flush() {
                    shouldQuit = true
                    break
                }
                switch chooseRecovery() {
                case .retry: continue
                case .cancel: break saveAttempts
                case .discard:
                    shouldQuit = true
                    break saveAttempts
                }
            }
            if shouldQuit { releaseAccess() }
            terminationTask = nil
            // Keep the normal persistence alert suppressed while exiting.
            if !shouldQuit { setPending(false) }
            reply(shouldQuit)
        }
        return .terminateLater
    }

    private static func showQuitRecovery(error: String?) -> QuitRecoveryChoice {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = String(localized: "Changes Could Not Be Saved")
        alert.informativeText = String(localized: "Retry after restoring access or freeing disk space, cancel quitting to keep your changes in memory, or quit without saving. Quitting without saving discards unsaved ratings and culling changes.") + "\n\n" + (error ?? "")
        alert.addButton(withTitle: String(localized: "Retry"))
        alert.addButton(withTitle: String(localized: "Cancel Quit")).keyEquivalent = "\u{1b}"
        let discard = alert.addButton(withTitle: String(localized: "Quit Without Saving"))
        discard.hasDestructiveAction = true
        discard.keyEquivalent = ""
        // An app-modal alert also works after the last window has closed.
        switch alert.runModal() {
        case .alertFirstButtonReturn: return .retry
        case .alertThirdButtonReturn: return .discard
        default: return .cancel
        }
    }
}

@main
struct RawCullApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    @State private var gridthumbnailviewmodel = GridThumbnailViewModel()
    @State private var viewModel: RawCullViewModel
    @State private var intelligenceRuntime: RawCullIntelligenceRuntime

    init() {
        let applicationState = RawCullApplicationState.live()
        _viewModel = State(
            initialValue: applicationState.viewModel,
        )
        _intelligenceRuntime = State(
            initialValue: applicationState.intelligenceRuntime,
        )
    }

    var body: some Scene {
        Window("Photo Culling", id: "main-window") {
            RawCullMainView(
                viewModel: viewModel,
                similarityFeature: intelligenceRuntime.similarityFeature,
                semanticSearchFeature: intelligenceRuntime.semanticSearchFeature,
                deepAIReviewController: intelligenceRuntime.deepAIReviewController,
            )
            .background(.windowBackground)
            .environment(gridthumbnailviewmodel)
            .environment(viewModel)
            .task {
                await viewModel.applyStoredScoringSettings()
            }
            .task {
                await intelligenceRuntime.settingsModel.refresh()
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
            SettingsView(aiSettingsModel: intelligenceRuntime.settingsModel)
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
