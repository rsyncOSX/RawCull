import Foundation
@testable import RawCull
import RawCullCore
import Testing

@Suite("AI analysis selection")
struct AIAnalysisSelectionTests {
    @MainActor
    @Test
    func `Grid source includes only selected files in catalog order`() {
        let state = RawCullApplicationState.make(
            integration: makeIntegration(),
            userDefaults: isolatedUserDefaults(),
        )
        let first = makeFile("first.ARW")
        let second = makeFile("second.ARW")
        let third = makeFile("third.ARW")
        state.viewModel.filteredFiles = [first, second, third]
        state.viewModel.selectedFileIDs = [third.id, first.id]

        #expect(
            state.viewModel.aiAnalysisFiles(for: .gridSelection).map(\.id)
                == [first.id, third.id],
        )
    }

    @MainActor
    @Test
    func `Grid source falls back to the focused image`() {
        let state = RawCullApplicationState.make(
            integration: makeIntegration(),
            userDefaults: isolatedUserDefaults(),
        )
        let file = makeFile("focused.ARW")
        state.viewModel.filteredFiles = [file]
        state.viewModel.selectedFileID = file.id

        #expect(state.viewModel.aiAnalysisFiles(for: .gridSelection).map(\.id) == [file.id])
    }

    @MainActor
    @Test
    func `Selected analysis images survive main view changes`() {
        let state = RawCullApplicationState.make(
            integration: makeIntegration(),
            userDefaults: isolatedUserDefaults(),
        )
        let first = makeFile("first.ARW")
        let second = makeFile("second.ARW")
        state.viewModel.filteredFiles = [first, second]
        state.viewModel.selectedFileIDs = [first.id, second.id]

        state.viewModel.selectMainViewMode(.aiAnalysis)
        state.viewModel.selectMainViewMode(.loupe)
        state.viewModel.selectMainViewMode(.aiAnalysis)

        #expect(state.viewModel.selectedFileIDs == [first.id, second.id])
        #expect(
            state.viewModel.aiAnalysisFiles(for: .gridSelection).map(\.id)
                == [first.id, second.id],
        )
    }

    private func makeFile(_ name: String) -> FileItem {
        FileItem(
            id: UUID(),
            url: URL(filePath: "/tmp/\(name)"),
            name: name,
            size: 1,
            dateModified: .distantPast,
            exifData: nil,
            afFocusNormalized: nil,
        )
    }

    private func isolatedUserDefaults() -> UserDefaults {
        let suite = "AIAnalysisSelectionTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        return defaults
    }

    @MainActor
    private func makeIntegration() -> RawCullAIIntegration {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("AIAnalysisSelectionTests-\(UUID().uuidString)", isDirectory: true)
        return RawCullAIIntegration(
            paths: RawCullAIPaths(
                applicationSupportRoot: root.appendingPathComponent("Application Support"),
                cachesRoot: root.appendingPathComponent("Caches"),
            ),
            allowsBundledModelFallback: false,
        )
    }
}
