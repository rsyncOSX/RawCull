import Foundation
import PhotoAIContracts
@testable import RawCull
import Testing

@Suite("Object analysis boundary", .tags(.smoke))
struct ObjectAnalysisBoundaryTests {
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
        let response = #"{"imageSummary":"Two birds","objects":[{"id":"1","concept":"bird","description":"Near bird","visibility":"clear","focusQuality":"sharp","expression":null,"obstructions":[],"strengths":["detail"],"problems":[],"confidence":0.9}],"relationships":[],"strengths":[],"problems":[],"preferredObjectIDs":["1"],"confidence":0.8}"#
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
        let response = #"{"imageSummary":"Birds","objects":[{"id":"1","concept":"bird","description":"Visible bird","visibility":"clear","focusQuality":"sharp","expression":null,"obstructions":[],"strengths":[],"problems":[],"confidence":0.9}],"relationships":[],"strengths":[],"problems":[],"preferredObjectIDs":["1"],"confidence":0.8}"#
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
        let observedShape = #"{"objects":[{"id":"1","concept":"bird","description":"Visible bird","visibility":"clear","focusQuality":"sharp","expression":null,"obstructions":"none","strengths":[],"problems":[],"confidence":0.9}],"relationships":[],"strengths":[],"problems":[],"preferredObjectIDs":["1"],"confidence":0.9}"#
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
        let response = #"{"objects":[{"id":1,"concept":"bird","description":"Flying bird","visibility":"clear","focusQuality":"sharp","expression":null,"obstructions":[],"strengths":[],"problems":[],"confidence":0.9}],"relationships":[],"strengths":[],"problems":[],"preferredObjectIDs":[1],"confidence":0.8}"#
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
