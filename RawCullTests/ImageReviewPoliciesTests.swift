import Foundation
@testable import RawCull
import Testing

@Suite("Image review policies")
struct ImageReviewPoliciesTests {
    @Test
    func `RAW failure restores the previous source and produces presentation inputs`() {
        var selection = ImageSourceSelectionState(initialSource: .embeddedJPG)
        selection.select(.developedRAW)
        selection.markDevelopedRAWUnavailable()

        let presentation = ImageReviewSourcePresentation(
            selection: selection,
            showsDevelopedRAWFailure: true,
        )

        #expect(presentation.selectedSource == .embeddedJPG)
        #expect(!presentation.isDevelopedRAWAvailable)
        #expect(presentation.failure == .developedRAWUnavailable)
        #expect(presentation.failure?.message == "Not supported")
    }

    @Test
    func `viewport policies clamp each surface to its own limits`() {
        let comparison = ImageReviewViewportPolicy.comparison
        let loupe = ImageReviewViewportPolicy.loupe

        #expect(comparison.zoomedIn(from: 4.8) == 5.0)
        #expect(comparison.zoomedOut(from: 0.6) == 0.5)
        #expect(comparison.clamped(12) == 5.0)
        #expect(loupe.zoomedIn(from: 3.9) == 4.0)
        #expect(loupe.zoomedOut(from: 0.6) == 0.5)
        #expect(loupe.clamped(-1) == 0.5)
    }

    @Test
    func `keyboard input resolves to shared semantic actions`() {
        #expect(ImageReviewKeyboardPolicy.action(for: "+") == .zoomIn)
        #expect(ImageReviewKeyboardPolicy.action(for: "J") == .toggleEmbeddedJPG)
        #expect(ImageReviewKeyboardPolicy.action(for: "r") == .toggleDevelopedRAW)
        #expect(ImageReviewKeyboardPolicy.action(for: "F") == .toggleFocusMask)
        #expect(ImageReviewKeyboardPolicy.action(for: "s") == .toggleSubjectOutline)
        #expect(ImageReviewKeyboardPolicy.action(for: "A") == .toggleFocusPoints)
        #expect(ImageReviewKeyboardPolicy.action(for: "x") == .rating(.reject))
        #expect(ImageReviewKeyboardPolicy.action(for: "P") == .rating(.keeper))
        #expect(ImageReviewKeyboardPolicy.action(for: "T") == .rating(.stars(3)))
        #expect(ImageReviewKeyboardPolicy.action(for: "q") == nil)
    }

    @Test
    func `rating policy distinguishes unrated keeper reject and stars`() {
        #expect(RatingDisplay(rating: 0, isExplicit: false) == .unrated)
        #expect(RatingDisplay(rating: 0, isExplicit: true) == .keeper)
        #expect(RatingDisplay(rating: -1) == .rejected)
        #expect(RatingDisplay(rating: 4) == .stars(4))
        #expect(ImageReviewRatingAction.stars(5).value == 5)
    }

    @Test
    func `focus request identity rejects cancellation supersession and stale content`() {
        let fileID = UUID()
        var tracker = ImageReviewRequestTracker<ImageReviewFocusRequestContext>()
        let older = tracker.begin(
            context: ImageReviewFocusRequestContext(fileIDs: [fileID]),
            generation: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!,
        )
        let newer = tracker.begin(
            context: ImageReviewFocusRequestContext(fileIDs: [fileID]),
            generation: UUID(uuidString: "00000000-0000-0000-0000-000000000002")!,
        )

        #expect(!tracker.accepts(older, isCancelled: false))
        #expect(tracker.accepts(newer, isCancelled: false, requestRevision: 4, currentRevision: 4))
        #expect(!tracker.accepts(newer, isCancelled: true, requestRevision: 4, currentRevision: 4))
        #expect(!tracker.accepts(newer, isCancelled: false, requestRevision: 4, currentRevision: 5))

        tracker.cancel()
        #expect(!tracker.accepts(newer, isCancelled: false))
    }

    @Test
    func `subject outline context participates in request identity`() {
        let fileID = UUID()
        var tracker = ImageReviewRequestTracker<ImageReviewSubjectOutlineRequestContext>()
        let first = tracker.begin(context: ImageReviewSubjectOutlineRequestContext(
            fileID: fileID,
            prompt: "person",
            isPresented: true,
        ))
        let replacement = tracker.begin(context: ImageReviewSubjectOutlineRequestContext(
            fileID: fileID,
            prompt: "face",
            isPresented: true,
        ))

        #expect(!tracker.accepts(first, isCancelled: false))
        #expect(tracker.accepts(replacement, isCancelled: false))
    }
}
