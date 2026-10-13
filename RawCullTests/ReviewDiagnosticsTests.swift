import CoreGraphics
import Foundation
@testable import RawCull
import Testing

@Suite("Bounded review diagnostics", .tags(.smoke))
struct ReviewDiagnosticsTests {
    @Test func `twelve recorded optional schema failures retain core discovery without inventing priority`() throws {
        struct Fixture: Decodable { let stage: String; let response: String }
        struct Core: Decodable { let observations: String; let uncertainty: String }
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        let fixtures = try JSONDecoder().decode([Fixture].self, from: Data(contentsOf: root.appendingPathComponent("Docs/CombinedReviewRegression/schema-responses-v9.json")))
        let overviews = fixtures.filter { $0.stage == "overview" }
        #expect(overviews.count == 12)
        for fixture in overviews {
            let core = try JSONDecoder().decode(Core.self, from: Data(fixture.response.utf8))
            let value = try CombinedReviewResponse.overview(fixture.response)
            #expect(value.observations == core.observations)
            #expect(value.uncertainty == core.uncertainty)
            #expect(!value.concepts.isEmpty)
            #expect(value.validationNotes?.contains { $0.contains("overview.optionalSchema") } == true)
            #expect(value.primarySubjects?.allSatisfy { value.concepts.contains($0.concept) && $0.location == nil } == true)
            #expect(value.contextualConcepts?.allSatisfy(value.concepts.contains) == true)
            let encoded = try JSONEncoder().encode(value)
            #expect(try JSONDecoder().decode(CombinedReviewOverview.self, from: encoded).validationNotes == value.validationNotes)
        }
    }

    @Test func `optional shapes are isolated independently while malformed core still fails`() throws {
        let core = #"{"observations":"Bird on fence","uncertainty":"Limited","concepts":[{"query":"bird","displayName":"Bird","reason":"Visible"}]"#
        let validPrimary = #""primarySubjects":[{"concept":"bird","reason":"Main"}]"#
        let validContext = #""contextualConcepts":["bird"]"#
        for shape in [#"["bird"]"#, #"["bird",{"concept":"bird","reason":"Main"}]"#, "42", #"{"concept":"bird"}"#, #"[{"concept":"bird","location":{"x":"bad","y":0.5}}]"#] {
            let value = try CombinedReviewResponse.overview(core + ",\"primarySubjects\":" + shape + "," + validContext + "}")
            #expect(value.primarySubjects?.isEmpty == true)
            #expect(value.contextualConcepts == ["bird"])
            #expect(value.validationNotes?.contains { $0.contains("malformed primarySubjects") } == true)
        }
        for shape in [#"[{"query":"bird"}]"#, #"["bird",{"query":"bird"}]"#, "false", #""bird""#] {
            let value = try CombinedReviewResponse.overview(core + "," + validPrimary + ",\"contextualConcepts\":" + shape + "}")
            #expect(value.primarySubjects?.first?.concept == "bird")
            #expect(value.contextualConcepts?.isEmpty == true)
            #expect(value.validationNotes?.contains { $0.contains("malformed contextualConcepts") } == true)
        }
        for suffix in ["}", #", "primarySubjects":null, "contextualConcepts":null}"#, #", "primarySubjects":[], "contextualConcepts":[]}"#] {
            #expect(try CombinedReviewResponse.overview(core + suffix).validationNotes?.isEmpty == true)
        }
        let badOptional = core + #", "primarySubjects":["bird"]}"#
        #expect(throws: (any Error).self) { try CombinedReviewResponse.overview(badOptional.replacingOccurrences(of: #""observations":"Bird on fence""#, with: #""observations":42"#)) }
        #expect(throws: (any Error).self) { try CombinedReviewResponse.overview(badOptional.replacingOccurrences(of: "Limited", with: String(repeating: "x", count: 501))) }
        #expect(throws: (any Error).self) { try CombinedReviewResponse.overview(badOptional.replacingOccurrences(of: #""query":"bird""#, with: #""query":null"#)) }
    }

    @Test func `recorded fox report defaults only absent contradictions and retains supported lighting`() throws {
        struct Fixture: Decodable { let stage: String; let response: String }
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        let fixtures = try JSONDecoder().decode([Fixture].self, from: Data(contentsOf: root.appendingPathComponent("Docs/CombinedReviewRegression/schema-responses-v9.json")))
        let fox = try #require(fixtures.first { $0.stage == "report" })
        var value = result("fox")
        let original = value.observations[0]
        struct Recorded: Decodable { let claims: [ReviewClaim] }
        let lighting = try #require(ObjectJSONEnvelope.decode(Recorded.self, from: fox.response).claims.first { ["lighting", "exposure"].contains($0.type) })
        value.observations[0] = .init(id: .init(rawValue: "o1"), regionID: nil, text: lighting.text, uncertainty: original.uncertainty, availability: original.availability, provenance: original.provenance)
        let allowed: Set<ReviewEvidenceReference> = [.init(kind: .observation, id: "o1")]
        let report = try CombinedReviewResponse.report(fox.response, imageID: value.file.id, allowed: allowed, limitations: [], regions: [], uninspected: [], incomplete: true, qualify: ReviewSynthesisGrounding(result: value).validate)
        #expect(report.claims.count == 1)
        #expect(report.claims.first?.type == "exposure")
        #expect(report.claims.first?.contradictions.isEmpty == true)
        #expect(report.limitations.count == 3)
        let claim = #"{"text":"Soft light","type":"exposure","evidence":[{"kind":"observation","id":"o1"}],"uncertainty":"Limited""#
        for malformed in ["null", "42", #""none""#, "[{}]"] {
            #expect(throws: (any Error).self) { try JSONDecoder().decode(ReviewClaim.self, from: Data((claim + ",\"contradictions\":" + malformed + "}").utf8)) }
        }
        let unknown = claim + #", "contradictions":[{"kind":"observation","id":"unknown"}]}"#
        #expect(throws: (any Error).self) { try CombinedReviewResponse.report(#"{"claims":["# + unknown + "]}", imageID: value.file.id, allowed: allowed, limitations: [], regions: [], uninspected: [], incomplete: true) }
        let roundtrip = try JSONDecoder().decode(ReviewClaim.self, from: JSONEncoder().encode(report.claims[0]))
        #expect(roundtrip.contradictions.isEmpty)
    }

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
        let claim = ReviewClaim(text: "Visible texture", type: "detail", evidence: [reference], uncertainty: "Render-dependent", contradictions: [])
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
        let origin = ReviewEvidenceProvenance(workID: .init(rawValue: "crop"), imageID: .init(rawValue: "other"), sourceIdentity: "source", renderPolicy: "appearance", compatibility: .init(fields: ["stageVersion": ReviewPipelineContract.stageVersions[.cropObservation]!]), modelIdentity: nil, inputReference: nil)
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
        // Species uncertainty must not override explicit generic-target support.
        let visibleUnknownSpecies = #"{"regionID":"r","observations":"A small brown bird perches on a wire fence.","uncertainty":"Species identity is unverified.","insufficientEvidence":false,"targetIdentified":true}"#
        #expect(try CombinedReviewResponse.inspection(visibleUnknownSpecies, regionID: "r").targetIdentified == true)
        // Replay the supplied runs' negative flag without upgrading it from the prose.
        let retainedNegative = #"{"regionID":"r","observations":"A small brown bird perches on a wire fence.","uncertainty":"The bird's identity is not clearly verifiable due to low resolution and partial visibility.","insufficientEvidence":false,"targetIdentified":false}"#
        #expect(try CombinedReviewResponse.inspection(retainedNegative, regionID: "r").targetIdentified == false)
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

    @Test func `texture alias still requires one qualified subject crop`() throws {
        let value = groundedResult()
        let references: Set<ReviewEvidenceReference> = [.init(kind: .observation, id: "crop-a"), .init(kind: .observation, id: "crop-b")]
        func report(_ ids: [String]) throws -> ReviewImageReport {
            let claim = ReviewClaim(text: "Visible texture", type: "texture", evidence: ids.map { .init(kind: .observation, id: $0) }, uncertainty: "Limited", contradictions: [])
            let data = try JSONEncoder().encode(["claims": [claim]])
            return try CombinedReviewResponse.report(String(decoding: data, as: UTF8.self), imageID: value.file.id, allowed: references, limitations: [], regions: [], uninspected: [], incomplete: false, qualify: ReviewSynthesisGrounding(result: value).validate)
        }
        let accepted = try report(["crop-a"])
        #expect(accepted.claims.first?.type == "detail")
        #expect(accepted.claims.first?.subjectID?.rawValue == "a")
        #expect(!accepted.incomplete)
        #expect(throws: ReviewValidationIssue.self) { try report(["crop-a", "crop-b"]) }

        // The v13 foal report combined two crops for detail. Preserve its scene claim,
        // but never salvage detail by dropping one cited subject or changing the prose.
        let scene = ReviewClaim(text: "Two subjects in a grassy field", type: "composition", evidence: references.sorted { $0.id < $1.id }, uncertainty: "Limited", contradictions: [])
        let multiCrop = ReviewClaim(text: "The coats and grass have visible texture", type: "detail", evidence: scene.evidence, uncertainty: "Limited", contradictions: [])
        let mixedData = try JSONEncoder().encode(["claims": [scene, multiCrop]])
        let partial = try CombinedReviewResponse.report(String(decoding: mixedData, as: UTF8.self), imageID: value.file.id, allowed: references, limitations: [], regions: [], uninspected: [], incomplete: false, qualify: ReviewSynthesisGrounding(result: value).validate)
        #expect(partial.claims.map(\.type) == ["composition"])
        #expect(partial.incomplete)
        #expect(partial.limitations.contains { $0.reason.contains("synthesis.targetCropRequired") })

        // Real Qwen sometimes emits short IDs instead of reference objects.
        let shorthand = #"{"claims":[{"text":"Visible texture","type":"texture","evidence":["crop-a"],"uncertainty":"Limited","contradictions":[]}]}"#
        func decode(_ response: String, allowed: Set<ReviewEvidenceReference>? = nil) throws -> ReviewImageReport {
            try CombinedReviewResponse.report(response, imageID: value.file.id, allowed: allowed ?? references, limitations: [], regions: [], uninspected: [], incomplete: false, qualify: ReviewSynthesisGrounding(result: value).validate)
        }
        let normalized = try decode(shorthand)
        #expect(normalized.claims.first?.evidence == [.init(kind: .observation, id: "crop-a")])
        #expect(normalized.claims.first?.subjectID?.rawValue == "a")
        #expect(throws: ReviewValidationIssue.self) { try decode(shorthand.replacingOccurrences(of: "crop-a", with: "unknown")) }
        #expect(throws: ReviewValidationIssue.self) { try decode(shorthand, allowed: references.union([.init(kind: .measurement, id: "crop-a")])) }
        #expect(throws: ReviewValidationIssue.self) { try decode(shorthand, allowed: [.init(kind: .measurement, id: "crop-a")]) }
        #expect(throws: (any Error).self) { try decode(shorthand.replacingOccurrences(of: #""contradictions":[]"#, with: #""contradictions":null"#)) }
        // Persisted claims retain the strict schema, without request-local aliases.
        #expect(throws: (any Error).self) { try JSONDecoder().decode(ReviewClaim.self, from: Data(#"{"text":"Texture","type":"detail","evidence":["crop-a"],"uncertainty":"Limited"}"#.utf8)) }
    }

    @Test func `prompt eligibility excludes unidentified crops and measurements from detail`() throws {
        var value = groundedResult()
        let original = value.observations[0]
        for target in [Optional(true), Optional(false), nil] {
            value.observations[0] = .init(targetIdentified: target, id: original.id, regionID: original.regionID, text: original.text, uncertainty: original.uncertainty, availability: original.availability, provenance: original.provenance)
            let support = try ReviewSynthesisGrounding(result: value).support(.init(kind: .observation, id: "crop-a"))
            #expect(support.subjectDetailSupported == (target == true))
            #expect(support.claimTypes.contains("detail") == (target == true))
        }
        let metric = try ReviewSynthesisGrounding(result: value).support(.init(kind: .measurement, id: "metric-a"))
        #expect(metric.claimTypes == "none")
        #expect(!metric.subjectDetailSupported)
    }

    @Test func `v14 technical claims cannot exceed their cited observation`() throws {
        let cases: [(String, String, String)] = [
            ("A brown foal grazes in a grassy field under warm, golden light.", "The grassy field has a textured surface with visible blades and yellow wildflowers.", "detail"),
            ("A red fox in motion, with visible fur texture and a bushy tail.", "The fur texture of the fox is detailed, with visible individual hairs.", "detail"),
            ("A puffin in mid-flight, showing textured feathers.", "The puffin's wings and beak are in focus.", "visibility"),
            ("A squirrel perched on a post with a blurred background.", "The squirrel is in focus.", "visibility"),
            ("A puffin with textured feathers against a gray background.", "Low resolution and motion blur.", "exposure"),
            ("The subject is not in focus.", "The subject is in focus.", "visibility"),
            ("The subject is not sharp.", "sharp", "detail"),
            ("The lighting is not bright.", "bright", "exposure")
        ]
        for (observation, text, type) in cases {
            var value = groundedResult()
            let original = value.observations[0]
            value.observations[0] = .init(targetIdentified: true, id: original.id, regionID: original.regionID, text: observation, uncertainty: "Limited", availability: .available, provenance: original.provenance)
            let claim = ReviewClaim(text: text, type: type, evidence: [.init(kind: .observation, id: "crop-a")], uncertainty: "Limited", contradictions: [])
            #expect(throws: ReviewValidationIssue.self) { try ReviewSynthesisGrounding(result: value).validate(claim) }
        }
    }

    @Test func `technical excerpts preserve support and missing texture abstains`() throws {
        var value = groundedResult()
        let original = value.observations[0]
        func observe(_ text: String) {
            value.observations[0] = .init(targetIdentified: true, id: original.id, regionID: original.regionID, text: text, uncertainty: "Limited", availability: .available, provenance: original.provenance)
        }
        observe("A fox. Visible fur texture. Bright sunlight.")
        for (text, type) in [("visible fur texture", "detail"), ("Bright sunlight", "exposure")] {
            let claim = ReviewClaim(text: text, type: type, evidence: [.init(kind: .observation, id: "crop-a")], uncertainty: "Limited", contradictions: [])
            #expect(try ReviewSynthesisGrounding(result: value).validate(claim).subjectID?.rawValue == "a")
        }
        observe("A brown foal grazes in a grassy field.")
        let support = try ReviewSynthesisGrounding(result: value).support(.init(kind: .observation, id: "crop-a"))
        #expect(!support.subjectDetailSupported)
        #expect(!support.claimTypes.contains("detail"))
        #expect(!support.claimTypes.contains("exposure"))
    }

    @Test func `criterion crops require nullable strings and keep anatomy outside observations`() throws {
        let good = #"{"regionID":"r","criteria":{"composition":"Subject left of center.","exposure":"Soft illumination.","visibility":"Subject partly occluded.","detail":null},"uncertainty":"Limited texture.","targetIdentified":true}"#
        let parsed = try CombinedReviewResponse.inspection(good, regionID: "r", requireCriteria: true)
        #expect(parsed.criteria?.exposure.supported == true)
        #expect(parsed.criteria?.detail.supported == false)
        #expect(!parsed.observations.contains("Limited texture"))
        for invalid in [
            good.replacingOccurrences(of: "Soft illumination.", with: "A bird against a light sky."),
            good.replacingOccurrences(of: "Subject partly occluded.", with: "Species identity unknown."),
            good.replacingOccurrences(of: "Subject partly occluded.", with: "Subject left of center."),
            good.replacingOccurrences(of: "Subject partly occluded.", with: "A yellow eye is visible."),
            good.replacingOccurrences(of: #""detail":null"#, with: #""detail":"""#),
            good.replacingOccurrences(of: #","detail":null"#, with: "")
        ] {
            #expect(throws: (any Error).self) { try CombinedReviewResponse.inspection(invalid, regionID: "r", requireCriteria: true) }
        }
        let legacy = #"{"regionID":"r","observations":"Visible texture","uncertainty":"Limited","insufficientEvidence":false,"targetIdentified":true}"#
        #expect(throws: (any Error).self) { try CombinedReviewResponse.inspection(legacy, regionID: "r", requireCriteria: true) }
    }

    @Test func `criterion grounding prevents repeated prose and uncertainty becoming evidence`() throws {
        var value = groundedResult()
        let original = value.observations[0]
        let entry: (String) -> ReviewCriterionObservation = { .init(supported: true, text: $0) }
        let criteria = ReviewCriterionObservations(composition: entry("Subject left of center."), exposure: entry("Soft illumination."),
                                                   visibility: entry("Subject partly occluded."), detail: entry("Coarse fur strands are resolved."))
        value.observations[0] = .init(targetIdentified: true, criteria: criteria, id: original.id, regionID: original.regionID, text: "General subject scene.", uncertainty: "Species identity unknown.", availability: .available, provenance: original.provenance)
        let grounding = ReviewSynthesisGrounding(result: value)
        for type in ReviewCriterionObservations.types {
            let claim = ReviewClaim(text: criteria[type]!.text, type: type, evidence: [.init(kind: .observation, id: "crop-a")], uncertainty: "Limited", contradictions: [])
            #expect(try grounding.validate(claim).subjectID?.rawValue == "a")
        }
        for (text, type) in [("Subject left of center.", "exposure"), ("Soft illumination.", "visibility"), ("Species identity unknown.", "visibility"), ("General subject scene.", "detail")] {
            let claim = ReviewClaim(text: text, type: type, evidence: [.init(kind: .observation, id: "crop-a")], uncertainty: "Limited", contradictions: [])
            #expect(throws: ReviewValidationIssue.self) { try grounding.validate(claim) }
        }
        let restored = try JSONDecoder().decode(ReviewObservation.self, from: JSONEncoder().encode(value.observations[0]))
        #expect(restored.criteria?.detail.text == "Coarse fur strands are resolved.")
    }

    @Test func `criterion background blur uses its exact registered criterion boundary`() throws {
        var value = groundedResult()
        let original = value.observations[0]
        let visibility = "squirrel fully visible, no occlusion, clear outline against blurred background"
        let criteria = ReviewCriterionObservations(
            composition: .init(supported: true, text: "Subject beside a fence"),
            exposure: .init(supported: true, text: "Soft lighting"),
            visibility: .init(supported: true, text: visibility),
            detail: .init(supported: false, text: ""))
        value.observations[0] = .init(targetIdentified: true, criteria: criteria, id: original.id,
            regionID: original.regionID, text: "Subject beside a fence Soft lighting " + visibility,
            uncertainty: "", availability: .available, provenance: original.provenance)
        let claim = ReviewClaim(text: visibility, type: "visibility", evidence: [.init(kind: .observation, id: "crop-a")], uncertainty: "", contradictions: [])
        #expect(try ReviewSynthesisGrounding(result: value).validate(claim).subjectID?.rawValue == "a")
        value.observations[0] = .init(targetIdentified: false, criteria: criteria, id: original.id,
            regionID: original.regionID, text: visibility, uncertainty: "", availability: .available, provenance: original.provenance)
        #expect(throws: ReviewValidationIssue.self) { try ReviewSynthesisGrounding(result: value).validate(claim) }
    }

    @Test func `crop repairs address target consistency and length without accepting invalid evidence`() throws {
        let response = #"{"regionID":"r","criteria":{"composition":"Subject left of center","exposure":"Soft lighting","visibility":"Subject visible","detail":"No texture resolved"},"uncertainty":"Species unknown","targetIdentified":false}"#
        #expect(throws: ReviewValidationIssue.self) { try CombinedReviewResponse.inspection(response, regionID: "r", requireCriteria: true) }
        let corrected = response.replacingOccurrences(of: #""No texture resolved""#, with: "null")
        #expect(try CombinedReviewResponse.inspection(corrected, regionID: "r", requireCriteria: true).targetIdentified == false)
        for check in ["crop.criterionTargetConsistency", "crop.criterionLength"] {
            let issue = ReviewValidationIssue(check == "crop.criterionLength" ? .responseLength : .grounding, check, field: "criteria")
            #expect(CombinedReviewResponse.canRepair(issue))
            #expect(!CombinedReviewResponse.repairInstruction(for: issue).contains("supported/text objects"))
        }
        #expect(!CombinedReviewResponse.canRepair(.init(.grounding, "synthesis.criterionObservation", field: "claims.text")))
        struct Fixture: Decodable { let response: String; let regionID: String; let check: String }
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        let fixtures = try JSONDecoder().decode([Fixture].self, from: Data(contentsOf: root.appendingPathComponent("Docs/CombinedReviewRegression/crop-responses-v17.json")))
        #expect(fixtures.count == 11)
        for fixture in fixtures {
            do {
                _ = try CombinedReviewResponse.inspection(fixture.response, regionID: fixture.regionID, requireCriteria: true)
                Issue.record("Invalid v17 evidence accepted")
            } catch let issue as ReviewValidationIssue {
                #expect(issue.check == fixture.check)
                #expect(CombinedReviewResponse.canRepair(issue))
            }
        }
    }

    @Test func `partial crop validation preserves siblings and persists detail abstention`() throws {
        struct Fixture: Decodable { let response: String; let regionID: String }
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        let fixtures = try JSONDecoder().decode([Fixture].self, from: Data(contentsOf: root.appendingPathComponent("Docs/CombinedReviewRegression/crop-responses-v18.json")))
        #expect(fixtures.count == 12)
        for fixture in fixtures {
            if fixture.regionID == "2c62fe40596e502ec75ea945f525c8dc5ac45855cf633f665ab163835be2d80e" {
                #expect(throws: (any Error).self) { try CombinedReviewResponse.inspection(fixture.response, regionID: fixture.regionID, requireCriteria: true, preserveValidCriteria: true) }
                continue
            }
            let parsed = try CombinedReviewResponse.inspection(fixture.response, regionID: fixture.regionID, requireCriteria: true, preserveValidCriteria: true)
            #expect(parsed.criteria?.composition.supported == true || parsed.criteria?.exposure.supported == true)
            #expect(parsed.criteria?.detail.supported == false)
            #expect(!(parsed.validationNotes ?? []).isEmpty)
            let restored = try JSONDecoder().decode(CombinedReviewInspection.self, from: JSONEncoder().encode(parsed))
            #expect(restored.validationNotes == parsed.validationNotes)
            #expect(restored.criteria?.detail.text == "")
            #expect(throws: (any Error).self) { try CombinedReviewResponse.inspection(fixture.response, regionID: "wrong", requireCriteria: true, preserveValidCriteria: true) }
        }
        let bad = #"{"regionID":"r","criteria":{"composition":"","exposure":"","visibility":"","detail":""},"uncertainty":"","targetIdentified":false}"#
        #expect(throws: (any Error).self) { try CombinedReviewResponse.inspection(bad, regionID: "r", requireCriteria: true, preserveValidCriteria: true) }
        #expect(throws: (any Error).self) { try CombinedReviewResponse.inspection("{}", regionID: "r", requireCriteria: true, preserveValidCriteria: true) }
    }

    @Test func `row selections assemble exact evidence and abstain on wrong category IDs`() throws {
        let image = ReviewImageID(rawValue: "image")
        let composition = ReviewClaim(text: "Subject beside a fence", type: "composition", evidence: [.init(kind: .observation, id: "stored-crop")], uncertainty: "", contradictions: [])
        let exposure = ReviewClaim(text: "Soft lighting", type: "exposure", evidence: [.init(kind: .observation, id: "stored-light")], uncertainty: "", contradictions: [])
        let candidates = ["composition": ["o2": composition], "exposure": ["o3": exposure]]
        func parse(_ text: String) throws -> ReviewImageReport {
            try CombinedReviewResponse.selectedReport(text, imageID: image, candidates: candidates, limitations: [], regions: [], uninspected: [], incomplete: false)
        }
        let good = #"{"composition":"o2","exposure":"o3","visibility":null,"detail":null}"#
        let report = try parse(good)
        #expect(report.claims.map(\.text) == [composition.text, exposure.text])
        #expect(report.claims[0].evidence == composition.evidence)
        #expect(Set(report.claims.map(\.type)).count == report.claims.count)
        let partial = try parse(good.replacingOccurrences(of: #""exposure":"o3""#, with: #""exposure":"o2""#))
        #expect(partial.claims.count == 1)
        #expect(partial.incomplete)
        #expect(partial.limitations.first?.reason.contains("eligibleCriterionRow") == true)
        #expect(try parse(#"{"composition":null,"exposure":null,"visibility":null,"detail":null}"#).claims.isEmpty)
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        let oldReports = try JSONDecoder().decode([String].self, from: Data(contentsOf: root.appendingPathComponent("Docs/CombinedReviewRegression/report-responses-v19.json")))
        #expect(!oldReports.isEmpty)
        for response in oldReports {
            #expect(throws: (any Error).self) { try parse(response) }
        }
        for bad in [#"{"composition":"invented","exposure":null,"visibility":null,"detail":null}"#,
                    #"{"composition":"o2"}"#,
                    #"{"claims":[{"text":"Borrowed prose","type":"composition"}]}"#] {
            #expect(throws: (any Error).self) { try parse(bad) }
        }
    }

    @Test func `invalid selections recover validated priority rows without overriding null abstention`() throws {
        let exposure = ReviewClaim(text: "Soft lighting", type: "exposure", evidence: [.init(kind: .observation, id: "stored-light")], uncertainty: "", contradictions: [])
        let composition = ReviewClaim(text: "Subject beside a fence", type: "composition", evidence: [.init(kind: .observation, id: "stored-crop")], uncertainty: "", contradictions: [])
        let candidates = ["exposure": ["o3": exposure], "composition": ["o2": composition]]
        func parse(_ response: String, preferred: [String: String]) throws -> ReviewImageReport {
            try CombinedReviewResponse.selectedReport(response, imageID: .init(rawValue: "image"), candidates: candidates,
                limitations: [], regions: [], uninspected: [], incomplete: false, preferredRows: preferred)
        }
        let wrong = #"{"composition":"o2","exposure":"o2,o3","visibility":null,"detail":"o3"}"#
        let recovered = try parse(wrong, preferred: ["exposure": "o3", "detail": "o3"])
        #expect(recovered.claims.count == 2)
        #expect(recovered.claims.last?.text == exposure.text)
        #expect(recovered.claims.last?.evidence == exposure.evidence)
        #expect(recovered.incomplete)
        #expect(recovered.limitations.contains { $0.id.rawValue == "image:selection-fallback:exposure" && $0.relatedEvidence == exposure.evidence })
        #expect(!recovered.claims.contains { $0.type == "detail" })
        #expect(try parse(wrong, preferred: ["exposure": "invented"]).claims.count == 1)
        #expect(throws: ReviewValidationIssue.self) { try parse(wrong.replacingOccurrences(of: #""composition":"o2""#, with: #""composition":"invented""#), preferred: ["exposure": "o3"]) }
        let abstention = try parse(#"{"composition":null,"exposure":null,"visibility":null,"detail":null}"#, preferred: ["exposure": "o3"])
        #expect(abstention.claims.isEmpty)
        #expect(abstention.limitations.isEmpty)
    }

    @Test func `null criteria preserve explicit abstention without contradictory flags`() throws {
        let response = #"{"regionID":"r","criteria":{"composition":null,"exposure":null,"visibility":null,"detail":null},"uncertainty":"","targetIdentified":true}"#
        let parsed = try CombinedReviewResponse.inspection(response, regionID: "r", requireCriteria: true)
        #expect(parsed.insufficientEvidence)
        #expect(parsed.targetIdentified == true)
        #expect(parsed.observations.isEmpty)
        #expect(parsed.criteria?.detail.supported == false)
        let wire = ReviewNullableCriteria(composition: nil, exposure: nil, visibility: nil, detail: nil)
        let roundTrip = try JSONDecoder().decode(ReviewNullableCriteria.self, from: JSONEncoder().encode(wire))
        #expect(roundTrip.detail == nil)
        #expect(throws: (any Error).self) { try CombinedReviewResponse.inspection(response.replacingOccurrences(of: #","detail":null"#, with: ""), regionID: "r", requireCriteria: true) }
    }

    @Test func `v16 rejected responses stay rejected and receive stage specific feedback`() throws {
        struct Fixture: Decodable { let stage: String; let regionID: String?; let response: String }
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        let fixtures = try JSONDecoder().decode([Fixture].self, from: Data(contentsOf: root.appendingPathComponent("Docs/CombinedReviewRegression/schema-responses-v16.json")))
        #expect(fixtures.count == 4)
        for fixture in fixtures {
            if fixture.stage == "crop" {
                #expect(throws: (any Error).self) { try CombinedReviewResponse.inspection(fixture.response, regionID: fixture.regionID!, requireCriteria: true) }
            } else {
                #expect(throws: (any Error).self) { try CombinedReviewResponse.report(fixture.response, imageID: .init(rawValue: "image"), allowed: [.init(kind: .observation, id: "o1")], limitations: [], regions: [], uninspected: [], incomplete: false) }
            }
        }
        let crop = CombinedReviewResponse.repairInstruction(for: .init(.schema, "schema.requiredFieldOrType", field: "criteria.composition"))
        #expect(crop.contains("string or null"))
        #expect(crop.contains("No supported/text objects"))
        let report = CombinedReviewResponse.repairInstruction(for: .init(.schema, "schema.requiredFieldOrType", field: "claims.text"))
        #expect(report.contains("text STRING"))
        #expect(report.contains("evidence ARRAY"))
        #expect(!report.contains("criterion text"))
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
            let provenance = ReviewEvidenceProvenance(workID: .init(rawValue: "crop-" + id), imageID: value.file.id, sourceIdentity: "source", renderPolicy: "appearance", compatibility: .init(fields: ["stageVersion": ReviewPipelineContract.stageVersions[.cropObservation]!]), modelIdentity: nil, inputReference: nil)
            value.observations.append(.init(targetIdentified: true, id: .init(rawValue: "crop-" + id), regionID: regionID, text: "Visible texture. Soft illumination.", uncertainty: "Limited", availability: .available, provenance: provenance))
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
