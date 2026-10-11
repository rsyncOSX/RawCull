import CoreGraphics
import Foundation
@testable import RawCull
import Testing

@Suite("Bounded review diagnostics", .tags(.smoke))
struct ReviewDiagnosticsTests {
    @Test func `eleven recorded discovery failures preserve bounded core evidence without inventing locations`() throws {
        struct Fixture: Decodable { let run: String; let file: String; let response: String }
        struct Original: Decodable { let observations: String; let uncertainty: String }
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        let fixtures = try JSONDecoder().decode([Fixture].self, from: Data(contentsOf: root.appendingPathComponent("Docs/CombinedReviewRegression/overview-responses-v8.json")))
        #expect(fixtures.count == 11)
        for fixture in fixtures {
            let original = try JSONDecoder().decode(Original.self, from: Data(fixture.response.utf8))
            let value = try CombinedReviewResponse.overview(fixture.response)
            #expect(value.observations == original.observations, "\(fixture.run) \(fixture.file)")
            #expect(value.uncertainty == original.uncertainty)
            #expect(!value.concepts.isEmpty)
            #expect(value.primarySubjects?.allSatisfy { value.concepts.contains($0.concept) && $0.location == nil } == true)
            #expect(value.contextualConcepts?.allSatisfy(value.concepts.contains) == true)
        }
    }

    @Test func `ambiguous aliases and invalid optional points abstain while oversized core text still fails`() throws {
        let response = #"{"observations":"Two subjects","uncertainty":"Limited","concepts":[{"query":"first bird","displayName":"Bird","reason":"Visible"},{"query":"second bird","displayName":"Bird","reason":"Visible"}],"primarySubjects":[{"concept":"Bird","reason":"Main"},{"concept":"first bird","reason":"Main","location":{"x":100,"y":200}}],"contextualConcepts":["unseen"]}"#
        let value = try CombinedReviewResponse.overview(response)
        #expect(value.primarySubjects?.count == 1)
        #expect(value.primarySubjects?.first?.concept == "first bird")
        #expect(value.primarySubjects?.first?.location == nil)
        #expect(value.contextualConcepts?.isEmpty == true)
        #expect(value.validationNotes?.count == 3)
        #expect(throws: ReviewValidationIssue.self) {
            try CombinedReviewResponse.overview(response.replacingOccurrences(of: "Limited", with: String(repeating: "x", count: 501)))
        }
        let restored = try JSONDecoder().decode(CombinedReviewOverview.self, from: JSONEncoder().encode(value))
        #expect(restored.validationNotes == value.validationNotes)
    }

    @Test func `scene conflicts span registered subjects but subject detail conflicts remain local`() throws {
        let value = groundedResult(), grounding = ReviewSynthesisGrounding(result: groundedResult())
        let claim = ReviewClaim(text: "Foreground and context disagree", type: "composition", evidence: [.init(kind: .observation, id: "crop-a")], uncertainty: "Conflict", contradictions: [.init(kind: .observation, id: "crop-b")])
        let qualified = try grounding.validate(claim)
        #expect(qualified.subjectID == nil)
        #expect(qualified.regionID == nil)
        let detail = ReviewClaim(text: claim.text, type: "detail", evidence: claim.evidence, uncertainty: claim.uncertainty, contradictions: claim.contradictions)
        #expect(throws: ReviewValidationIssue.self) { try grounding.validate(detail) }
        var response = ""
        for (alias, criterion) in [("lighting", "exposure"), ("subject visibility", "visibility"), ("behavior", "visibility")] {
            let generated = ReviewClaim(text: "Soft illumination", type: alias, evidence: claim.evidence, uncertainty: "Limited", contradictions: [])
            response = String(decoding: try JSONEncoder().encode(["claims": [generated]]), as: UTF8.self)
            let report = try CombinedReviewResponse.report(response, imageID: value.file.id, allowed: Set(claim.evidence), limitations: [], regions: [], uninspected: [], incomplete: false, qualify: grounding.validate)
            #expect(report.claims.first?.type == criterion)
        }
        let unknown = response.replacingOccurrences(of: "behavior", with: "quality")
        #expect(throws: ReviewValidationIssue.self) {
            try CombinedReviewResponse.report(unknown, imageID: value.file.id, allowed: Set(claim.evidence), limitations: [], regions: [], uninspected: [], incomplete: false, qualify: grounding.validate)
        }
    }

    @Test func `fallback target flag alone cannot establish subject detail`() throws {
        var value = groundedResult()
        let data = try JSONEncoder().encode(value.regions[0])
        var object = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        object.removeValue(forKey: "subjectID")
        value.regions[0] = try JSONDecoder().decode(ReviewRegionRecord.self, from: JSONSerialization.data(withJSONObject: object))
        let claim = ReviewClaim(text: "Visible animal fur", type: "detail", evidence: [.init(kind: .observation, id: "crop-a")], uncertainty: "Limited", contradictions: [])
        #expect(throws: ReviewValidationIssue.self) { try ReviewSynthesisGrounding(result: value).validate(claim) }
    }

    @Test func `overview rejects copied instructions and discards undiscovered optional context`() throws {
        let copied = #"{"observations":"visible composition, exposure, subjects, obstructions; at most 500 characters","uncertainty":"Limited","concepts":[{"query":"deer","displayName":"Deer","reason":"Visible"}],"contextualConcepts":[]}"#
        #expect(throws: ReviewValidationIssue.self) { try CombinedReviewResponse.overview(copied) }
        let valid = copied.replacingOccurrences(of: "visible composition, exposure, subjects, obstructions; at most 500 characters", with: "Deer beside a tree")
        #expect(try CombinedReviewResponse.overview(valid).concepts == ["deer"])
        let recovered = try CombinedReviewResponse.overview(valid.replacingOccurrences(of: #""contextualConcepts":[]"#, with: #""contextualConcepts":["flower"]"#))
        #expect(recovered.concepts == ["deer"])
        #expect(recovered.contextualConcepts?.isEmpty == true)
        #expect(recovered.validationNotes?.contains { $0.contains("overview.discoveredContextualConcept") } == true)
    }

    @Test func `partial synthesis retains valid observations and reports rejected claims`() throws {
        let value = groundedResult()
        let grounding = ReviewSynthesisGrounding(result: value)
        let good = ReviewClaim(text: "Visible texture", type: "detail", evidence: [.init(kind: .observation, id: "crop-a")], uncertainty: "Limited", contradictions: [])
        let bad = ReviewClaim(text: "Flower texture", type: "detail", evidence: [.init(kind: .measurement, id: "metric-a")], uncertainty: "Limited", contradictions: [])
        let text = String(decoding: try JSONEncoder().encode(["claims": [good, bad]]), as: UTF8.self)
        let allowed = Set(good.evidence + bad.evidence)
        let report = try CombinedReviewResponse.report(text, imageID: value.file.id, allowed: allowed, limitations: [], regions: [], uninspected: [], incomplete: false, qualify: grounding.validate)
        #expect(report.claims.count == 1)
        #expect(report.claims.first?.subjectID?.rawValue == "a")
        #expect(report.incomplete)
        #expect(report.limitations.contains { $0.reason.contains("synthesis.observationRequired") })
        let rejected = String(decoding: try JSONEncoder().encode(["claims": [bad]]), as: UTF8.self)
        #expect(throws: ReviewValidationIssue.self) {
            try CombinedReviewResponse.report(rejected, imageID: value.file.id, allowed: allowed, limitations: [], regions: [], uninspected: [], incomplete: false, qualify: grounding.validate)
        }
    }

    @Test func `rejections preserve the failing decoder or guard without copying untrusted text`() throws {
        let crop = #"{"regionID":"region","observations":"Texture visible","uncertainty":"Limited","insufficientEvidence":false}"#
        let cases: [(String, ReviewValidationCode, String)] = [
            ("not JSON", .json, "json.completeObject"),
            ("{}", .schema, "schema.requiredFieldOrType"),
            (crop.replacingOccurrences(of: #""region""#, with: #""wrong""#), .unknownID, "crop.expectedRegionID"),
            (crop.replacingOccurrences(of: "Texture visible", with: "Sharp eye detail"), .unsupportedDomain, "crop.supportedDomain"),
            (crop.replacingOccurrences(of: "Texture visible", with: String(repeating: "x", count: 501)), .responseLength, "text.characterAllowance"),
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
                if code == .schema {
                    #expect(error.issue.fieldPath == "regionID")
                }
            }
        }
        let schema = ReviewValidationIssue.classify(ObjectResponseIssue.invalidSchema("claims.private/path/secret.text"))
        #expect(schema.fieldPath == "claims.text")
        #expect(ReviewValidationIssue.classify(ObjectResponseIssue.invalidSchema("targetIdentified")).fieldPath == "targetIdentified")
        #expect(ReviewValidationIssue.classify(ObjectResponseIssue.invalidSchema("claims.subjectID")).fieldPath == "claims.subjectID")
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

    @Test func `synthesis resolves one subject and rejects swapped or unrelated support`() throws {
        let value = groundedResult()
        let grounding = ReviewSynthesisGrounding(result: value)
        let reference = ReviewEvidenceReference(kind: .observation, id: "crop-a")
        let claim = ReviewClaim(text: "Visible textured surface", type: "detail", evidence: [reference], uncertainty: "Render-dependent", contradictions: [])
        let qualified = try grounding.validate(claim)
        #expect(qualified.subjectID?.rawValue == "a")
        #expect(qualified.regionID?.rawValue == "region-a")
        var swapped = claim
        swapped.subjectID = .init(rawValue: "b")
        #expect(throws: ReviewValidationIssue.self) { try grounding.validate(swapped) }
        swapped = claim; swapped.regionID = .init(rawValue: "region-b")
        #expect(throws: ReviewValidationIssue.self) { try grounding.validate(swapped) }
        let conflict = ReviewClaim(text: claim.text, type: claim.type, evidence: [reference], uncertainty: "Conflict", contradictions: [.init(kind: .observation, id: "crop-b")])
        #expect(throws: ReviewValidationIssue.self) { try grounding.validate(conflict) }
        let mixed = ReviewClaim(text: claim.text, type: claim.type, evidence: [reference, .init(kind: .measurement, id: "metric-b")], uncertainty: "Limited", contradictions: [])
        #expect(throws: ReviewValidationIssue.self) { try grounding.validate(mixed) }
        var otherImage = value
        let origin = ReviewEvidenceProvenance(workID: .init(rawValue: "crop"), imageID: .init(rawValue: "other"), sourceIdentity: "source", renderPolicy: "appearance", compatibility: .init(fields: ["stageVersion": "combined-v7"]), modelIdentity: nil, inputReference: nil)
        otherImage.observations[0] = .init(targetIdentified: true, id: .init(rawValue: "crop-a"), regionID: .init(rawValue: "region-a"), text: "Texture", uncertainty: "Limited", availability: .available, provenance: origin)
        #expect(throws: ReviewValidationIssue.self) { try ReviewSynthesisGrounding(result: otherImage).validate(claim) }
    }

    @Test func `absent unknown and unregistered crop targets cannot establish detail`() throws {
        for target in [Optional(true), Optional(false), nil] {
            var value = groundedResult()
            let original = value.observations[0]
            value.observations[0] = .init(targetIdentified: target, id: original.id, regionID: original.regionID, text: original.text, uncertainty: original.uncertainty, availability: .available, provenance: original.provenance)
            let claim = ReviewClaim(text: "Visible texture", type: "detail", evidence: [.init(kind: .observation, id: "crop-a")], uncertainty: "Limited", contradictions: [])
            if target == true {
                _ = try ReviewSynthesisGrounding(result: value).validate(claim)
            } else {
                #expect(throws: ReviewValidationIssue.self) { try ReviewSynthesisGrounding(result: value).validate(claim) }
            }
            value.subjects[0].registration = nil
            #expect(throws: ReviewValidationIssue.self) { try ReviewSynthesisGrounding(result: value).validate(claim) }
        }
        var overview = result("overview")
        let original = overview.observations[0]
        let origin = ReviewEvidenceProvenance(workID: original.provenance.workID, imageID: overview.file.id, sourceIdentity: "source", renderPolicy: "appearance", compatibility: .init(fields: ["stageVersion": ReviewPipelineContract.stageVersions[.overview]!]), modelIdentity: nil, inputReference: nil)
        overview.observations[0] = .init(id: original.id, regionID: nil, text: "Whole scene in focus", uncertainty: "Limited", availability: .available, provenance: origin)
        let focus = ReviewClaim(text: "Whole scene in focus", type: "composition", evidence: [.init(kind: .observation, id: original.id.rawValue)], uncertainty: "Limited", contradictions: [])
        #expect(throws: ReviewValidationIssue.self) { try ReviewSynthesisGrounding(result: overview).validate(focus) }
        let contradictory = #"{"regionID":"r","observations":"No target visible","uncertainty":"Limited","insufficientEvidence":true,"targetIdentified":true}"#
        #expect(throws: ReviewValidationIssue.self) { try CombinedReviewResponse.inspection(contradictory, regionID: "r") }
    }

    @Test func `numeric summaries preserve distinct subject values and stale evidence abstains`() throws {
        var value = groundedResult()
        let lookup = ReviewSynthesisGrounding(result: value)
        let first = try lookup.measurementSummary(value.measurements[0])
        let second = try lookup.measurementSummary(value.measurements[1])
        #expect(first.contains("Subject a"))
        #expect(first.contains("detail=0.125"))
        #expect(!first.contains("detail=0.875"))
        #expect(second.contains("Subject b"))
        #expect(second.contains("detail=0.875"))
        let metricOnly = ReviewClaim(text: "Visible behavior", type: "composition", evidence: [.init(kind: .measurement, id: "metric-a")], uncertainty: "Limited", contradictions: [])
        #expect(throws: ReviewValidationIssue.self) { try lookup.validate(metricOnly) }
        let transcription = ReviewClaim(text: "Subject detail is 0.875", type: "detail", evidence: [.init(kind: .observation, id: "crop-a")], uncertainty: "Limited", contradictions: [])
        #expect(throws: ReviewValidationIssue.self) { try lookup.validate(transcription) }
        value.measurements[0].scorerVersion = nil
        #expect(throws: ReviewValidationIssue.self) { try ReviewSynthesisGrounding(result: value).measurementSummary(value.measurements[0]) }
        let restored = try JSONDecoder().decode(ReviewClaim.self, from: JSONEncoder().encode(lookup.validate(.init(text: "Visible texture", type: "detail", evidence: [.init(kind: .observation, id: "crop-a")], uncertainty: "Limited", contradictions: []))))
        #expect(restored.subjectID?.rawValue == "a")
    }

    private func groundedResult() -> CombinedReviewResult {
        var value = result("image")
        value.observations = []
        for (id, metric) in [("a", 0.125), ("b", 0.875)] {
            let subjectID = ReviewSubjectID(rawValue: id)
            let regionID = ReviewRegionID(rawValue: "region-" + id)
            let rect = CGRect(x: 0, y: 0, width: 10, height: 10)
            let registration = ReviewMaskRegistration(version: ReviewMaskRegistration.version, sourceIdentity: "source", producerBounds: rect, foregroundBounds: rect, maximumBoundsDisagreementPixels: 0, tolerancePixels: 1, touchesSourceEdge: false, transform: "identity")
            value.subjects.append(.init(registration: registration, id: subjectID, imageID: value.file.id, concept: "bird", normalizedBounds: rect, maskConfidence: 1, aliases: [], maskInputReference: nil, availability: .available))
            value.regions.append(.init(id: regionID, imageID: value.file.id, subjectID: subjectID, sourceIdentity: "source", purpose: "Subject", requestedRect: rect, paddedRect: rect, sourceRect: rect, retainedSourceRect: rect, encoderSize: rect.size, scaleX: 1, scaleY: 1, edgeClipped: false, intendedRegionRetained: true, fidelity: "preview", policy: "appearance", inputReference: nil))
            let provenance = ReviewEvidenceProvenance(workID: .init(rawValue: "crop-" + id), imageID: value.file.id, sourceIdentity: "source", renderPolicy: "appearance", compatibility: .init(fields: ["stageVersion": "combined-v7"]), modelIdentity: nil, inputReference: nil)
            value.observations.append(.init(targetIdentified: true, id: .init(rawValue: "crop-" + id), regionID: regionID, text: "Visible texture", uncertainty: "Limited", availability: .available, provenance: provenance))
            value.measurements.append(.init(scorerVersion: SubjectMaskFocusScorer.semanticsVersion, maskContract: .init(version: SubjectMaskContract.version, channel: .grayscaleIntensity, width: 10, height: 10, sourceIdentity: "source", origin: "top-left-source-raster", polarity: "white-or-opaque-foreground", threshold: 16, interpolation: "none-no-resize"), id: .init(rawValue: "metric-" + id), subjectID: subjectID, values: ["detail": metric], availability: .available, reason: nil, provenance: provenance))
        }
        return value
    }

    private func result(_ id: String) -> CombinedReviewResult {
        let imageID = ReviewImageID(rawValue: id)
        var value = CombinedReviewResult(file: .init(id: imageID, fileID: UUID(), url: URL(filePath: "/fixture"), displayName: "Fixture", fingerprint: id))
        value.observations = [.init(id: .init(rawValue: id + "-observation"), regionID: nil, text: "Visible composition", uncertainty: "Limited", availability: .available,
                                    provenance: .init(workID: .init(rawValue: "overview"), imageID: imageID, sourceIdentity: id, renderPolicy: "appearance", compatibility: .init(fields: ["stageVersion": ReviewPipelineContract.stageVersions[.overview]!]), modelIdentity: nil, inputReference: nil))]
        return value
    }
}
