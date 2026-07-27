import CoreGraphics
import Foundation
import PhotoAIContracts
import PhotoAIStorage
import PhotoAIWorkflows
import Testing
import VisionFeaturePrintBackend

@Suite("Chapter 2 package expansions")
struct ArchitectureExpansionTests {
    @Test("Manifest fingerprints are verified and become artifact identity")
    func verifiedModelFingerprint() throws {
        let root = try expansionTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let asset = root.appendingPathComponent("model.aimodel")
        try Data("model-v1".utf8).write(to: asset)
        try FileManager.default.createDirectory(
            at: root.appendingPathComponent("tokenizer"),
            withIntermediateDirectories: true
        )
        try Data("{}".utf8).write(to: root.appendingPathComponent("tokenizer/tokenizer.json"))
        let fingerprint = try ModelAssetFingerprinter.cryptographicFingerprint(at: asset)
        let metadata = ModelBundleMetadata(
            name: "verified",
            family: "clip",
            assets: ["main": asset.lastPathComponent],
            assetFingerprints: [
                "main": ModelAssetFingerprintManifest(
                    algorithm: fingerprint.algorithm,
                    value: fingerprint.value
                ),
            ]
        )
        try JSONEncoder().encode(metadata).write(to: root.appendingPathComponent("metadata.json"))

        let status = ModelBundleResolver(
            descriptor: ModelResourceDescriptor.clip.bundleDescriptor
        ).status(at: root)
        #expect(status.identity?.assetFingerprint?.isCryptographicallyVerified == true)
        #expect(status.identity?.artifactIdentifier.contains(fingerprint.value) == true)

        try Data("model-v2".utf8).write(to: asset)
        guard case .invalid = ModelBundleResolver(
            descriptor: ModelResourceDescriptor.clip.bundleDescriptor
        ).status(at: root) else {
            Issue.record("A modified asset should fail manifest verification.")
            return
        }
    }

    @Test("Resource resolver and provider factory share candidate validation")
    func modelProviderFactory() throws {
        let root = try expansionTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let bundle = try makeExpansionModelBundle(in: root)
        let factory = ModelProviderFactory<String>(descriptor: .clip) { url in
            url.lastPathComponent
        }
        #expect(factory.capability(in: [root.appendingPathComponent("missing"), bundle]).isAvailable)
        #expect(try factory.makeFirstAvailable(in: [bundle]) == bundle.lastPathComponent)
    }

    @Test("Legacy CLIP data is accepted only as a rewrite candidate")
    func legacyEmbeddingMigration() throws {
        let model = ModelIdentity(
            family: "clip",
            name: "current",
            assetName: "model.aimodel",
            assetFingerprint: ModelAssetFingerprint(
                algorithm: .sha256,
                value: "abc123",
                isCryptographicallyVerified: true
            )
        )
        let descriptor = EmbeddingArtifactDescriptor(
            backend: "clip",
            modelFingerprint: model.artifactIdentifier,
            dimensions: 2,
            representation: "normalized-float-vector-json-v1",
            preprocessingVersion: "clip-v1",
            normalizationVersion: "l2-v1",
            configurationVersion: "test-v1",
            sourceFingerprint: SourceFingerprint(
                standardizedPath: "/tmp/legacy.raw",
                fileSize: 10,
                modificationDate: nil
            )
        )
        let legacy = try JSONEncoder().encode(LegacyCLIPFixture(
            version: 1,
            backend: "clip",
            dimensions: 2,
            values: [1, 0]
        ))
        let migrated = try EmbeddingCodec.decodeMigrating(
            legacy,
            expectedDescriptor: descriptor,
            currentModelIdentity: model
        )
        #expect(migrated.requiresRewrite)
        #expect(migrated.sourceFormat == .rawCullCLIPVersion1)
        #expect(migrated.artifact.isInternallyConsistent)

        let formerIdentity = ModelIdentity(
            family: "clip",
            name: "current",
            assetName: "model.aimodel"
        )
        let typedVersion1 = try JSONEncoder().encode(TypedEmbeddingVersion1Fixture(
            version: 1,
            embedding: ImageEmbedding(
                backend: "clip",
                modelIdentity: formerIdentity,
                values: [1, 0]
            )
        ))
        #expect(try EmbeddingCodec.decode(typedVersion1).modelIdentity == formerIdentity)
        let typedMigration = try EmbeddingCodec.decodeMigrating(
            typedVersion1,
            expectedDescriptor: descriptor,
            currentModelIdentity: model
        )
        #expect(typedMigration.sourceFormat == .typedVersion1)
        #expect(typedMigration.requiresRewrite)
        #expect(typedMigration.artifact.embedding.modelIdentity == model)
    }

    @Test("Opaque artifact indexer recomputes the whole batch with fallback")
    func opaqueArtifactFallback() async throws {
        let sources = (0 ..< 3).map {
            AIImageSource(
                id: UUID(),
                url: URL(fileURLWithPath: "/tmp/artifact-\($0).raw"),
                displayName: "\($0).raw"
            )
        }
        let fallback = FakeArtifactProvider(name: "vision", shouldFail: false)
        let indexer = SimilarityArtifactIndexer(
            primaryProvider: FakeArtifactProvider(name: "clip", shouldFail: true),
            fallbackProvider: fallback,
            decoder: ExpansionImageDecoder(),
            fallbackPolicy: .wholeBatch,
            concurrencyLimit: 2
        )
        let result = try await indexer.index(sources)
        #expect(result.usedWholeBatchFallback)
        #expect(result.failures.isEmpty)
        #expect(result.artifacts.count == sources.count)
        #expect(result.artifacts.values.allSatisfy { $0.descriptor.backend == "vision" })

        let persisted = try SimilarityArtifactCodec.encode(try #require(result.artifacts.values.first))
        #expect(try SimilarityArtifactCodec.decode(persisted).descriptor.backend == "vision")
    }

    @Test("Vision feature prints stay opaque and provide their own metric")
    func visionFeaturePrintMetric() async throws {
        let backend = VisionFeaturePrintBackend()
        let image = try #require(expansionImage(width: 16, height: 16))
        let leftSource = AIImageSource(
            id: UUID(),
            url: URL(fileURLWithPath: "/tmp/vision-left.raw"),
            displayName: "left.raw"
        )
        let rightSource = AIImageSource(
            id: UUID(),
            url: URL(fileURLWithPath: "/tmp/vision-right.raw"),
            displayName: "right.raw"
        )
        let left = try await backend.artifact(for: image, source: leftSource)
        let right = try await backend.artifact(for: image, source: rightSource)
        let distance = try backend.distance(from: left, to: right)
        #expect(abs((distance ?? 1)) < 0.0001)
        #expect(left.descriptor.sourceFingerprint != right.descriptor.sourceFingerprint)
    }

    @Test("Catalog inventory extracts reusable geometry and quality")
    func catalogInventory() async throws {
        let root = try expansionTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let sourceURL = root.appendingPathComponent("catalog.raw")
        try Data("source".utf8).write(to: sourceURL)
        let source = AIImageSource(id: UUID(), url: sourceURL, displayName: "catalog.raw")
        let model = expansionModelIdentity()
        let memory = SubjectMaskMemoryStore()
        let repository = SubjectMaskRepository(
            configuration: SubjectMaskRepositoryConfiguration(
                modelIdentity: model,
                inputMaxSide: 64
            ),
            stores: [memory]
        )
        let key = await repository.storageKey(for: source)
        let result = try expansionSegmentationResult(
            source: source,
            model: model,
            prompt: .subject,
            mask: expansionMask(width: 20, height: 20, rect: CGRect(x: 5, y: 5, width: 10, height: 10)),
            confidence: 0.8
        )
        await memory.save(result, for: key)

        let index = SubjectMaskCatalogIndex()
        await index.startBuild(sources: [source], repository: repository, batchSize: 1)
        await index.waitForCurrentBuild()
        let entry = await index.inventory[source.id]
        #expect(entry?.hasMask == true)
        #expect(entry?.quality.level == .good)
        #expect(abs((entry?.geometry.coverage ?? 0) - 0.25) < 0.02)
    }

    @Test("Prompt fallback chooses the best cached mask")
    func promptMaskSelection() async throws {
        let source = AIImageSource(
            id: UUID(),
            url: URL(fileURLWithPath: "/tmp/selection.raw"),
            displayName: "selection.raw"
        )
        let model = expansionModelIdentity()
        let memory = SubjectMaskMemoryStore()
        let repository = SubjectMaskRepository(
            configuration: SubjectMaskRepositoryConfiguration(modelIdentity: model),
            stores: [memory]
        )
        let poor = try expansionSegmentationResult(
            source: source,
            model: model,
            prompt: .subject,
            mask: expansionMask(width: 20, height: 20, rect: CGRect(x: 0, y: 0, width: 20, height: 20)),
            confidence: 0.95
        )
        let good = try expansionSegmentationResult(
            source: source,
            model: model,
            prompt: .bird,
            mask: expansionMask(width: 20, height: 20, rect: CGRect(x: 5, y: 5, width: 10, height: 10)),
            confidence: 0.75
        )
        await memory.save(poor, for: await repository.storageKey(for: source, prompt: .subject))
        await memory.save(good, for: await repository.storageKey(for: source, prompt: .bird))

        let selection = try await SubjectMaskSelector(repository: repository).select(
            for: source,
            strategy: SubjectMaskSelectionStrategy(
                orderedPrompts: [.subject, .bird],
                minimumQuality: .good,
                acquisitionPolicy: .cacheOnly,
                stopsAtFirstAcceptableMask: false
            )
        )
        #expect(selection.selected?.result.prompt == .bird)
        #expect(selection.metMinimumQuality)
        #expect(selection.attempts.count == 2)
    }

    @Test("Batch transport has an explicit stable schema")
    func batchTransport() throws {
        let event = SegmentationBuildEvent.completed(SegmentationBuildSummary(
            total: 4,
            cached: 1,
            generated: 2,
            failed: 1
        ))
        let line = try SegmentationBuildTransportCodec.encodeLine(event)
        #expect(line.last == 0x0A)
        #expect(try SegmentationBuildTransportCodec.decodeLine(line) == event)
    }

    @Test("Batch pipeline reports generated progress and summary")
    func batchPipelineProgress() async throws {
        let sources = (0 ..< 2).map {
            AIImageSource(
                id: UUID(),
                url: URL(fileURLWithPath: "/tmp/batch-\($0).raw"),
                displayName: "batch-\($0).raw"
            )
        }
        let service = SegmentationService(
            provider: ExpansionSegmenter(),
            stores: [SubjectMaskMemoryStore()],
            maxSide: 64
        )
        let recorder = ExpansionEventRecorder()
        let summary = try await SegmentationBatchPipeline(
            service: service,
            decoder: ExpansionImageDecoder()
        ).generate(sources: sources) { event in
            await recorder.append(event)
        }
        #expect(summary == SegmentationBuildSummary(
            total: 2,
            cached: 0,
            generated: 2,
            failed: 0
        ))
        let events = await recorder.events
        #expect(events.first?.kind == .started)
        #expect(events.last?.kind == .completed)
        #expect(events.contains { $0.kind == .progress && $0.completed == 2 })
    }

    @Test("Segmentation cancellation crosses the service boundary")
    func segmentationCancellation() async throws {
        let source = AIImageSource(
            id: UUID(),
            url: URL(fileURLWithPath: "/tmp/cancel.raw"),
            displayName: "cancel.raw"
        )
        let service = SegmentationService(
            provider: ExpansionSegmenter(delay: .seconds(30)),
            maxSide: 64
        )
        let image = try #require(expansionImage(width: 8, height: 8))
        let task = Task {
            try await service.segment(image: image, source: source, prompt: .subject)
        }
        try await Task.sleep(for: .milliseconds(10))
        task.cancel()
        await #expect(throws: CancellationError.self) {
            try await task.value
        }
    }

    @Test("Disk store rejects stale and corrupt entries")
    func diskStoreValidation() async throws {
        let root = try expansionTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let sourceURL = root.appendingPathComponent("source.raw")
        try Data("one".utf8).write(to: sourceURL)
        let source = AIImageSource(id: UUID(), url: sourceURL, displayName: "source.raw")
        let model = expansionModelIdentity()
        let store = try SubjectMaskDiskStore(cacheDirectory: root.appendingPathComponent("masks"))
        let key = SubjectMaskStorageKey(
            source: source,
            sourceIdentity: SourceFileIdentity.read(from: sourceURL),
            prompt: .subject,
            modelIdentity: model,
            inputMaxSide: 64
        )
        let result = try expansionSegmentationResult(
            source: source,
            model: model,
            prompt: .subject,
            mask: expansionMask(width: 8, height: 8, rect: CGRect(x: 2, y: 2, width: 4, height: 4)),
            confidence: 0.8
        )
        try await store.save(result, for: key)

        try Data("changed-source".utf8).write(to: sourceURL)
        let staleKey = SubjectMaskStorageKey(
            source: source,
            sourceIdentity: SourceFileIdentity.read(from: sourceURL),
            prompt: .subject,
            modelIdentity: model,
            inputMaxSide: 64
        )
        #expect(await store.load(for: staleKey) == nil)

        let files = try FileManager.default.contentsOfDirectory(
            at: root.appendingPathComponent("masks"),
            includingPropertiesForKeys: nil
        )
        for file in files where file.pathExtension == "json" {
            try Data("not-json".utf8).write(to: file)
        }
        #expect(await store.load(for: key) == nil)
    }
}

private struct LegacyCLIPFixture: Codable {
    let version: Int
    let backend: String
    let dimensions: Int
    let values: [Float]
}

private struct TypedEmbeddingVersion1Fixture: Codable {
    let version: Int
    let embedding: ImageEmbedding
}

private struct FakeArtifactProvider: ImageSimilarityArtifactProviding {
    let backendDescriptor: SimilarityBackendDescriptor
    let shouldFail: Bool

    init(name: String, shouldFail: Bool) {
        self.backendDescriptor = SimilarityBackendDescriptor(
            backend: name,
            modelFingerprint: "\(name)-model",
            representation: "test",
            preprocessingVersion: "test",
            normalizationVersion: "test",
            configurationVersion: "test"
        )
        self.shouldFail = shouldFail
    }

    func artifact(for image: CGImage, source: AIImageSource) async throws -> SimilarityArtifact {
        if shouldFail { throw ExpansionTestError.expected }
        return SimilarityArtifact(
            descriptor: SimilarityArtifactDescriptor(
                backend: backendDescriptor,
                dimensions: nil,
                sourceFingerprint: SourceFingerprint(source: source)
            ),
            payload: Data(source.displayName.utf8)
        )
    }
}

private struct ExpansionImageDecoder: ImageDecoding {
    func image(for source: AIImageSource) async throws -> CGImage {
        try #require(expansionImage(width: 8, height: 8))
    }
}

private enum ExpansionTestError: Error {
    case expected
}

private actor ExpansionEventRecorder {
    private(set) var events: [SegmentationBuildEvent] = []

    func append(_ event: SegmentationBuildEvent) {
        events.append(event)
    }
}

private actor ExpansionSegmenter: SubjectSegmenting {
    nonisolated let modelIdentity = expansionModelIdentity()
    let delay: Duration?

    init(delay: Duration? = nil) {
        self.delay = delay
    }

    func segment(_ request: SubjectSegmentationRequest) async throws -> SubjectSegmentationResult {
        if let delay { try await Task.sleep(for: delay) }
        let source = AIImageSource(
            id: request.sourceID,
            url: URL(fileURLWithPath: "/tmp/fake.raw"),
            displayName: "fake.raw"
        )
        return try expansionSegmentationResult(
            source: source,
            model: modelIdentity,
            prompt: request.prompt,
            mask: request.image,
            confidence: 0.9
        )
    }
}

private func makeExpansionModelBundle(in root: URL) throws -> URL {
    let bundle = root.appendingPathComponent("CLIP", isDirectory: true)
    try FileManager.default.createDirectory(
        at: bundle.appendingPathComponent("tokenizer"),
        withIntermediateDirectories: true
    )
    try Data("{}".utf8).write(to: bundle.appendingPathComponent("tokenizer/tokenizer.json"))
    try Data("asset".utf8).write(to: bundle.appendingPathComponent("model.aimodel"))
    try JSONEncoder().encode(ModelBundleMetadata(
        name: "test",
        family: "clip",
        assets: ["main": "model.aimodel"]
    )).write(to: bundle.appendingPathComponent("metadata.json"))
    return bundle
}

private func expansionModelIdentity() -> ModelIdentity {
    ModelIdentity(family: "sam3", name: "test", assetName: "sam3.aimodel")
}

private func expansionSegmentationResult(
    source: AIImageSource,
    model: ModelIdentity,
    prompt: SubjectSegmentationPrompt,
    mask: CGImage?,
    confidence: Float
) throws -> SubjectSegmentationResult {
    let mask = try #require(mask)
    let size = CGSize(width: mask.width, height: mask.height)
    let timing = SubjectSegmentationTiming(totalMilliseconds: 1)
    return SubjectSegmentationResult(
        sourceID: source.id,
        requestID: UUID(),
        prompt: prompt,
        mask: mask,
        confidence: confidence,
        modelIdentity: model,
        inputSize: size,
        outputSize: size,
        timing: timing,
        diagnostics: SubjectSegmentationDiagnostics(
            modelIdentity: model,
            prompt: prompt,
            confidence: confidence,
            timing: timing,
            inputSize: size,
            outputSize: size
        )
    )
}

private func expansionTemporaryDirectory() throws -> URL {
    let url = FileManager.default.temporaryDirectory
        .appendingPathComponent("PhotoAIKitExpansionTests-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
}

private func expansionImage(width: Int, height: Int) -> CGImage? {
    expansionMask(
        width: width,
        height: height,
        rect: CGRect(x: 0, y: 0, width: width, height: height)
    )
}

private func expansionMask(width: Int, height: Int, rect: CGRect) -> CGImage? {
    guard let context = CGContext(
        data: nil,
        width: width,
        height: height,
        bitsPerComponent: 8,
        bytesPerRow: 0,
        space: CGColorSpaceCreateDeviceRGB(),
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    ) else { return nil }
    context.clear(CGRect(x: 0, y: 0, width: width, height: height))
    context.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
    context.fill(rect)
    return context.makeImage()
}
