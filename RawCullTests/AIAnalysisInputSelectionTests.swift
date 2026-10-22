@testable import RawCull
import SwiftUI
import Testing

@MainActor
@Suite("Analysis input selection")
struct AIAnalysisInputSelectionTests {
    @Test
    func `preserves grid selection only when leaving the grid`() {
        var source = AIAnalysisInputSource.gridSelection
        var preservedSources: [AIAnalysisInputSource] = []
        let binding = AIAnalysisInputSelection.binding(
            selection: Binding(get: { source }, set: { source = $0 }),
            preserveGridSelection: { preservedSources.append(source) },
        )
        binding.wrappedValue = .taggedImages
        #expect(source == .taggedImages)
        #expect(preservedSources == [.gridSelection])
        binding.wrappedValue = .taggedImages
        binding.wrappedValue = .gridSelection
        #expect(source == .gridSelection)
        #expect(preservedSources == [.gridSelection])
    }
}
