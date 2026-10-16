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
        objects[0]["strengths"] = (0 ..< counts.0).map { "Visible strength \($0)" }
        objects[0]["strengthEvidence"] = (0 ..< counts.1).map { _ in ["cropID": "1", "observation": "Visible subject contrast"] }
        document["objects"] = objects
        let invalid = try String(decoding: JSONSerialization.data(withJSONObject: document), as: UTF8.self)
        #expect(throws: ObjectResponseIssue.self) {
            try ObjectAnalysisResponseDecoder.decode(invalid, boardIDs: ["1"])
        }
        let feedback = RawCullObjectAnalysisFeature.assessmentValidationFeedback(invalid, fallback: .assessmentFailed)
        #expect(feedback.contains("strengths has \(counts.0) items but strengthEvidence has \(counts.1)"))
        #expect(feedback.contains("focusQuality is soft, so focusEvidence cannot be null"))
        #expect(feedback.contains("do not invent evidence"))
    }

    @Test func `Retry feedback explains invalid visibility and vague focus`() {
        let vague = focusResponse(observation: "The subject is in focus with visible texture.")
        let feedback = RawCullObjectAnalysisFeature.assessmentValidationFeedback(vague, fallback: .assessmentFailed)
        #expect(feedback.contains("does not support focusQuality=sharp"))
        #expect(feedback.contains("Rejected observation: The subject is in focus with visible texture."))
        #expect(feedback.contains("Reinspect only crop 1"))
        #expect(feedback.contains(#""focusQuality":"uncertain","focusEvidence":null"#))
        #expect(feedback.contains("Keep the object and its ID"))
        #expect(feedback.contains("Do not invent detail"))
        let invalid = vague.replacingOccurrences(of: "\"visibility\":\"clear\"", with: "\"visibility\":\"visible\"")
        #expect(RawCullObjectAnalysisFeature.assessmentValidationFeedback(invalid, fallback: .assessmentFailed).contains("Use exactly clear, partial, obscured, or uncertain"))
        #expect(throws: ObjectResponseIssue.self) { try ObjectAnalysisResponseDecoder.decode(invalid, boardIDs: ["1"]) }
    }

    @Test func `Undecodable feedback preserves typed errors and supplies a default`() {
        #expect(RawCullObjectAnalysisFeature.assessmentValidationFeedback("{", fallback: .incompleteJSON)
            == ObjectResponseIssue.incompleteJSON.localizedDescription)
        #expect(RawCullObjectAnalysisFeature.assessmentValidationFeedback("{")
            == ObjectResponseIssue.assessmentFailed.localizedDescription)
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

    @Test(arguments: [
        "The squirrel's fur texture and facial features are clearly resolved, with distinct edges and fine detail.",
        "Subject feather texture is distinctly resolved.",
        "Subject outline has distinct edges.",
        "The deer's antlers are well-defined with visible ridges and a smooth, natural texture.",
        "Subject feather texture is well-resolved."
    ])
    func `Sharp focus accepts equivalent resolved detail wording`(observation: String) throws {
        let response = focusResponse(observation: observation)
        #expect(try ObjectAnalysisResponseDecoder.decode(response, boardIDs: ["1"]).objects[0].focusQuality == .sharp)
    }

    @Test(arguments: [
        "Subject texture is not clearly resolved.",
        "Subject texture is clearly resolved but edges are soft.",
        "Subject edges are distinct but feathers are smeared.",
        "Subject texture lacks clearly resolved detail.",
        "Subject fur is visible.",
        "Subject antlers are not well-defined.",
        "Subject feather texture lacks well-resolved detail.",
        "The butterfly's wings are in focus, with visible texture and a muted color pattern."
    ])
    func `Sharp focus still rejects unsupported or contradictory detail wording`(observation: String) {
        #expect(throws: ObjectResponseIssue.self) {
            try ObjectAnalysisResponseDecoder.decode(focusResponse(observation: observation), boardIDs: ["1"])
        }
    }

    @Test(arguments: ["The horse is not sharply focused.", "The horse lacks sharp detail.", "The horse is not sharp.", "The cygnet is not in sharp focus.", "The feathers are not sharply defined."])
    func `Soft focus accepts negated sharpness without admitting positive sharpness`(description: String) throws {
        let response = focusResponse(observation: "The coat is soft and lacks crisp edges.")
            .replacingOccurrences(of: "\"focusQuality\":\"sharp\"", with: "\"focusQuality\":\"soft\"")
            .replacingOccurrences(of: "Visible bird", with: description)
        #expect(try ObjectAnalysisResponseDecoder.decode(response, boardIDs: ["1"]).objects[0].focusQuality == .soft)
        let contradictory = response.replacingOccurrences(of: description, with: "The horse is not sharply focused but its mane is sharp.")
        #expect(throws: ObjectResponseIssue.self) { try ObjectAnalysisResponseDecoder.decode(contradictory, boardIDs: ["1"]) }
    }

    @Test func `Retry feedback identifies focus contradictions`() {
        let response = focusResponse(observation: "The subject edges are crisp.")
            .replacingOccurrences(of: "Visible bird", with: "The feathers are blurred.")
        let feedback = RawCullObjectAnalysisFeature.assessmentValidationFeedback(response, fallback: .assessmentFailed)
        #expect(feedback.contains("contradict focusQuality=sharp"))
        #expect(feedback.contains("Do not invent detail"))
    }

    private func focusResponse(observation: String) -> String {
        #"{"schemaVersion":2,"objects":[{"id":"1","concept":"bird","description":"Visible bird","visibility":"clear","focusQuality":"sharp","focusEvidence":{"cropID":"1","observation":""# + observation + #""},"expression":null,"obstructions":[],"strengths":[],"strengthEvidence":[],"problems":[],"problemEvidence":[],"confidence":0.8}],"relationships":[],"strengths":[],"problems":[],"preferredObjectIDs":[],"confidence":0.8}"#
    }

    @Test func `Final retry abstains from captured butterfly focus wording`() throws {
        let response = focusResponse(observation: "clearly visible wing pattern and edge detail on the butterfly")
            .replacingOccurrences(of: "Visible bird", with: "A sharp butterfly on a flower")
            .replacingOccurrences(of: #""strengths":[],"strengthEvidence":[]"#,
                                  with: #""strengths":["Sharp wings","Bright colors"],"strengthEvidence":[{"cropID":"1","observation":"Visible wing detail"},{"cropID":"1","observation":"Orange wing markings"}]"#)
        #expect(throws: ObjectResponseIssue.self) { try ObjectAnalysisResponseDecoder.decode(response, boardIDs: ["1"]) }
        let result = try ObjectAnalysisResponseDecoder.decodeAbstainingFromUnsupportedFocus(response, boardIDs: ["1"])
        let object = try #require(result.objects.first)
        #expect(object.id == "1")
        #expect(object.focusQuality == .uncertain)
        #expect(object.focusEvidence == nil)
        #expect(!object.description.contains("sharp"))
        #expect(object.strengths == ["Bright colors"])
        #expect(object.strengthEvidence.map(\.observation) == ["Orange wing markings"])
    }

    @Test(arguments: ["sharp", "soft", "blurred"])
    func `Final retry abstains when focus evidence is explicitly null`(quality: String) throws {
        let response = focusResponse(observation: "Subject feather edges are crisp.")
            .replacingOccurrences(of: #""focusQuality":"sharp""#, with: "\"focusQuality\":\"\(quality)\"")
            .replacingOccurrences(of: #""focusEvidence":{"cropID":"1","observation":"Subject feather edges are crisp."}"#,
                                  with: #""focusEvidence":null"#)
        #expect(throws: ObjectResponseIssue.self) {
            try ObjectAnalysisResponseDecoder.decode(response, boardIDs: ["1"])
        }
        let result = try ObjectAnalysisResponseDecoder.decodeAbstainingFromUnsupportedFocus(response, boardIDs: ["1"])
        let object = try #require(result.objects.first)
        #expect(object.focusQuality == .uncertain)
        #expect(object.focusEvidence == nil)
        #expect(object.description == "Visible bird")
        #expect(result.preferredObjectIDs.isEmpty)
    }

    @Test func `Final focus abstention preserves supported objects`() throws {
        let response = focusResponse(observation: "Subject feather edges are crisp.")
        #expect(try ObjectAnalysisResponseDecoder.decodeAbstainingFromUnsupportedFocus(response, boardIDs: ["1"]) == ObjectAnalysisResponseDecoder.decode(response, boardIDs: ["1"]))
    }

    @Test func `Focus abstention preserves paired evidence and unaffected object ownership`() throws {
        let response = #"""
        {"schemaVersion":2,"imageSummary":"A sharp bird beside a fence","objects":[
          {"id":"1","concept":"bird","description":"A sharp bird","visibility":"partial","focusQuality":"sharp","focusEvidence":null,"expression":null,
           "obstructions":["branch"],"strengths":["Bright colors","Fine detail","Visible wings"],
           "strengthEvidence":[{"cropID":"1","observation":"Orange markings"},{"cropID":"1","observation":"Wing markings"},{"cropID":"1","observation":"Soft edges"}],
           "problems":["Blurred wings","Obstructed body"],"problemEvidence":[{"cropID":"1","observation":"Smeared feathers"},{"cropID":"1","observation":"Branch across body"}],"confidence":0.7},
          {"id":"2","concept":"fence","description":"Visible fence","visibility":"clear","focusQuality":"sharp","focusEvidence":{"cropID":"2","observation":"Crisp fence edges"},"expression":null,
           "obstructions":[],"strengths":["Sharp edges"],"strengthEvidence":[{"cropID":"2","observation":"Crisp outline"}],"problems":[],"problemEvidence":[],"confidence":0.9}
        ],"relationships":["Bird beside fence","Bird is sharper than fence"],"strengths":[],"problems":[],"preferredObjectIDs":["1"],"confidence":0.8}
        """#
        let result = try ObjectAnalysisResponseDecoder.decodeAbstainingFromUnsupportedFocus(
            response, boardIDs: ["1", "2"], expectedConcepts: ["1": "bird", "2": "fence"],
        )
        let bird = try #require(result.objects.first)
        #expect(bird.description == "Object identified as bird.")
        #expect(bird.focusQuality == .uncertain)
        #expect(bird.focusEvidence == nil)
        #expect(bird.strengths == ["Bright colors"])
        #expect(bird.strengthEvidence == [ObjectClaimEvidence(cropID: "1", observation: "Orange markings")])
        #expect(bird.problems == ["Obstructed body"])
        #expect(bird.problemEvidence == [ObjectClaimEvidence(cropID: "1", observation: "Branch across body")])
        #expect(bird.obstructions == ["branch"])
        #expect(bird.visibility == .partial)
        #expect(bird.confidence == 0.7)
        let fence = try #require(result.objects.last)
        #expect(fence.id == "2")
        #expect(fence.concept == "fence")
        #expect(fence.focusQuality == .sharp)
        #expect(fence.focusEvidence == ObjectClaimEvidence(cropID: "2", observation: "Crisp fence edges"))
        #expect(fence.strengths == ["Sharp edges"])
        #expect(fence.strengthEvidence == [ObjectClaimEvidence(cropID: "2", observation: "Crisp outline")])
        #expect(result.imageSummary == nil)
        #expect(result.relationships == ["Bird beside fence"])
        #expect(result.preferredObjectIDs.isEmpty)
    }

    @Test(arguments: [#""expression":null,""#, #""focusEvidence":null,""#])
    func `Focus abstention still requires explicit nullable fields`(field: String) {
        let response = focusResponse(observation: "Visible wings")
            .replacingOccurrences(of: #""focusEvidence":{"cropID":"1","observation":"Visible wings"},"#, with: #""focusEvidence":null,"#)
            .replacingOccurrences(of: field, with: "")
        #expect(throws: ObjectResponseIssue.self) {
            try ObjectAnalysisResponseDecoder.decodeAbstainingFromUnsupportedFocus(response, boardIDs: ["1"])
        }
    }

    @Test(arguments: [
        (#""cropID":"1""#, #""cropID":"2""#),
        (#""confidence":0.8"#, #""confidence":1.2"#),
        (#""strengths":[],"strengthEvidence":[]"#, #""strengths":["Sharp wings"],"strengthEvidence":[]"#),
        (#""visibility":"clear""#, #""visibility":"visible""#),
    ])
    func `Final focus abstention rejects unrelated invalid data`(replacement: (String, String)) {
        let response = focusResponse(observation: "clearly visible wing pattern and edge detail on the butterfly")
            .replacingOccurrences(of: replacement.0, with: replacement.1)
        #expect(throws: ObjectResponseIssue.self) {
            try ObjectAnalysisResponseDecoder.decodeAbstainingFromUnsupportedFocus(response, boardIDs: ["1"])
        }
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
