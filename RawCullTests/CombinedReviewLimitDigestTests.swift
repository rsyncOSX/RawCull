import Foundation
@testable import RawCull
import Testing

@Suite("Combined Review limit digest")
struct CombinedReviewLimitDigestTests {
    private func limit(_ reason: String) -> ReviewLimitation {
        .init(id: .init(rawValue: UUID().uuidString), reason: reason, relatedEvidence: [])
    }

    @Test func `pipeline wording becomes plain sentences and nothing is dropped`() throws {
        let reasons = [
            "Crop fff36f7f306c: Rejected detail: crop.supportedDomain; criterion abstained",
            "Crop bff3ca135d71: Rejected detail: crop.criterionTargetConsistency; criterion abstained",
            "Crop fff36f7f306c cannot establish target-specific detail; target support is absent or unknown.",
            "Selected exposure rejected: selection.eligibleCriterionRow",
            "Selected visibility replaced with the highest-priority validated criterion row o2.",
            "No supported detail claim; abstained because admitted observations did not establish this criterion.",
            "Eye localization unavailable. Head and subject masks do not establish eye detail.",
            "Something the digest has never seen.",
        ]
        let source = ["Preview reduced from 9984×6656 to 4096×2731 to fit the review memory budget; fine-detail evidence is limited"]
        let omission = ReviewRegionOmission(regionID: .init(rawValue: "4466e5ef"), subjectID: nil, reason: .ambiguousAnatomy,
                                            detail: "Head-query foreground has no unique parent association")
        let notes = CombinedReviewLimitDigest.notes(limitations: reasons.map(limit), sourceLimitations: source, omissions: [omission])

        // Every original reason survives as a detail.
        #expect(notes.reduce(0) { $0 + $1.count } == reasons.count + source.count + 1)
        // The same check failing on two crops is one note counted twice.
        let rejected = try #require(notes.first { $0.text.contains("visible detail observation failed a check") })
        #expect(rejected.count == 2 && rejected.group == .findings)
        #expect(notes.contains { $0.group == .image && $0.text.contains("4096×2731 instead of 9984×6656") })
        #expect(notes.contains { $0.text.contains("The lighting statement did not meet the evidence rules") })
        #expect(notes.contains { $0.text.contains("subject visibility statement was replaced") })
        #expect(notes.contains { $0.group == .subject && $0.text.contains("eyes could not be located") })
        #expect(notes.contains { $0.group == .regions && $0.details.first?.contains("4466e5ef") == true })
        // Unrecognised wording is shown as it is, never hidden.
        #expect(notes.contains { $0.text == "Something the digest has never seen." })
        // No hashes or rule names leak into the plain sentences of recognised reasons.
        for note in notes where note.text != "Something the digest has never seen." {
            #expect(!note.text.contains("fff36f7f") && !note.text.contains("selection."))
        }
        // Groups come out in a stable order.
        #expect(notes.map(\.group.rawValue) == notes.map(\.group.rawValue).sorted())
    }

    @Test func `duplicate reasons from source and run are counted once`() {
        let reason = "Output is SDR RGBA8; higher precision source values are not retained"
        let notes = CombinedReviewLimitDigest.notes(limitations: [limit(reason)], sourceLimitations: [reason], omissions: [])
        #expect(notes.count == 1 && notes[0].count == 1)
    }
}
