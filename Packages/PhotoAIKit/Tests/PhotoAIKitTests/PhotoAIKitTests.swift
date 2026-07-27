import CoreAICLIPBackend
import CoreAISAM3Backend
import CoreGraphics
import Foundation
import PhotoAIContracts
import PhotoAIStorage
import PhotoAIWorkflows
import Testing

@Suite("PhotoAIKit public API")
struct PhotoAIKitTests {
    @Test("CLIP normalization and cosine distance are typed and stable")
    func embeddingMath() throws {
        let identity = ModelIdentity(family: "clip", name: "test", assetName: "test.aimodel")
        let left = ImageEmbedding(backend: "clip", modelIdentity: identity, values: [3, 4])
        let same = ImageEmbedding(backend: "clip", modelIdentity: identity, values: [6, 8])
        let orthogonal = ImageEmbedding(backend: "clip", modelIdentity: identity, values: [-4, 3])

        #expect(abs((left.cosineDistance(to: same) ?? -1)) < 0.0001)
        #expect(abs((left.cosineDistance(to: orthogonal) ?? -1) - 1) < 0.0001)
        let descriptor = EmbeddingArtifactDescriptor(
            backend: "clip",
            modelFingerprint: identity.artifactIdentifier,
            dimensions: left.values.count,
            representation: "normalized-float-vector-json-v1",
            preprocessingVersion: "test-v1",
            normalizationVersion: "l2-v1",
            configurationVersion: "test-v1",
            sourceFingerprint: SourceFingerprint(
                standardizedPath: "/tmp/test.raw",
                fileSize: 1,
                modificationDate: nil
            )
        )
        let artifact = EmbeddingArtifact(descriptor: descriptor, embedding: left)
        let encoded = try EmbeddingCodec.encode(artifact)
        #expect(try EmbeddingCodec.decodeArtifact(encoded) == artifact)
    }

    @Test("Model bundles are accepted only through supplied URLs")
    func modelBundleURLValidation() throws {
        let root = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(
            at: root.appendingPathComponent("tokenizer"),
            withIntermediateDirectories: true
        )
        try Data("{}".utf8).write(to: root.appendingPathComponent("tokenizer/tokenizer.json"))
        try Data().write(to: root.appendingPathComponent("model.aimodel"))
        let metadata = ModelBundleMetadata(
            name: "test-clip",
            family: "clip",
            sourceModel: "example/model",
            metadataVersion: "1",
            assets: ["main": "model.aimodel"]
        )
        try JSONEncoder().encode(metadata).write(to: root.appendingPathComponent("metadata.json"))

        let status = ModelBundleResolver(descriptor: .clip).status(at: root)
        #expect(status.modelURL == root)
        #expect(status.identity?.assetName == "model.aimodel")
        let provider = try CoreAICLIPProvider(modelBundleURL: root)
        #expect(provider.modelIdentity.name == "test-clip")
    }

    @Test("SAM3 accepts the existing flat tokenizer export layout")
    func flatSAM3Bundle() throws {
        let root = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        try Data("{}".utf8).write(to: root.appendingPathComponent("tokenizer.json"))
        try Data().write(to: root.appendingPathComponent("sam3.aimodel"))
        let metadata = ModelBundleMetadata(
            name: "test-sam3",
            family: "sam3",
            assets: ["main": "sam3.aimodel"]
        )
        try JSONEncoder().encode(metadata).write(to: root.appendingPathComponent("metadata.json"))

        let provider = try CoreAISAM3Provider(modelBundleURL: root)
        #expect(provider.modelIdentity.name == "test-sam3")
        #expect(provider.modelIdentity.cacheIdentifier == "coreai-sam3-local:test-sam3:sam3.aimodel")
    }

    @Test("Explicit cache identifiers preserve host storage versions")
    func explicitCacheIdentifier() {
        let identity = ModelIdentity(
            family: "sam3",
            name: "adapter",
            assetName: "",
            cacheIdentifier: "legacy-version"
        )
        #expect(identity.cacheIdentifier == "legacy-version")
    }

    @Test("Bounded indexer can recompute a whole batch with fallback")
    func wholeBatchFallback() async throws {
        let fallback = ConstantEmbeddingProvider(name: "fallback", shouldFail: false)
        let indexer = EmbeddingIndexer(
            primaryProvider: ConstantEmbeddingProvider(name: "primary", shouldFail: true),
            fallbackProvider: fallback,
            decoder: SolidImageDecoder(),
            fallbackPolicy: .wholeBatch,
            concurrencyLimit: 2
        )
        let sources = (0 ..< 4).map {
            AIImageSource(
                id: UUID(),
                url: URL(fileURLWithPath: "/tmp/\($0).raw"),
                displayName: "\($0).raw"
            )
        }
        let result = try await indexer.index(sources)
        #expect(result.usedWholeBatchFallback)
        #expect(result.failures.isEmpty)
        #expect(result.embeddings.count == sources.count)
        #expect(result.embeddings.values.allSatisfy { $0.modelIdentity.name == "fallback" })
    }

    @Test("Segmentation service caches by package-owned source")
    func segmentationMemoryCache() async throws {
        let provider = FakeSegmenter()
        let memory = SubjectMaskMemoryStore()
        let service = SegmentationService(provider: provider, stores: [memory], maxSide: 64)
        let source = AIImageSource(
            id: UUID(),
            url: URL(fileURLWithPath: "/tmp/photo.raw"),
            displayName: "photo.raw"
        )
        let image = try #require(makeImage(width: 16, height: 12))

        _ = try await service.segment(image: image, source: source, prompt: .subject)
        _ = try await service.segment(image: image, source: source, prompt: .subject)
        #expect(await provider.calls == 1)
    }

    @Test("Configured repository reads masks without host globals")
    func configuredMaskRepository() async throws {
        let source = AIImageSource(
            id: UUID(),
            url: URL(fileURLWithPath: "/tmp/repository-photo.raw"),
            displayName: "repository-photo.raw"
        )
        let model = ModelIdentity(
            family: "sam3",
            name: "repository-test",
            assetName: "sam3.aimodel"
        )
        let memory = SubjectMaskMemoryStore()
        let configuration = SubjectMaskRepositoryConfiguration(
            defaultPrompt: .bird,
            modelIdentity: model,
            inputMaxSide: 128
        )
        let repository = SubjectMaskRepository(
            configuration: configuration,
            stores: [memory]
        )
        let key = await repository.storageKey(for: source)
        let mask = try #require(makeImage(width: 8, height: 6))
        let timing = SubjectSegmentationTiming(totalMilliseconds: 1)
        let diagnostics = SubjectSegmentationDiagnostics(
            modelIdentity: model,
            prompt: .bird,
            confidence: 0.8,
            timing: timing,
            inputSize: CGSize(width: 8, height: 6),
            outputSize: CGSize(width: 8, height: 6)
        )
        let result = SubjectSegmentationResult(
            sourceID: source.id,
            requestID: UUID(),
            prompt: .bird,
            mask: mask,
            confidence: 0.8,
            modelIdentity: model,
            inputSize: CGSize(width: 8, height: 6),
            outputSize: CGSize(width: 8, height: 6),
            timing: timing,
            diagnostics: diagnostics
        )

        await memory.save(result, for: key)

        #expect(await repository.contains(source))
        #expect(await repository.cachedMask(for: source)?.prompt == .bird)
        #expect(await repository.cachedMask(for: source, prompt: .person) == nil)
    }

    @Test("Disk store round trips PNG masks without model assets")
    func diskStoreRoundTrip() async throws {
        let root = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let store = try SubjectMaskDiskStore(cacheDirectory: root)
        let source = AIImageSource(id: UUID(), url: root.appendingPathComponent("source.raw"), displayName: "source.raw")
        try Data("source".utf8).write(to: source.url)
        let identity = SourceFileIdentity.read(from: source.url)
        let model = ModelIdentity(family: "sam3", name: "test", assetName: "sam3.aimodel")
        let key = SubjectMaskStorageKey(
            source: source,
            sourceIdentity: identity,
            prompt: .bird,
            modelIdentity: model,
            inputMaxSide: 64
        )
        let mask = try #require(makeImage(width: 8, height: 6))
        let timing = SubjectSegmentationTiming(totalMilliseconds: 1)
        let diagnostics = SubjectSegmentationDiagnostics(
            modelIdentity: model,
            prompt: .bird,
            confidence: 0.8,
            timing: timing,
            inputSize: CGSize(width: 8, height: 6),
            outputSize: CGSize(width: 8, height: 6)
        )
        let result = SubjectSegmentationResult(
            sourceID: source.id,
            requestID: UUID(),
            prompt: .bird,
            mask: mask,
            confidence: 0.8,
            modelIdentity: model,
            inputSize: CGSize(width: 8, height: 6),
            outputSize: CGSize(width: 8, height: 6),
            timing: timing,
            diagnostics: diagnostics
        )

        try await store.save(result, for: key)
        let loaded = await store.load(for: key)
        #expect(loaded?.prompt == .bird)
        #expect(loaded?.mask.width == 8)
        #expect(loaded?.mask.height == 6)
    }
}

private struct ConstantEmbeddingProvider: ImageEmbeddingProviding {
    let modelIdentity: ModelIdentity
    let shouldFail: Bool

    init(name: String, shouldFail: Bool) {
        self.modelIdentity = ModelIdentity(family: "clip", name: name, assetName: "\(name).aimodel")
        self.shouldFail = shouldFail
    }

    func embedding(for image: CGImage) async throws -> ImageEmbedding {
        if shouldFail { throw TestError.expected }
        return ImageEmbedding(backend: "clip", modelIdentity: modelIdentity, values: [1, 0, 0])
    }
}

private struct SolidImageDecoder: ImageDecoding {
    func image(for source: AIImageSource) async throws -> CGImage {
        guard let image = makeImage(width: 4, height: 4) else { throw TestError.imageCreation }
        return image
    }
}

private actor FakeSegmenter: SubjectSegmenting {
    nonisolated let modelIdentity = ModelIdentity(
        family: "sam3",
        name: "fake",
        assetName: "fake.aimodel"
    )
    private(set) var calls = 0

    func segment(_ request: SubjectSegmentationRequest) async throws -> SubjectSegmentationResult {
        calls += 1
        let timing = SubjectSegmentationTiming(totalMilliseconds: 1)
        let diagnostics = SubjectSegmentationDiagnostics(
            modelIdentity: modelIdentity,
            prompt: request.prompt,
            confidence: 0.9,
            timing: timing,
            inputSize: request.inputSize,
            outputSize: request.inputSize
        )
        return SubjectSegmentationResult(
            sourceID: request.sourceID,
            requestID: request.requestID,
            prompt: request.prompt,
            mask: request.image,
            confidence: 0.9,
            modelIdentity: modelIdentity,
            inputSize: request.inputSize,
            outputSize: request.inputSize,
            timing: timing,
            diagnostics: diagnostics
        )
    }
}

private enum TestError: Error {
    case expected
    case imageCreation
}

private func temporaryDirectory() throws -> URL {
    let url = FileManager.default.temporaryDirectory
        .appendingPathComponent("PhotoAIKitTests-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
}

private func makeImage(width: Int, height: Int) -> CGImage? {
    let colorSpace = CGColorSpaceCreateDeviceRGB()
    guard let context = CGContext(
        data: nil,
        width: width,
        height: height,
        bitsPerComponent: 8,
        bytesPerRow: 0,
        space: colorSpace,
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    ) else { return nil }
    context.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
    context.fill(CGRect(x: 0, y: 0, width: width, height: height))
    return context.makeImage()
}
