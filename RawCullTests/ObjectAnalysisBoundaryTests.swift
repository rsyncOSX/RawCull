import Foundation
import PhotoAIContracts
@testable import RawCull
import Testing

@Suite("Object analysis boundary", .tags(.smoke))
struct ObjectAnalysisBoundaryTests {
    @Test(arguments: [(0, 1), (2, 1)])
    func `Retry feedback names mismatched claim counts and missing focus evidence`(counts: (Int, Int)) throws {
        let response = #"{"schemaVersion":2,"objects":[{"id":"1","concept":"bird","description":"Visible bird","visibility":"clear","focusQuality":"soft","focusEvidence":null,"expression":null,"obstructions":[],"strengths":[],"strengthEvidence":[],"problems":[],"problemEvidence":[],"confidence":0.8}],"relationships":[],"strengths":[],"problems":[],"preferredObjectIDs":[],"confidence":0.8}"#
        var document = try #require(JSONSerialization.jsonObject(with: Data(response.utf8)) as? [String: Any])
        var objects = try #require(document["objects"] as? [[String: Any]])
        objects[0]["strengths"] = (0..<counts.0).map { "Visible strength \($0)" }
        objects[0]["strengthEvidence"] = (0..<counts.1).map { _ in ["cropID": "1", "observation": "Visible subject contrast"] }
        document["objects"] = objects
        let invalid = String(decoding: try JSONSerialization.data(withJSONObject: document), as: UTF8.self)
        #expect(throws: ObjectResponseIssue.self) {
            try ObjectAnalysisResponseDecoder.decode(invalid, boardIDs: ["1"])
        }
        let feedback = RawCullObjectAnalysisFeature.assessmentValidationFeedback(invalid, fallback: "Generic failure")
        #expect(feedback.contains("strengths has \(counts.0) items but strengthEvidence has \(counts.1)"))
        #expect(feedback.contains("focusQuality is soft, so focusEvidence cannot be null"))
        #expect(feedback.contains("do not invent evidence"))
    }

    @Test func `Schema feedback preserves original error for undecodable output`() {
        #expect(RawCullObjectAnalysisFeature.assessmentValidationFeedback("{", fallback: "Incomplete JSON") == "Incomplete JSON")
    }

    @Test func `Focus and claims require their own crop evidence and unverified expression abstains`() throws {
        let response = #"{"schemaVersion":2,"objects":[{"id":"1","concept":"bird","description":"Visible bird","visibility":"clear","focusQuality":"sharp","focusEvidence":{"cropID":"1","observation":"subject feather edges are crisp"},"expression":null,"obstructions":[],"strengths":["resolved texture"],"strengthEvidence":[{"cropID":"1","observation":"subject feather texture resolved"}],"problems":[],"problemEvidence":[],"confidence":0.8}],"relationships":[],"strengths":[],"problems":[],"preferredObjectIDs":["1"],"confidence":0.8}"#
        #expect(try ObjectAnalysisResponseDecoder.decode(response, boardIDs: ["1"]).objects[0].focusEvidence?.cropID == "1")
        for invalid in [
            response.replacingOccurrences(of: "\"cropID\":\"1\"", with: "\"cropID\":\"2\""),
            response.replacingOccurrences(of: "subject feather edges are crisp", with: "subject feather edges are smeared"),
            response.replacingOccurrences(of: "Visible bird", with: "The subject is blurred"),
            response.replacingOccurrences(of: "\"expression\":null", with: "\"expression\":\"alert\""),
            response.replacingOccurrences(of: "\"schemaVersion\":2", with: "\"schemaVersion\":1"),
            response.replacingOccurrences(of: "\"strengths\":[\"resolved texture\"]", with: "\"strengths\":[]")
        ] {
            #expect(throws: ObjectResponseIssue.self) { try ObjectAnalysisResponseDecoder.decode(invalid, boardIDs: ["1"]) }
        }
        #expect(throws: ObjectResponseIssue.self) {
            try ObjectAnalysisResponseDecoder.decode(response, boardIDs: ["1"], expectedConcepts: ["1": "fence"])
        }
        let background = response.replacingOccurrences(of: "Visible bird", with: "Visible bird with blurred background")
        #expect(try ObjectAnalysisResponseDecoder.decode(background, boardIDs: ["1"]).objects[0].focusQuality == .sharp)
        let uncertain = response.replacingOccurrences(of: "\"focusQuality\":\"sharp\",\"focusEvidence\":{\"cropID\":\"1\",\"observation\":\"subject feather edges are crisp\"}", with: "\"focusQuality\":\"uncertain\",\"focusEvidence\":null")
        #expect(try ObjectAnalysisResponseDecoder.decode(uncertain, boardIDs: ["1"]).objects[0].focusQuality == .uncertain)
    }

    @Test func `Automatic concepts normalize and deduplicate`() throws {
        let response = #"{"concepts":[{"query":"  Musk   Ox  ","displayName":"Musk Ox","reason":"Main subject"},{"query":"musk ox","displayName":"Musk ox","reason":"Duplicate"},{"query":"bird","displayName":"Bird","reason":"On branch"}]}"#
        let concepts = try ObjectConceptDiscovery.decode(response)
        #expect(concepts.map(\.concept.cacheIdentifier) == ["musk ox", "bird"])
    }

    @Test func `Invalid discovery is surfaced`() {
        #expect(throws: ObjectResponseIssue.invalidJSON) {
            try ObjectConceptDiscovery.decode("not JSON")
        }
        #expect(throws: ObjectResponseIssue.invalidValue("concept")) {
            try ObjectConceptDiscovery.decode(#"{"concepts":[{"query":"bird\ncar","displayName":"Bird","reason":"Visible"}]}"#)
        }
    }

    @Test func `Manual concepts reject empty entries`() throws {
        #expect(try ObjectConceptDiscovery.parseManual("bird, musk ox, BIRD").map(\.query) == ["bird", "musk ox"])
        #expect(throws: ObjectAnalysisError.self) {
            try ObjectConceptDiscovery.parseManual("bird,,car")
        }
    }

    @Test func `Assessment accepts only rendered object IDs`() throws {
        let response = #"{"schemaVersion":2,"imageSummary":"Two birds","objects":[{"id":"1","concept":"bird","description":"Near bird","visibility":"clear","focusQuality":"sharp","focusEvidence":{"cropID":"1","observation":"subject feather edges are crisp"},"strengthEvidence":[{"cropID":"1","observation":"subject feather texture is visible"}],"problemEvidence":[],"expression":null,"obstructions":[],"strengths":["detail"],"problems":[],"confidence":0.9}],"relationships":[],"strengths":[],"problems":[],"preferredObjectIDs":["1"],"confidence":0.8}"#
        #expect(try ObjectAnalysisResponseDecoder.decode(response, boardIDs: ["1"]).objects[0].id == "1")
        #expect(throws: ObjectResponseIssue.unknownID("1")) {
            try ObjectAnalysisResponseDecoder.decode(response, boardIDs: ["2"])
        }
        let duplicate = response.replacingOccurrences(of: "\"preferredObjectIDs\":[\"1\"]", with: "\"preferredObjectIDs\":[\"1\",\"1\"]")
        #expect(throws: ObjectResponseIssue.duplicateID("1")) {
            try ObjectAnalysisResponseDecoder.decode(duplicate, boardIDs: ["1"])
        }
    }

    @Test func `Wrapped JSON remains strict`() throws {
        let concepts = "```json\n{\"concepts\":[{\"query\":\"bird\",\"displayName\":\"Bird\",\"reason\":\"Visible\"}]}\n```"
        #expect(try ObjectConceptDiscovery.decode(concepts).map(\.concept.query) == ["bird"])
        #expect(throws: ObjectResponseIssue.incompleteJSON) {
            try ObjectConceptDiscovery.decode(#"{"concepts":[{"query":"bird"}"#)
        }
        #expect(throws: ObjectResponseIssue.self) {
            try ObjectConceptDiscovery.decode(#"{"concepts":[{"query":"bird","displayName":"Bird"}]}"#)
        }
        #expect(throws: ObjectResponseIssue.self) {
            try ObjectConceptDiscovery.decode(#"{"concepts":[{"query":3,"displayName":"Bird","reason":"Visible"}]}"#)
        }
    }

    @Test func `Assessment rejects invalid confidence and duplicate object IDs`() throws {
        let response = #"{"schemaVersion":2,"imageSummary":"Birds","objects":[{"id":"1","concept":"bird","description":"Visible bird","visibility":"clear","focusQuality":"sharp","focusEvidence":{"cropID":"1","observation":"subject feather edges are crisp"},"strengthEvidence":[],"problemEvidence":[],"expression":null,"obstructions":[],"strengths":[],"problems":[],"confidence":0.9}],"relationships":[],"strengths":[],"problems":[],"preferredObjectIDs":["1"],"confidence":0.8}"#
        #expect(try ObjectAnalysisResponseDecoder.decode("Here is the result:\n" + response, boardIDs: ["1"]).objects.count == 1)
        #expect(throws: ObjectResponseIssue.invalidValue("confidence")) {
            try ObjectAnalysisResponseDecoder.decode(response.replacingOccurrences(of: "\"confidence\":0.8}", with: "\"confidence\":1.2}"), boardIDs: ["1"])
        }
        let doubled = response.replacingOccurrences(of: "\"relationships\":[]", with: "\"objects\":[],\"relationships\":[]")
        #expect(throws: ObjectResponseIssue.invalidJSON) {
            try ObjectAnalysisResponseDecoder.decode(response + "\n" + doubled, boardIDs: ["1"])
        }
        #expect(throws: ObjectResponseIssue.incompleteJSON) {
            try ObjectAnalysisResponseDecoder.decode(String(response.dropLast(2)), boardIDs: ["1"])
        }
        #expect(throws: ObjectResponseIssue.missingID("2")) {
            try ObjectAnalysisResponseDecoder.decode(response, boardIDs: ["1", "2"])
        }
        #expect(throws: ObjectResponseIssue.self) {
            try ObjectAnalysisResponseDecoder.decode(
                response.replacingOccurrences(of: "\"visibility\":\"clear\"", with: "\"visibility\":\"hidden\""),
                boardIDs: ["1"],
            )
        }
        let extra = response.replacingOccurrences(of: "\"id\":\"1\"", with: "\"id\":\"3\"")
        #expect(throws: ObjectResponseIssue.unknownID("3")) {
            try ObjectAnalysisResponseDecoder.decode(extra, boardIDs: ["1"])
        }
    }

    @Test func `Captured assessment shape normalizes singular text lists`() throws {
        let observedShape = #"{"schemaVersion":2,"objects":[{"id":"1","concept":"bird","description":"Visible bird","visibility":"clear","focusQuality":"sharp","focusEvidence":{"cropID":"1","observation":"subject feather edges are crisp"},"strengthEvidence":[],"problemEvidence":[],"expression":null,"obstructions":"none","strengths":[],"problems":[],"confidence":0.9}],"relationships":[],"strengths":[],"problems":[],"preferredObjectIDs":["1"],"confidence":0.9}"#
        let recovered = try ObjectAnalysisResponseDecoder.decode(observedShape, boardIDs: ["1"])
        #expect(recovered.imageSummary == nil)
        #expect(recovered.objects[0].obstructions.isEmpty)
        let singular = observedShape.replacingOccurrences(of: "\"obstructions\":\"none\"", with: "\"obstructions\":\"branch across wing\"")
        #expect(try ObjectAnalysisResponseDecoder.decode(singular, boardIDs: ["1"]).objects[0].obstructions == ["branch across wing"])
        #expect(throws: ObjectResponseIssue.self) {
            try ObjectAnalysisResponseDecoder.decode(
                observedShape.replacingOccurrences(of: "\"obstructions\":\"none\"", with: "\"obstructions\":3"),
                boardIDs: ["1"],
            )
        }
        #expect(throws: ObjectResponseIssue.self) {
            try ObjectAnalysisResponseDecoder.decode(
                observedShape.replacingOccurrences(of: "\"preferredObjectIDs\":[\"1\"],", with: ""),
                boardIDs: ["1"],
            )
        }
    }

    @Test func `Numeric board IDs normalize but still require an exact board match`() throws {
        let response = #"{"schemaVersion":2,"objects":[{"id":1,"concept":"bird","description":"Flying bird","visibility":"clear","focusQuality":"sharp","focusEvidence":{"cropID":"1","observation":"subject feather edges are crisp"},"strengthEvidence":[],"problemEvidence":[],"expression":null,"obstructions":[],"strengths":[],"problems":[],"confidence":0.9}],"relationships":[],"strengths":[],"problems":[],"preferredObjectIDs":[1],"confidence":0.8}"#
        let assessment = try ObjectAnalysisResponseDecoder.decode(response, boardIDs: ["1"])
        #expect(assessment.objects.map(\.id) == ["1"])
        #expect(assessment.preferredObjectIDs == ["1"])
        #expect(throws: ObjectResponseIssue.unknownID("1")) {
            try ObjectAnalysisResponseDecoder.decode(response, boardIDs: ["2"])
        }
        #expect(throws: ObjectResponseIssue.self) {
            try ObjectAnalysisResponseDecoder.decode(
                response.replacingOccurrences(of: "\"id\":1", with: "\"id\":1.5"),
                boardIDs: ["1"],
            )
        }
    }
}
