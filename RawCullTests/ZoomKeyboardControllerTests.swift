@testable import RawCull
import SwiftUI
import Testing

@MainActor
@Suite("Zoom keyboard controller")
struct ZoomKeyboardControllerTests {
    @Test
    func `exposure inspection keeps navigation and rating disabled`() {
        let session = ZoomSessionModel()
        var navigations = 0
        var ratings = 0
        var zooms = 0
        let controller = ZoomKeyboardController(
            session: session, hasSubjectOutline: true,
            navigate: { _ in navigations += 1 }, dismiss: session.endRAWExposureInspection,
            increaseZoom: { zooms += 1 }, decreaseZoom: {},
            applyRating: { _ in
                ratings += 1
                return .handled
            },
        )
        session.beginRAWExposureInspection()
        #expect(controller.handle(.navigateNext) == .handled)
        #expect(controller.handle(.rating(5)) == .handled)
        #expect(controller.handle(.toggleFocusMask) == .handled)
        #expect(navigations == 0)
        #expect(ratings == 0)
        #expect(!session.viewport.showFocusMask)
        #expect(controller.handle(.zoomIn) == .handled)
        #expect(zooms == 1)
        #expect(controller.handle(.escape) == .handled)
        #expect(!session.evaluateRAWExposure)
        #expect(controller.handle(.navigateNext) == .handled)
        #expect(navigations == 1)
    }

    @Test
    func `subject outline shortcut requires an available outline`() {
        let session = ZoomSessionModel()
        let controller = ZoomKeyboardController(
            session: session, hasSubjectOutline: false,
            navigate: { _ in }, dismiss: {}, increaseZoom: {}, decreaseZoom: {}, applyRating: { _ in .handled },
        )
        #expect(controller.handle(.toggleSubjectOutline) == .ignored)
        #expect(!session.showSubjectOutline)
        #expect(controller.handle(nil) == .ignored)
    }
}
