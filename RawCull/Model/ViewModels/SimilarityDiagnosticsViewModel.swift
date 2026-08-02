import AppKit
import Foundation
import Observation

@Observable
@MainActor
final class SimilarityDiagnosticsViewModel {
    private(set) var logText = ""
    private(set) var isLoading = false
    private(set) var errorMessage: String?

    let logFilePath: String

    @ObservationIgnored private let logStore: SimilarityDiagnosticsLog

    init(logStore: SimilarityDiagnosticsLog = .shared) {
        self.logStore = logStore
        self.logFilePath = logStore.fileURL.path
    }

    func refresh() async {
        guard !isLoading else { return }
        isLoading = true
        defer { isLoading = false }

        do {
            logText = try await logStore.contents()
            errorMessage = nil
        } catch {
            errorMessage = String(describing: error)
        }
    }

    func clear() async {
        guard !isLoading else { return }
        isLoading = true
        defer { isLoading = false }

        do {
            try await logStore.clear()
            logText = ""
            errorMessage = nil
        } catch {
            errorMessage = String(describing: error)
        }
    }

    func copyAllToClipboard() {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(logText, forType: .string)
    }
}
