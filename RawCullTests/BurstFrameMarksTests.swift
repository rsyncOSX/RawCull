@testable import RawCull
import Testing

@Suite("Burst frame marks")
struct BurstFrameMarksTests {
    @Test func `leader is the single highest value`() {
        #expect(BurstFrameMarks.leader([(id: "a", value: 3.0), (id: "b", value: 4.3), (id: "c", value: 2.0)]) == "b")
    }

    @Test func `no leader for a tie or a single value`() {
        #expect(BurstFrameMarks.leader([(id: "a", value: 4.0), (id: "b", value: 4.0)]) == nil)
        #expect(BurstFrameMarks.leader([(id: "a", value: 4.0)]) == nil)
        #expect(BurstFrameMarks.leader([(id: String, value: Double)]()) == nil)
    }

    @MainActor @Test func `picks bar shows only when the AI pick differs`() {
        func pick(_ kind: BurstFramePick.Kind, _ name: String) -> BurstFramePick {
            BurstFramePick(kind: kind, fileName: name) {}
        }
        #expect(BurstFramePicksBar.isShown(for: [pick(.aiTop, "a"), pick(.suggested, "b")]))
        #expect(!BurstFramePicksBar.isShown(for: [pick(.aiTop, "a"), pick(.suggested, "a"), pick(.sharpest, "a")]))
        #expect(!BurstFramePicksBar.isShown(for: [pick(.suggested, "a"), pick(.sharpest, "b")]))
    }
}
