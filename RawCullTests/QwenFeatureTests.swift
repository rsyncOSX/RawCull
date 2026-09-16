import Foundation
@testable import RawCull
import Testing

@Suite("Qwen feature", .tags(.smoke))
struct QwenFeatureTests {
    @Test
    func `Structured assessment decodes JSON wrapped in model prose`() throws {
        let response = """
        ```json
        {
          "subject": "bird on a branch",
          "compositionScore": 4,
          "exposureScore": 5,
          "subjectVisibilityScore": 3,
          "eyesOpen": true,
          "problems": ["branch crosses tail"],
          "strengths": ["clean background"],
          "confidence": 0.8
        }
        ```
        """

        let assessment = try QwenPhotoAssessment.decodeResponse(response)

        #expect(assessment.subject == "bird on a branch")
        #expect(assessment.compositionScore == 4)
        #expect(assessment.eyesOpen == true)
        #expect(assessment.overallScore > 0.7)
    }

    @Test
    func `Structured assessment rejects scores outside the schema`() {
        let response = #"{"subject":"bird","compositionScore":7,"exposureScore":5,"subjectVisibilityScore":3,"eyesOpen":null,"problems":[],"strengths":[],"confidence":0.8}"#

        #expect(throws: QwenModelError.self) {
            try QwenPhotoAssessment.decodeResponse(response)
        }
    }

    @Test
    func `Qwen manager validates a compatible Core AI bundle`() async throws {
        let bundle = try makeQwenBundle(kind: "vlm")
        defer { try? FileManager.default.removeItem(at: bundle) }

        let status = await QwenModelManager().validate(url: bundle)

        guard case let .available(url, modelName) = status else {
            Issue.record("Expected the Qwen model bundle to validate, got \(status)")
            return
        }
        #expect(url.standardizedFileURL == bundle.standardizedFileURL)
        #expect(modelName == "qwen3_4b_test")
    }

    @Test
    func `Qwen manager rejects a text-only Qwen model`() async throws {
        let bundle = try makeQwenBundle()
        defer { try? FileManager.default.removeItem(at: bundle) }

        let status = await QwenModelManager().validate(url: bundle)

        guard case let .invalid(_, reason) = status else {
            Issue.record("Expected the text-only Qwen model to be rejected, got \(status)")
            return
        }
        #expect(reason.contains("text-only"))
    }

    private func makeQwenBundle(
        tokenizer: String = "Qwen/Qwen3-4B",
        kind: String = "llm",
    ) throws -> URL {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("RawCullQwenTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(
            at: root.appendingPathComponent("tokenizer", isDirectory: true),
            withIntermediateDirectories: true,
        )
        try Data().write(to: root.appendingPathComponent("qwen.aimodelc"))
        if kind == "vlm" {
            try Data().write(to: root.appendingPathComponent("embedding.aimodelc"))
            try Data().write(to: root.appendingPathComponent("vision.aimodelc"))
        }
        try Data("{}".utf8).write(to: root.appendingPathComponent("tokenizer/tokenizer.json"))
        try Data("{}".utf8).write(to: root.appendingPathComponent("tokenizer/tokenizer_config.json"))
        let metadata = """
        {
          "metadata_version": "0.2",
          "kind": "\(kind)",
          "name": "qwen3_4b_test",
          "assets": {
            "main": "qwen.aimodelc",
            "embedding": "embedding.aimodelc",
            "vision": "vision.aimodelc"
          },
          "vision": {
            "image_size": 448,
            "patch_size": 14,
            "image_token_count": 256,
            "image_token_id": 151655
          },
          "language": {
            "tokenizer": "\(tokenizer)",
            "vocab_size": 151936,
            "max_context_length": 40960,
            "embedded_tokenizer": true,
            "function_map": { "main": ["main"] }
          },
          "source": { "hf_model_id": "\(tokenizer)" }
        }
        """
        try Data(metadata.utf8).write(to: root.appendingPathComponent("metadata.json"))
        return root
    }
}
