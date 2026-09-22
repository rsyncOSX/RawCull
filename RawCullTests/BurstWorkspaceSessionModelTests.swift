import CoreGraphics
@testable import RawCull
import Testing

@MainActor
@Suite("BurstWorkspaceSessionModel")
struct BurstWorkspaceSessionModelTests {
    @Test
    func `sliding window stays bounded around selection`() {
        let model = BurstWorkspaceSessionModel()
        #expect(model.cachedWindowIndices(selectedIndex: 0, itemCount: 5) == [0, 1])
        #expect(model.cachedWindowIndices(selectedIndex: 2, itemCount: 5) == [1, 2, 3])
        #expect(model.cachedWindowIndices(selectedIndex: 4, itemCount: 5) == [3, 4])
    }

    @Test
    func `group reset clears presentation and restores viewport`() {
        let model = BurstWorkspaceSessionModel()
        model.showSubjectOutline = true
        model.viewportState.scale = 3
        model.sourceSelection.select(.developedRAW)

        model.resetForGroupChange()

        #expect(!model.showSubjectOutline)
        #expect(model.viewportState.scale == 1)
        #expect(model.imageCache.isEmpty)
    }
}
