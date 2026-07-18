import AppKit
import Foundation
import ImageIO
import PhotoAnalysisKit
@testable import RawCull
import PhotoAIContracts
import RawCullCore
import Testing
import UniformTypeIdentifiers

private actor SimilarityMigrationProgressRecorder {
    private var updates: [RawCullSimilarityIndexingProgress] = []

    func record(_ update: RawCullSimilarityIndexingProgress) {
        updates.append(update)
    }

    func snapshot() -> [RawCullSimilarityIndexingProgress] {
        updates
    }
}

private nonisolated let migrationTestBackend = SimilarityBackendDescriptor(
    backend: "migration-test",
    modelFingerprint: "byte-distance-v1",
    representation: "single-byte",
    preprocessingVersion: "none-v1",
    normalizationVersion: "byte-range-v1",
    configurationVersion: "test-v1",
)

private nonisolated let migrationCLIPBackend = SimilarityBackendDescriptor(
    backend: "clip",
    modelFingerprint: "test-clip-v1",
    representation: "single-byte",
    preprocessingVersion: "test-clip-v1",
    normalizationVersion: "byte-range-v1",
    configurationVersion: "test-v1",
)

private enum MigrationArtifactBackendError: Error {
    case generationFailed(String)
}

private actor MigrationArtifactCallRecorder {
    private var displayNames: [String] = []

    func record(_ displayName: String) {
        displayNames.append(displayName)
    }

    func snapshot() -> [String] {
        displayNames
    }
}

private actor NonFiniteArtifactProvider: ImageSimilarityArtifactProviding {
    nonisolated let backendDescriptor: SimilarityBackendDescriptor

    private let name: String
    private var failuresRemaining: Int
    private let recorder: MigrationArtifactCallRecorder

    init(
        name: String,
        backendDescriptor: SimilarityBackendDescriptor,
        failuresRemaining: Int,
        recorder: MigrationArtifactCallRecorder,
    ) {
        self.name = name
        self.backendDescriptor = backendDescriptor
        self.failuresRemaining = failuresRemaining
        self.recorder = recorder
    }

    func artifact(
        for _: CGImage,
        source: AIImageSource,
    ) async throws -> SimilarityArtifact {
        await recorder.record(name)
        if failuresRemaining > 0 {
            failuresRemaining -= 1
            throw EncodingError.invalidValue(
                Float.nan,
                EncodingError.Context(
                    codingPath: [],
                    debugDescription: "Unable to encode Float.nan directly in JSON.",
                ),
            )
        }
        return migrationArtifact(source: source, backend: backendDescriptor)
    }
}

private nonisolated struct MigrationArtifactBackend:
    ImageSimilarityArtifactProviding,
    ImageSimilarityArtifactComparing
{
    let backendDescriptor: SimilarityBackendDescriptor
    var failingDisplayNames: Set<String> = []
    var recorder: MigrationArtifactCallRecorder?

    func artifact(
        for _: CGImage,
        source: AIImageSource,
    ) async throws -> SimilarityArtifact {
        await recorder?.record(source.displayName)
        guard !failingDisplayNames.contains(source.displayName) else {
            throw MigrationArtifactBackendError.generationFailed(source.displayName)
        }
        return migrationArtifact(
            source: source,
            backend: backendDescriptor,
        )
    }

    func distance(
        from left: SimilarityArtifact,
        to right: SimilarityArtifact,
    ) throws -> Float? {
        guard left.descriptor.isCompatibleForDistance(with: right.descriptor),
              left.descriptor.backend == backendDescriptor.backend,
              left.descriptor.modelFingerprint == backendDescriptor.modelFingerprint,
              let leftValue = left.payload.first,
              let rightValue = right.payload.first
        else { return nil }
        return Float(abs(Int(leftValue) - Int(rightValue))) / 255
    }
}

private nonisolated func migrationArtifact(
    source: AIImageSource,
    backend: SimilarityBackendDescriptor,
) -> SimilarityArtifact {
    SimilarityArtifact(
        descriptor: SimilarityArtifactDescriptor(
            backend: backend,
            dimensions: 1,
            sourceFingerprint: SourceFingerprint(source: source),
        ),
        payload: Data([source.displayName.utf8.first ?? 0]),
    )
}

private nonisolated struct MigrationTestSimilarityService: RawCullSimilarityServicing {
    let backendDescriptor = migrationTestBackend

    func index(
        sources: [AIImageSource],
        maxPixelSize _: Int,
        progress: (@Sendable (RawCullSimilarityIndexingProgress) async -> Void)?,
    ) async throws -> RawCullSimilarityIndexingOutput {
        var artifacts: [UUID: SimilarityArtifact] = [:]
        for (offset, source) in sources.enumerated() {
            let value: UInt8 = switch source.displayName {
            case "anchor.ARW": 10
            case "near.ARW": 11
            default: 200
            }
            artifacts[source.id] = migrationTestArtifact(
                source: source,
                value: value,
            )
            await progress?(
                RawCullSimilarityIndexingProgress(
                    completed: offset + 1,
                    total: sources.count,
                    currentSourceID: source.id,
                ),
            )
        }
        return RawCullSimilarityIndexingOutput(artifacts: artifacts, failures: [])
    }

    func distance(
        from left: SimilarityArtifact,
        to right: SimilarityArtifact,
    ) throws -> Float? {
        guard left.descriptor.isCompatibleForDistance(with: right.descriptor),
              let leftValue = left.payload.first,
              let rightValue = right.payload.first
        else { return nil }
        return Float(abs(Int(leftValue) - Int(rightValue))) / 255
    }
}

private nonisolated func migrationTestArtifact(
    source: AIImageSource,
    value: UInt8,
) -> SimilarityArtifact {
    SimilarityArtifact(
        descriptor: SimilarityArtifactDescriptor(
            backend: migrationTestBackend,
            dimensions: 1,
            sourceFingerprint: SourceFingerprint(source: source),
        ),
        payload: Data([value]),
    )
}

private nonisolated func migrationTestFile(
    name: String,
    id: UUID = UUID(),
) -> FileItem {
    FileItem(
        id: id,
        url: URL(fileURLWithPath: "/tmp/PhotoAIKitSimilarityMigrationTests/\(name)"),
        name: name,
        size: 1,
        dateModified: Date(timeIntervalSince1970: 0),
        exifData: nil,
        afFocusNormalized: nil,
    )
}

private enum SimilarityMigrationFixtureError: Error {
    case contextCreationFailed
    case imageCreationFailed
    case destinationCreationFailed
    case imageWriteFailed
}

private nonisolated func makeMigrationImage(seed: Int) throws -> CGImage {
    let width = 256
    let height = 192
    guard let context = CGContext(
        data: nil,
        width: width,
        height: height,
        bitsPerComponent: 8,
        bytesPerRow: 0,
        space: CGColorSpaceCreateDeviceRGB(),
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue,
    ) else {
        throw SimilarityMigrationFixtureError.contextCreationFailed
    }

    context.setFillColor(NSColor(calibratedRed: 0.10, green: 0.14, blue: 0.20, alpha: 1).cgColor)
    context.fill(CGRect(x: 0, y: 0, width: width, height: height))
    let hue = CGFloat((seed * 47) % 255) / 255
    context.setFillColor(NSColor(calibratedHue: hue, saturation: 0.85, brightness: 0.95, alpha: 1).cgColor)
    context.fillEllipse(
        in: CGRect(
            x: 20 + (seed * 13) % 100,
            y: 24 + (seed * 19) % 70,
            width: 72,
            height: 72,
        ),
    )

    context.setStrokeColor(NSColor.white.cgColor)
    context.setLineWidth(8)
    context.move(to: CGPoint(x: 12, y: 12 + seed * 3))
    context.addLine(to: CGPoint(x: 244, y: 174 - seed * 5))
    context.strokePath()

    guard let image = context.makeImage() else {
        throw SimilarityMigrationFixtureError.imageCreationFailed
    }
    return image
}

private nonisolated func writeMigrationPNG(
    _ image: CGImage,
    to url: URL,
) throws {
    guard let destination = CGImageDestinationCreateWithURL(
        url as CFURL,
        UTType.png.identifier as CFString,
        1,
        nil,
    ) else {
        throw SimilarityMigrationFixtureError.destinationCreationFailed
    }
    CGImageDestinationAddImage(destination, image, nil)
    guard CGImageDestinationFinalize(destination) else {
        throw SimilarityMigrationFixtureError.imageWriteFailed
    }
}

private nonisolated func migrationCacheFileName(for catalog: URL) -> String {
    let safe = Data(catalog.path.utf8)
        .base64EncodedString()
        .replacingOccurrences(of: "/", with: "_")
        .replacingOccurrences(of: "+", with: "-")
        .replacingOccurrences(of: "=", with: "")
    return "\(safe).json"
}

@MainActor
@Suite("PhotoAIKit similarity migration", .serialized)
struct PhotoAIKitSimilarityMigrationTests {
    @Test("CLIP retains successful artifacts and excludes failed images", .tags(.critical))
    func clipRetainsPartialArtifacts() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("PhotoAIKitCLIPPartial-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let urls = try (0 ..< 2).map { index in
            let url = root.appendingPathComponent("image-\(index).png")
            try writeMigrationPNG(makeMigrationImage(seed: index), to: url)
            return url
        }
        let sources = urls.map {
            AIImageSource(id: UUID(), url: $0, displayName: $0.lastPathComponent)
        }
        let primary = MigrationArtifactBackend(
            backendDescriptor: migrationCLIPBackend,
            failingDisplayNames: [sources[1].displayName],
        )
        let service = RawCullCLIPSimilarityService(
            primaryProvider: primary,
            primaryComparator: primary,
            concurrencyLimit: 2,
        )

        let output = try await service.index(
            sources: sources,
            maxPixelSize: SimilarityScoringModel.embeddingThumbnailMaxPixelSize,
            progress: nil,
        )

        #expect(!output.usedWholeBatchFallback)
        #expect(output.failures.count == 1)
        #expect(output.artifacts.count == 1)
        let diagnostic = try #require(output.primaryFailureDiagnostic)
        #expect(diagnostic.contains(sources[1].displayName))
        #expect(diagnostic.contains("generationFailed"))
        let primaryFailure = try #require(output.primaryFailures.first)
        #expect(output.primaryFailures.count == 1)
        #expect(primaryFailure.source == sources[1])
        #expect(primaryFailure.stage == .clipInference)
        #expect(primaryFailure.message.contains("generationFailed"))
        #expect(output.artifacts[sources[0].id] != nil)
        #expect(output.artifacts[sources[1].id] == nil)
        #expect(service.backendDescriptor == migrationCLIPBackend)
        #expect(service.artifactBackendDescriptors == [migrationCLIPBackend])
    }

    @Test("CLIP partial indexing captures image decoding failures")
    func clipPartialIndexingCapturesImageDecodingFailure() async throws {
        let missingURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("MissingCLIPImage-\(UUID().uuidString).raw")
        let source = AIImageSource(
            id: UUID(),
            url: missingURL,
            displayName: missingURL.lastPathComponent,
        )
        let primary = MigrationArtifactBackend(
            backendDescriptor: migrationCLIPBackend,
        )
        let service = RawCullCLIPSimilarityService(
            primaryProvider: primary,
            primaryComparator: primary,
        )

        let output = try await service.index(
            sources: [source],
            maxPixelSize: SimilarityScoringModel.embeddingThumbnailMaxPixelSize,
            progress: nil,
        )

        #expect(!output.usedWholeBatchFallback)
        #expect(output.artifacts.isEmpty)
        #expect(output.failures.count == 1)
        let primaryFailure = try #require(output.primaryFailures.first)
        #expect(output.primaryFailures.count == 1)
        #expect(primaryFailure.source == source)
        #expect(primaryFailure.stage == .imageDecoding)
        #expect(primaryFailure.message.contains("imageDecodeFailed"))
        #expect(output.primaryFailureDiagnostic?.contains(source.displayName) == true)
    }

    @Test("CLIP reindexes only missing or stale artifacts", .tags(.critical))
    func clipReindexesOnlyMissingArtifacts() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("PhotoAIKitCLIPReindex-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let urls = try (0 ..< 2).map { index in
            let url = root.appendingPathComponent("image-\(index).png")
            try writeMigrationPNG(makeMigrationImage(seed: index), to: url)
            return url
        }
        let files = urls.map { url in
            FileItem(
                id: UUID(),
                url: url,
                name: url.lastPathComponent,
                size: 1,
                dateModified: Date(timeIntervalSince1970: 0),
                exifData: nil,
                afFocusNormalized: nil,
            )
        }
        let recorder = MigrationArtifactCallRecorder()
        let primary = MigrationArtifactBackend(
            backendDescriptor: migrationCLIPBackend,
            recorder: recorder,
        )
        let service = RawCullCLIPSimilarityService(
            primaryProvider: primary,
            primaryComparator: primary,
        )
        let model = SimilarityScoringModel(similarityService: service)
        let existingSource = SimilarityScoringModel.source(for: files[0])
        model.embeddings[files[0].id] = migrationArtifact(
            source: existingSource,
            backend: migrationCLIPBackend,
        )

        await model.indexFiles(files)

        let indexedNames = await recorder.snapshot()
        #expect(indexedNames == [files[1].name])
        #expect(model.embeddings.count == files.count)
        #expect(model.embeddings.values.allSatisfy {
            $0.descriptor.backend == migrationCLIPBackend.backend
        })
    }

    @Test("Non-finite CLIP output retries once then reloads the provider", .tags(.critical))
    func clipReloadsProviderAfterNonFiniteRetry() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("PhotoAIKitCLIPRecovery-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let imageURL = root.appendingPathComponent("recovery.png")
        try writeMigrationPNG(makeMigrationImage(seed: 7), to: imageURL)
        let source = AIImageSource(
            id: UUID(),
            url: imageURL,
            displayName: imageURL.lastPathComponent,
        )
        let recorder = MigrationArtifactCallRecorder()
        let initial = NonFiniteArtifactProvider(
            name: "initial",
            backendDescriptor: migrationCLIPBackend,
            failuresRemaining: 2,
            recorder: recorder,
        )
        let comparator = MigrationArtifactBackend(
            backendDescriptor: migrationCLIPBackend,
        )
        let service = RawCullCLIPSimilarityService(
            primaryProvider: initial,
            primaryComparator: comparator,
            replacementProviderFactory: {
                NonFiniteArtifactProvider(
                    name: "replacement",
                    backendDescriptor: migrationCLIPBackend,
                    failuresRemaining: 0,
                    recorder: recorder,
                )
            },
        )

        let output = try await service.index(
            sources: [source],
            maxPixelSize: SimilarityScoringModel.embeddingThumbnailMaxPixelSize,
            progress: nil,
        )

        #expect(await recorder.snapshot() == ["initial", "initial", "replacement"])
        #expect(output.artifacts[source.id] != nil)
        #expect(output.failures.isEmpty)
        #expect(output.primaryFailures.isEmpty)
    }

    @Test("Persistent non-finite CLIP output is excluded after provider reload", .tags(.critical))
    func clipExcludesPersistentNonFiniteOutput() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("PhotoAIKitCLIPPersistentNaN-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let imageURL = root.appendingPathComponent("persistent-nan.png")
        try writeMigrationPNG(makeMigrationImage(seed: 8), to: imageURL)
        let source = AIImageSource(
            id: UUID(),
            url: imageURL,
            displayName: imageURL.lastPathComponent,
        )
        let recorder = MigrationArtifactCallRecorder()
        let initial = NonFiniteArtifactProvider(
            name: "initial",
            backendDescriptor: migrationCLIPBackend,
            failuresRemaining: 2,
            recorder: recorder,
        )
        let comparator = MigrationArtifactBackend(
            backendDescriptor: migrationCLIPBackend,
        )
        let service = RawCullCLIPSimilarityService(
            primaryProvider: initial,
            primaryComparator: comparator,
            replacementProviderFactory: {
                NonFiniteArtifactProvider(
                    name: "replacement",
                    backendDescriptor: migrationCLIPBackend,
                    failuresRemaining: 1,
                    recorder: recorder,
                )
            },
        )

        let output = try await service.index(
            sources: [source],
            maxPixelSize: SimilarityScoringModel.embeddingThumbnailMaxPixelSize,
            progress: nil,
        )

        #expect(await recorder.snapshot() == ["initial", "initial", "replacement"])
        #expect(output.artifacts.isEmpty)
        #expect(output.failures.count == 1)
        #expect(output.primaryFailures.count == 1)
        #expect(output.primaryFailures.first?.source == source)
        #expect(output.primaryFailures.first?.stage == .clipInference)
    }

    @Test("Burst grouping excludes unindexed images and preserves hard boundaries", .tags(.critical))
    func groupingExcludesUnindexedImages() async throws {
        let model = SimilarityScoringModel(
            similarityService: MigrationTestSimilarityService(),
        )
        let first = migrationTestFile(name: "first.ARW")
        let excluded = migrationTestFile(name: "excluded.ARW")
        let last = migrationTestFile(name: "last.ARW")
        model.embeddings[first.id] = migrationTestArtifact(
            source: SimilarityScoringModel.source(for: first),
            value: 10,
        )
        model.embeddings[last.id] = migrationTestArtifact(
            source: SimilarityScoringModel.source(for: last),
            value: 11,
        )

        await model.groupBursts(files: [first, excluded, last])

        #expect(model.burstGroups.map(\.fileIDs) == [[first.id], [last.id]])
        #expect(model.burstGroupLookup[excluded.id] == nil)
        #expect(model.burstBoundaryEvidence.isEmpty)
    }

    @Test("PhotoAIKit Vision indexing produces complete reusable artifacts", .tags(.critical))
    func visionArtifactsAreDescriptorComplete() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("PhotoAIKitVisionArtifacts-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let urls = try (0 ..< 3).map { index in
            let url = root.appendingPathComponent("image-\(index).png")
            try writeMigrationPNG(makeMigrationImage(seed: index), to: url)
            return url
        }
        let sources = urls.map {
            AIImageSource(id: UUID(), url: $0, displayName: $0.lastPathComponent)
        }
        let progressRecorder = SimilarityMigrationProgressRecorder()
        let service = RawCullVisionSimilarityService(concurrencyLimit: 2)

        let output = try await service.index(
            sources: sources,
            maxPixelSize: SimilarityScoringModel.embeddingThumbnailMaxPixelSize,
        ) { update in
            await progressRecorder.record(update)
        }
        let progress = await progressRecorder.snapshot()

        #expect(output.failures.isEmpty)
        #expect(output.artifacts.count == sources.count)
        #expect(progress.last?.completed == sources.count)
        #expect(progress.last?.total == sources.count)
        #expect(service.backendDescriptor.backend == "vision-feature-print")
        #expect(service.backendDescriptor.modelFingerprint.hasSuffix("revision-2"))

        for source in sources {
            let artifact = try #require(output.artifacts[source.id])
            #expect(RawCullSimilarityArtifactValidation.isCurrent(
                artifact,
                for: source,
                backend: service.backendDescriptor,
            ))
            #expect(artifact.descriptor.schemaVersion == SimilarityArtifactDescriptor.currentSchemaVersion)
            #expect(!artifact.payload.isEmpty)

            let roundTrip = try JSONDecoder().decode(
                SimilarityArtifact.self,
                from: JSONEncoder().encode(artifact),
            )
            #expect(roundTrip == artifact)
        }

        let first = try #require(output.artifacts[sources[0].id])
        let optionalSameImageDistance = try service.distance(from: first, to: first)
        let sameImageDistance = try #require(optionalSameImageDistance)
        #expect(abs(sameImageDistance) < 0.000_001)
    }

    @Test("RawCull ranking policy is preserved behind the PhotoAIKit boundary", .tags(.critical))
    func rankingPolicyIsPreserved() async throws {
        let model = SimilarityScoringModel(
            similarityService: MigrationTestSimilarityService(),
        )
        let anchor = migrationTestFile(name: "anchor.ARW")
        let near = migrationTestFile(name: "near.ARW")
        let far = migrationTestFile(name: "far.ARW")

        await model.indexFiles([anchor, near, far])
        await model.rankSimilar(
            to: anchor.id,
            using: [anchor, near, far],
            saliencyInfo: [
                anchor.id: SaliencyInfo(subjectLabel: "bird"),
                near.id: SaliencyInfo(subjectLabel: "person"),
                far.id: SaliencyInfo(subjectLabel: "bird"),
            ],
        )

        let nearDistance = try #require(model.distances[near.id])
        let farDistance = try #require(model.distances[far.id])
        #expect(abs(nearDistance - (1 / 255 + 0.10)) < 0.000_1)
        #expect(abs(farDistance - (190 / 255)) < 0.000_1)
        #expect(nearDistance < farDistance)
        #expect(model.anchorFileID == anchor.id)
        #expect(model.sortBySimilarity)
    }

    @Test("Schema 7 burst artifacts are rejected and schema 8 rebuild loads", .tags(.critical))
    func legacyCacheIsInvalidated() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("PhotoAIKitCacheMigration-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let catalog = URL(fileURLWithPath: "/tmp/catalog-\(UUID().uuidString)")
        let file = migrationTestFile(name: "cached.ARW")
        let source = SimilarityScoringModel.source(for: file)
        let sharpnessSignature = BurstSharpnessSignature(
            thumbnailMaxPixelSize: 512,
            config: FocusDetectorConfig(),
        )
        let similaritySignature = BurstSimilaritySignature(
            groupingConfig: BurstGroupingConfig(),
            backendDescriptor: migrationTestBackend,
            artifactSchemaVersion: SimilarityArtifactDescriptor.currentSchemaVersion,
            embeddingThumbnailMaxPixelSize: SimilarityScoringModel.embeddingThumbnailMaxPixelSize,
            embeddingPipelineVersion: SimilarityScoringModel.embeddingPipelineVersion,
        )
        var snapshot = BurstAnalysisCacheSnapshot(
            schemaVersion: 7,
            algorithmVersion: BurstGroupingConfig.algorithmVersion,
            catalogPath: catalog.path,
            thumbnailMaxPixelSize: 512,
            sharpnessSignature: sharpnessSignature,
            similaritySignature: similaritySignature,
            files: [
                BurstAnalysisCacheFile(
                    id: file.id,
                    path: file.url.path,
                    size: file.size,
                    modificationDate: file.dateModified,
                )
            ],
            embeddings: [file.id: migrationTestArtifact(source: source, value: 1)],
            sharpnessScores: [:],
            saliencyInfo: [:],
            groups: [],
            boundaryEvidence: [],
            results: [],
            reviewStateSnapshots: [],
        )
        let cache = BurstAnalysisCache(cacheDirectory: root)

        await cache.save(snapshot, catalog: catalog)
        let rejected = await cache.load(
            catalog: catalog,
            files: [file],
            thumbnailMaxPixelSize: 512,
            sharpnessSignature: sharpnessSignature,
            similaritySignature: similaritySignature,
        )
        #expect(rejected == nil)
        #expect(FileManager.default.fileExists(
            atPath: root.appendingPathComponent(migrationCacheFileName(for: catalog)).path,
        ))

        snapshot.schemaVersion = BurstAnalysisCache.schemaVersion
        await cache.save(snapshot, catalog: catalog)
        let rebuilt = await cache.load(
            catalog: catalog,
            files: [file],
            thumbnailMaxPixelSize: 512,
            sharpnessSignature: sharpnessSignature,
            similaritySignature: similaritySignature,
        )
        #expect(rebuilt == snapshot)
    }

    @Test("Partial CLIP cache excludes files without validated artifacts", .tags(.critical))
    func partialCLIPCache() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("PhotoAIKitPartialCache-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let catalog = URL(fileURLWithPath: "/tmp/catalog-\(UUID().uuidString)")
        let indexed = migrationTestFile(name: "indexed.ARW")
        let excluded = migrationTestFile(name: "excluded.ARW")
        let files = [indexed, excluded]
        let sharpnessSignature = BurstSharpnessSignature(
            thumbnailMaxPixelSize: 512,
            config: FocusDetectorConfig(),
        )
        let similaritySignature = BurstSimilaritySignature(
            groupingConfig: BurstGroupingConfig(),
            backendDescriptor: migrationTestBackend,
            artifactSchemaVersion: SimilarityArtifactDescriptor.currentSchemaVersion,
            embeddingThumbnailMaxPixelSize: SimilarityScoringModel.embeddingThumbnailMaxPixelSize,
            embeddingPipelineVersion: SimilarityScoringModel.embeddingPipelineVersion,
        )
        var snapshot = BurstAnalysisCacheSnapshot(
            schemaVersion: BurstAnalysisCache.schemaVersion,
            algorithmVersion: BurstGroupingConfig.algorithmVersion,
            catalogPath: catalog.path,
            thumbnailMaxPixelSize: 512,
            sharpnessSignature: sharpnessSignature,
            similaritySignature: similaritySignature,
            files: files.map {
                BurstAnalysisCacheFile(
                    id: $0.id,
                    path: $0.url.path,
                    size: $0.size,
                    modificationDate: $0.dateModified,
                )
            },
            embeddings: [
                indexed.id: migrationTestArtifact(
                    source: SimilarityScoringModel.source(for: indexed),
                    value: 1,
                ),
            ],
            sharpnessScores: [:],
            saliencyInfo: [:],
            groups: [BurstGroup(id: 0, fileIDs: [indexed.id])],
            boundaryEvidence: [],
            results: [],
            reviewStateSnapshots: [],
        )
        let cache = BurstAnalysisCache(cacheDirectory: root)

        await cache.save(snapshot, catalog: catalog)
        let loaded = await cache.load(
            catalog: catalog,
            files: files,
            thumbnailMaxPixelSize: 512,
            sharpnessSignature: sharpnessSignature,
            similaritySignature: similaritySignature,
        )
        #expect(loaded == snapshot)

        snapshot.groups = [BurstGroup(id: 0, fileIDs: [indexed.id, excluded.id])]
        await cache.save(snapshot, catalog: catalog)
        let unsafe = await cache.load(
            catalog: catalog,
            files: files,
            thumbnailMaxPixelSize: 512,
            sharpnessSignature: sharpnessSignature,
            similaritySignature: similaritySignature,
        )
        #expect(unsafe == nil)
    }

    @Test(
        "PhotoAIKit Vision indexing and ranking benchmark",
        .timeLimit(.minutes(1)),
        .tags(.performance),
    )
    func visionIndexingAndRankingBenchmark() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("PhotoAIKitVisionBenchmark-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let sources = try (0 ..< 12).map { index in
            let url = root.appendingPathComponent("benchmark-\(index).png")
            try writeMigrationPNG(makeMigrationImage(seed: index), to: url)
            return AIImageSource(id: UUID(), url: url, displayName: url.lastPathComponent)
        }
        let service = RawCullVisionSimilarityService(concurrencyLimit: 4)
        let clock = ContinuousClock()

        let indexingStart = clock.now
        let output = try await service.index(
            sources: sources,
            maxPixelSize: SimilarityScoringModel.embeddingThumbnailMaxPixelSize,
            progress: nil,
        )
        let indexingDuration = indexingStart.duration(to: clock.now)
        let artifacts = try sources.map { source in
            try #require(output.artifacts[source.id])
        }

        let comparisonStart = clock.now
        let comparisonCount = try await Task { @concurrent in
            var count = 0
            for index in 0 ..< 500 {
                try Task.checkCancellation()
                let left = artifacts[index % artifacts.count]
                let right = artifacts[(index + 1) % artifacts.count]
                if try service.distance(from: left, to: right) != nil {
                    count += 1
                }
            }
            return count
        }.value
        let comparisonDuration = comparisonStart.duration(to: clock.now)

        print(
            "PhotoAIKit Vision benchmark: indexed \(artifacts.count) images in \(indexingDuration); "
                + "computed \(comparisonCount) distances in \(comparisonDuration)",
        )
        #expect(output.failures.isEmpty)
        #expect(artifacts.count == sources.count)
        #expect(comparisonCount == 500)
        #expect(indexingDuration < .seconds(30))
        #expect(comparisonDuration < .seconds(30))
    }
}
