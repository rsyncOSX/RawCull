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
        #expect(throws: ObjectAnalysisError.invalidConceptResponse) {
            try ObjectConceptDiscovery.decode("not JSON")
        }
        #expect(throws: ObjectAnalysisError.invalidConceptResponse) {
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
        #expect(throws: ObjectAnalysisError.invalidAssessment) {
            try ObjectAnalysisResponseDecoder.decode(response, boardIDs: ["2"])
        }
        let duplicate = response.replacingOccurrences(of: "\"preferredObjectIDs\":[\"1\"]", with: "\"preferredObjectIDs\":[\"1\",\"1\"]")
        #expect(throws: ObjectAnalysisError.invalidAssessment) {
            try ObjectAnalysisResponseDecoder.decode(duplicate, boardIDs: ["1"])
        }
    }
}
