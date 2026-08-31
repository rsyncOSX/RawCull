@testable import RawCull
import Testing

@MainActor
@Suite("Accessibility presentation", .tags(.smoke))
struct AccessibilityPresentationTests {
    @Test
    func `saved rows announce content and selection`() {
        #expect(RawCullAccessibilityPresentation.savedCatalogValue(
            fileCount: 3,
            date: "4 August 2026",
            isSelected: true,
        ) == "3 files, 4 August 2026, Selected")
        #expect(RawCullAccessibilityPresentation.savedRecordValue(
            rating: 4,
            dateTagged: "Today",
            isSelected: false,
        ) == "4-star rating, Tagged Today, Not selected")
    }

    @Test
    func `image tiles announce rating and selection`() {
        #expect(RawCullAccessibilityPresentation.imageValue(
            rating: .keeper,
            isSelected: false,
            isMultiSelected: true,
        ) == "Keeper, Included in selection")
    }
}
