@testable import CoreAICLIPBackend
import CoreAI
import CoreAIImageSegmenter
import Foundation
import PhotoAIContracts
import Testing

@Suite("CLIP text capability")
struct CLIPTextCapabilityTests {
    @Test("Tokenizer fixtures cover empty, punctuation, Unicode, and truncation")
    func tokenizerFixtures() throws {
        let tokenizer = try fixtureTokenizer()

        #expect(tokenizer.encode("", contextLength: 6) == [
            CLIPTokenizer.sotTokenId,
            CLIPTokenizer.eotTokenId,
            CLIPTokenizer.eotTokenId,
            CLIPTokenizer.eotTokenId,
            CLIPTokenizer.eotTokenId,
            CLIPTokenizer.eotTokenId,
        ])
        #expect(tokenizer.encode("Hi!", contextLength: 6) == [
            CLIPTokenizer.sotTokenId,
            10,
            11,
            12,
            CLIPTokenizer.eotTokenId,
            CLIPTokenizer.eotTokenId,
        ])
        #expect(tokenizer.encode("É", contextLength: 4) == [
            CLIPTokenizer.sotTokenId,
            13,
            14,
            CLIPTokenizer.eotTokenId,
        ])
        #expect(tokenizer.encode("cat", contextLength: 4) == [
            CLIPTokenizer.sotTokenId,
            20,
            21,
            CLIPTokenizer.eotTokenId,
        ])
        #expect(tokenizer.encode("hi", contextLength: 4) == [
            CLIPTokenizer.sotTokenId,
            10,
            11,
            CLIPTokenizer.eotTokenId,
        ])
    }

    @Test("Static multi-row batches have deterministic padding and masks")
    func staticBatchAndAttentionMasks() throws {
        let tokenizer = try fixtureTokenizer()
        let empty = tokenizer.encode("", contextLength: 6)
        let filler = tokenizer.encode("hi", contextLength: 6)

        let first = try CoreAICLIPProvider.makeTextBatch(
            queryTokens: empty,
            fillerTokens: filler,
            batchSize: 3,
            sequenceLength: 6
        )
        let second = try CoreAICLIPProvider.makeTextBatch(
            queryTokens: empty,
            fillerTokens: filler,
            batchSize: 3,
            sequenceLength: 6
        )

        #expect(first == second)
        #expect(first.tokenIDs.count == 3)
        #expect(first.tokenIDs.allSatisfy { $0.count == 6 })
        #expect(first.attentionMask == [
            [1, 1, 0, 0, 0, 0],
            [1, 1, 1, 1, 0, 0],
            [1, 1, 1, 1, 0, 0],
        ])
    }

    @Test("Text output rows retain expected shape and scalar values")
    func textOutputValidation() throws {
        var output = NDArray(shape: [2, 3], scalarType: .float32)
        var view = output.mutableView(as: Float.self)
        view.copyElements(fromContentsOf: [
            0.6, 0, 0.8,
            0, 1, 0,
        ])

        let values = try CoreAICLIPProvider.validatedTextEmbeddingValues(
            output,
            expectedBatchSize: 2
        )
        #expect(values == [0.6, 0, 0.8])

        #expect(throws: CLIPTextInferenceError.unexpectedOutputShape(
            expectedBatchSize: 3,
            actual: [2, 3]
        )) {
            try CoreAICLIPProvider.validatedTextEmbeddingValues(
                output,
                expectedBatchSize: 3
            )
        }

        let unsupported = NDArray(shape: [2, 3], scalarType: .int32)
        #expect(throws: CLIPTextInferenceError.unsupportedOutputScalarType) {
            try CoreAICLIPProvider.validatedTextEmbeddingValues(
                unsupported,
                expectedBatchSize: 2
            )
        }
    }

    @Test("Text vectors reject malformed and unnormalized output")
    func textEmbeddingValidation() throws {
        let descriptor = TextEmbeddingDescriptor(
            backend: fixtureBackend(),
            dimensions: 2,
            tokenizerVersion: CoreAICLIPProvider.tokenizerVersion
        )

        #expect(throws: TextEmbeddingValidationError.dimensionMismatch(
            expected: 2,
            actual: 1
        )) {
            try TextEmbedding(descriptor: descriptor, values: [1])
        }
        #expect(throws: TextEmbeddingValidationError.nonFiniteValue(index: 1)) {
            try TextEmbedding(descriptor: descriptor, values: [1, .infinity])
        }
        #expect(throws: TextEmbeddingValidationError.zeroNorm) {
            try TextEmbedding(descriptor: descriptor, values: [0, 0])
        }
        #expect(throws: TextEmbeddingValidationError.notNormalized(magnitude: 2)) {
            try TextEmbedding(descriptor: descriptor, values: [2, 0])
        }
    }

    @Test("Compatible image/text scoring ranks related vectors first")
    func compatibleRetrievalFixture() throws {
        let fixture = try comparisonFixture()
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        let query = try TextEmbedding(
            descriptor: fixture.textDescriptor,
            values: [0.8, 0.6]
        )
        let related = try fixture.artifact(values: [1, 0])
        let unrelated = try fixture.artifact(values: [0, 1])

        let relatedScore = try fixture.provider.similarity(
            image: related,
            text: query
        )
        let unrelatedScore = try fixture.provider.similarity(
            image: unrelated,
            text: query
        )

        #expect(relatedScore > unrelatedScore)
        #expect(abs(relatedScore - 0.8) < 0.0001)
        #expect(abs(unrelatedScore - 0.6) < 0.0001)
    }

    @Test("Comparison rejects every incompatible descriptor field")
    func incompatibleDescriptors() throws {
        let fixture = try comparisonFixture()
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        let image = try fixture.artifact(values: [1, 0])

        try expectComparisonError(
            .unsupportedTextBackend(expected: "clip", actual: "vision"),
            fixture: fixture,
            image: image,
            backend: replacing(fixture.backend, backend: "vision")
        )
        try expectComparisonError(
            .incompatibleModelFingerprint,
            fixture: fixture,
            image: image,
            backend: replacing(fixture.backend, modelFingerprint: "other")
        )
        try expectComparisonError(
            .incompatibleRepresentation,
            fixture: fixture,
            image: image,
            backend: replacing(fixture.backend, representation: "other")
        )
        try expectComparisonError(
            .incompatiblePreprocessing,
            fixture: fixture,
            image: image,
            backend: replacing(fixture.backend, preprocessingVersion: "other")
        )
        try expectComparisonError(
            .incompatibleNormalization,
            fixture: fixture,
            image: image,
            backend: replacing(fixture.backend, normalizationVersion: "other")
        )
        try expectComparisonError(
            .incompatibleConfiguration,
            fixture: fixture,
            image: image,
            backend: replacing(fixture.backend, configurationVersion: "other")
        )

        let wrongDimensions = try TextEmbedding(
            descriptor: TextEmbeddingDescriptor(
                backend: fixture.backend,
                dimensions: 3,
                tokenizerVersion: CoreAICLIPProvider.tokenizerVersion
            ),
            values: [1, 0, 0]
        )
        #expect(throws: ImageTextSimilarityError.incompatibleDimensions(
            expected: 3,
            actual: 2
        )) {
            try fixture.provider.similarity(image: image, text: wrongDimensions)
        }

        let wrongTokenizer = try TextEmbedding(
            descriptor: TextEmbeddingDescriptor(
                backend: fixture.backend,
                dimensions: 2,
                tokenizerVersion: "other"
            ),
            values: [1, 0]
        )
        #expect(throws: ImageTextSimilarityError.incompatibleTokenizer) {
            try fixture.provider.similarity(image: image, text: wrongTokenizer)
        }
    }

    @Test("Comparison rejects Vision and malformed CLIP artifacts")
    func incompatibleAndMalformedArtifacts() throws {
        let fixture = try comparisonFixture()
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        let text = try TextEmbedding(
            descriptor: fixture.textDescriptor,
            values: [1, 0]
        )
        let vision = SimilarityArtifact(
            descriptor: SimilarityArtifactDescriptor(
                backend: replacing(fixture.backend, backend: "vision"),
                dimensions: 2,
                sourceFingerprint: fixture.source
            ),
            payload: Data()
        )
        #expect(throws: ImageTextSimilarityError.unsupportedImageBackend(
            expected: "clip",
            actual: "vision"
        )) {
            try fixture.provider.similarity(image: vision, text: text)
        }

        let malformed = SimilarityArtifact(
            descriptor: SimilarityArtifactDescriptor(
                backend: fixture.backend,
                dimensions: 2,
                sourceFingerprint: fixture.source
            ),
            payload: Data("not-json".utf8)
        )
        #expect(throws: ImageTextSimilarityError.self) {
            try fixture.provider.similarity(image: malformed, text: text)
        }
    }

    @Test("A cancelled text request stops before model loading")
    func cancellationBeforeModelLoad() async throws {
        let fixture = try comparisonFixture()
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        let task = Task {
            await Task.yield()
            return try await fixture.provider.embedding(for: "bird")
        }
        task.cancel()

        await #expect(throws: CancellationError.self) {
            try await task.value
        }
    }

    private func fixtureTokenizer() throws -> CLIPTokenizer {
        try CLIPTokenizer(
            vocab: [
                "h": 10,
                "i</w>": 11,
                "!</w>": 12,
                "Ã": 13,
                "©</w>": 14,
                "c": 20,
                "a": 21,
                "t</w>": 22,
            ],
            merges: []
        )
    }

    private func comparisonFixture() throws -> ComparisonFixture {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(
            at: root.appendingPathComponent("tokenizer", isDirectory: true),
            withIntermediateDirectories: true
        )
        try Data("{}".utf8).write(
            to: root.appendingPathComponent("tokenizer/tokenizer.json")
        )
        try Data().write(to: root.appendingPathComponent("model.aimodel"))
        let metadata = ModelBundleMetadata(
            name: "text-test",
            family: "clip",
            assets: ["main": "model.aimodel"]
        )
        try JSONEncoder().encode(metadata).write(
            to: root.appendingPathComponent("metadata.json")
        )
        let provider = try CoreAICLIPProvider(modelBundleURL: root)
        return ComparisonFixture(root: root, provider: provider)
    }

    private func expectComparisonError(
        _ error: ImageTextSimilarityError,
        fixture: ComparisonFixture,
        image: SimilarityArtifact,
        backend: SimilarityBackendDescriptor
    ) throws {
        let text = try TextEmbedding(
            descriptor: TextEmbeddingDescriptor(
                backend: backend,
                dimensions: 2,
                tokenizerVersion: CoreAICLIPProvider.tokenizerVersion
            ),
            values: [1, 0]
        )
        #expect(throws: error) {
            try fixture.provider.similarity(image: image, text: text)
        }
    }
}

private struct ComparisonFixture {
    let root: URL
    let provider: CoreAICLIPProvider

    var backend: SimilarityBackendDescriptor {
        provider.backendDescriptor
    }

    var textDescriptor: TextEmbeddingDescriptor {
        TextEmbeddingDescriptor(
            backend: backend,
            dimensions: 2,
            tokenizerVersion: CoreAICLIPProvider.tokenizerVersion
        )
    }

    var source: SourceFingerprint {
        SourceFingerprint(
            standardizedPath: "/tmp/text-test.raw",
            fileSize: 1,
            modificationDate: nil
        )
    }

    func artifact(values: [Float]) throws -> SimilarityArtifact {
        let embedding = ImageEmbedding(
            backend: backend.backend,
            modelIdentity: provider.modelIdentity,
            values: values
        )
        return SimilarityArtifact(
            descriptor: SimilarityArtifactDescriptor(
                backend: backend,
                dimensions: values.count,
                sourceFingerprint: source
            ),
            payload: try JSONEncoder().encode(embedding)
        )
    }
}

private func fixtureBackend() -> SimilarityBackendDescriptor {
    SimilarityBackendDescriptor(
        backend: "clip",
        modelFingerprint: "test-model",
        representation: "normalized-float-vector-json-v1",
        preprocessingVersion: "clip-srgb-bilinear-chw-v1",
        normalizationVersion: "l2-v1",
        configurationVersion: "test-v1"
    )
}

private func replacing(
    _ descriptor: SimilarityBackendDescriptor,
    backend: String? = nil,
    modelFingerprint: String? = nil,
    representation: String? = nil,
    preprocessingVersion: String? = nil,
    normalizationVersion: String? = nil,
    configurationVersion: String? = nil
) -> SimilarityBackendDescriptor {
    SimilarityBackendDescriptor(
        backend: backend ?? descriptor.backend,
        modelFingerprint: modelFingerprint ?? descriptor.modelFingerprint,
        representation: representation ?? descriptor.representation,
        preprocessingVersion: preprocessingVersion ?? descriptor.preprocessingVersion,
        normalizationVersion: normalizationVersion ?? descriptor.normalizationVersion,
        configurationVersion: configurationVersion ?? descriptor.configurationVersion
    )
}
