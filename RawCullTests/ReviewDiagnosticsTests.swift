import Foundation
@testable import RawCull
import Testing

@Suite("Bounded review diagnostics", .tags(.smoke))
struct ReviewDiagnosticsTests {
    @Test func `rejections preserve the failing decoder or guard without copying untrusted text`() throws {
        let crop = #"{"regionID":"region","observations":"Texture visible","uncertainty":"Limited","insufficientEvidence":false}"#
        let cases: [(String, ReviewValidationCode, String)] = [
            ("not JSON", .json, "json.completeObject"),
            ("{}", .schema, "schema.requiredFieldOrType"),
            (crop.replacingOccurrences(of: #""region""#, with: #""wrong""#), .unknownID, "crop.expectedRegionID"),
            (crop.replacingOccurrences(of: "Texture visible", with: "Sharp eye detail"), .unsupportedDomain, "crop.supportedDomain"),
            (crop.replacingOccurrences(of: "Texture visible", with: String(repeating: "x", count: 501)), .responseLength, "text.characterAllowance")
        ]
        for (text, code, check) in cases {
            do {
                _ = try CombinedReviewResponse.validated(text) { try CombinedReviewResponse.inspection($0, regionID: "region") }
                Issue.record("Expected rejection")
            } catch let error as ReviewResponseRejection {
                #expect(error.issue.code == code)
                #expect(error.issue.check == check)
                #expect(error.response == text)
                #expect(!error.issue.check.contains("Sharp eye detail"))
                if code == .schema { #expect(error.issue.fieldPath == "regionID") }
            }
        }
        let schema = ReviewValidationIssue.classify(ObjectResponseIssue.invalidSchema("claims.private/path/secret.text"))
        #expect(schema.fieldPath == "claims.text")
    }

    @Test func `grounding ownership runtime mask geometry budget and timeout remain distinct`() throws {
        #expect(ReviewValidationIssue.classify(ReviewRunError.budgetExhausted).code == .budget)
        #expect(ReviewValidationIssue.classify(SubjectMaskDecodingError.emptyForeground).code == .maskDecoding)
        #expect(ReviewValidationIssue.classify(SubjectMaskDecodingError.unsafeRegistration).code == .geometry)
        #expect(ReviewValidationIssue.classify(ReviewImageError.unsupportedAlignment).code == .geometry)
        #expect(ReviewValidationIssue.classify(NSError(domain: NSURLErrorDomain, code: NSURLErrorTimedOut)).code == .timeout)
        #expect(ReviewValidationIssue.classify(CancellationError()).code == .cancellation)
        #expect(ReviewValidationIssue.classify(NSError(domain: "private/path", code: 1)).check == "runtime.stageFailure")
        let response = #"{"claims":[{"text":"Texture visible","type":"detail","evidence":[],"uncertainty":"Limited","contradictions":[]}]}"#
        do {
            _ = try CombinedReviewResponse.report(response, imageID: .init(rawValue: "image"), allowed: [], limitations: [], regions: [], uninspected: [], incomplete: true)
            Issue.record("Missing evidence must fail")
        } catch let issue as ReviewValidationIssue {
            #expect(issue.code == .grounding)
            #expect(issue.check == "report.evidenceRequired")
        }
        let left = result("left"), right = result("right")
        let claim = ReviewClaim(text: "Visible composition", type: "composition", evidence: [.init(kind: .observation, id: "right-observation")], uncertainty: "Limited", contradictions: [])
        let comparison = ReviewSelectionReport(comparability: .comparable, decision: .abstain, preferred: [], claims: [.init(imageIDs: [left.file.id], claim: claim)], reason: "Limited")
        do {
            try comparison.validate(results: [left, right]); Issue.record("Cross-image support must fail")
        } catch let issue as ReviewValidationIssue { #expect(issue.code == .ownership) }
    }

    @Test func `raw text retention is UTF8 bounded separate from findings reloadable and cleanable`() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = ReviewArtifactStore(root: root)
        let text = String(repeating: "å🚀", count: 4096)
        let bounded = ReviewDiagnosticLimits.bounded(text, maximumBytes: ReviewDiagnosticLimits.perResponseBytes)
        #expect(bounded.text.utf8.count <= 4096)
        #expect(!bounded.text.contains("�"))
        #expect(bounded.truncated)
        let response = ReviewRejectedResponse(runID: UUID(), workID: .init(rawValue: "report"), text: bounded.text, truncated: bounded.truncated)
        let key = try await store.retainRejectedResponse(response)
        let loaded = try await store.rejectedResponse(key)
        #expect(loaded.text == response.text)
        #expect(loaded.workID == response.workID)
        #expect(!FileManager.default.fileExists(atPath: root.appendingPathComponent("stages").path))
        #expect(ReviewDiagnosticLimits.bounded(text, maximumBytes: 0).text.isEmpty)
        try await store.clearRejectedResponses()
        await #expect(throws: (any Error).self) { try await store.rejectedResponse(key) }
    }

    private func result(_ id: String) -> CombinedReviewResult {
        let imageID = ReviewImageID(rawValue: id)
        var value = CombinedReviewResult(file: .init(id: imageID, fileID: UUID(), url: URL(filePath: "/fixture"), displayName: "Fixture", fingerprint: id))
        value.observations = [.init(id: .init(rawValue: id + "-observation"), regionID: nil, text: "Visible composition", uncertainty: "Limited", availability: .available,
                                   provenance: .init(workID: .init(rawValue: "overview"), imageID: imageID, sourceIdentity: id, renderPolicy: "appearance", compatibility: .init(fields: [:]), modelIdentity: nil, inputReference: nil))]
        return value
    }
}
