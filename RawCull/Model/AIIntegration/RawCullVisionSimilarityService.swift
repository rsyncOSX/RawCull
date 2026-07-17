import CoreGraphics
import Foundation
import ImageIO
import PhotoAIContracts
import PhotoAIWorkflows
import VisionFeaturePrintBackend

nonisolated struct RawCullSimilarityIndexingProgress: Equatable, Sendable {
    let completed: Int
    let total: Int
    let currentSourceID: UUID?
}

nonisolated struct RawCullSimilarityIndexingFailure: Equatable, Sendable {
    let source: AIImageSource
    let message: String
}

nonisolated struct RawCullSimilarityIndexingOutput: Sendable {
    let artifacts: [UUID: SimilarityArtifact]
    let failures: [RawCullSimilarityIndexingFailure]
}

/// Narrow application boundary consumed by RawCull's similarity feature model.
/// RawCull owns source decoding and culling policy; PhotoAIKit owns artifacts,
/// Vision generation, validation identity, and distance semantics.
nonisolated protocol RawCullSimilarityServicing: Sendable {
    var backendDescriptor: SimilarityBackendDescriptor { get }

    func index(
        sources: [AIImageSource],
        maxPixelSize: Int,
        progress: (@Sendable (RawCullSimilarityIndexingProgress) async -> Void)?,
    ) async throws -> RawCullSimilarityIndexingOutput

    func distance(
        from left: SimilarityArtifact,
        to right: SimilarityArtifact,
    ) throws -> Float?
}

/// Vision-only Phase 2 service. CLIP selection remains intentionally disconnected
/// until its Settings control and whole-batch fallback are implemented together.
nonisolated struct RawCullVisionSimilarityService: RawCullSimilarityServicing {
    static let defaultConcurrencyLimit = 4

    let backendDescriptor: SimilarityBackendDescriptor

    private let backend: VisionFeaturePrintBackend
    private let concurrencyLimit: Int

    init(
        backend: VisionFeaturePrintBackend = VisionFeaturePrintBackend(),
        concurrencyLimit: Int = Self.defaultConcurrencyLimit,
    ) {
        self.backend = backend
        self.backendDescriptor = backend.backendDescriptor
        self.concurrencyLimit = max(1, concurrencyLimit)
    }

    func index(
        sources: [AIImageSource],
        maxPixelSize: Int,
        progress: (@Sendable (RawCullSimilarityIndexingProgress) async -> Void)? = nil,
    ) async throws -> RawCullSimilarityIndexingOutput {
        let indexer = SimilarityArtifactIndexer(
            primaryProvider: RawCullParallelVisionArtifactProvider(
                revision: backend.revision,
            ),
            decoder: RawCullSimilarityImageDecoder(maxPixelSize: maxPixelSize),
            fallbackPolicy: .none,
            concurrencyLimit: concurrencyLimit,
        )
        let result = try await indexer.index(sources) { update in
            await progress?(
                RawCullSimilarityIndexingProgress(
                    completed: update.completed,
                    total: update.total,
                    currentSourceID: update.currentSourceID,
                ),
            )
        }
        return RawCullSimilarityIndexingOutput(
            artifacts: result.artifacts,
            failures: result.failures.map {
                RawCullSimilarityIndexingFailure(
                    source: $0.source,
                    message: $0.message,
                )
            },
        )
    }

    func distance(
        from left: SimilarityArtifact,
        to right: SimilarityArtifact,
    ) throws -> Float? {
        try backend.distance(from: left, to: right)
    }
}

/// PhotoAIKit's current Vision backend is an actor and performs its synchronous
/// Vision request without suspension. A fresh stateless backend per item keeps
/// the package indexer's bounded parallelism effective instead of serializing
/// all generation through one actor instance.
private nonisolated struct RawCullParallelVisionArtifactProvider:
    ImageSimilarityArtifactProviding
{
    let revision: Int
    let backendDescriptor: SimilarityBackendDescriptor

    init(revision: Int) {
        self.revision = revision
        self.backendDescriptor = VisionFeaturePrintBackend(
            revision: revision,
        ).backendDescriptor
    }

    func artifact(
        for image: CGImage,
        source: AIImageSource,
    ) async throws -> SimilarityArtifact {
        try await VisionFeaturePrintBackend(revision: revision).artifact(
            for: image,
            source: source,
        )
    }
}

/// RawCull-specific RAW decoding adapter for PhotoAIKit's generic indexer.
nonisolated struct RawCullSimilarityImageDecoder: ImageDecoding {
    let maxPixelSize: Int

    func image(for source: AIImageSource) async throws -> CGImage {
        try Task.checkCancellation()
        if let image = await RawParserKitImageLoader.shared.thumbnailCGImage(
            for: source.url,
            maxPixelSize: maxPixelSize,
        ) {
            try Task.checkCancellation()
            return image
        }

        try Task.checkCancellation()
        let sourceOptions: [CFString: Any] = [kCGImageSourceShouldCache: false]
        guard let imageSource = CGImageSourceCreateWithURL(
            source.url as CFURL,
            sourceOptions as CFDictionary,
        ) else {
            throw RawCullSimilarityServiceError.imageDecodeFailed(source.url)
        }

        let thumbnailOptions: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageIfAbsent: false,
            kCGImageSourceCreateThumbnailFromImageAlways: false,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixelSize,
            kCGImageSourceShouldCacheImmediately: true,
        ]
        guard let image = CGImageSourceCreateThumbnailAtIndex(
            imageSource,
            0,
            thumbnailOptions as CFDictionary,
        ) else {
            throw RawCullSimilarityServiceError.imageDecodeFailed(source.url)
        }
        try Task.checkCancellation()
        return image
    }
}

nonisolated enum RawCullSimilarityServiceError: Error, Equatable, Sendable {
    case imageDecodeFailed(URL)
}

nonisolated enum RawCullSimilarityArtifactValidation {
    static func isCurrent(
        _ artifact: SimilarityArtifact,
        for source: AIImageSource,
        backend: SimilarityBackendDescriptor,
    ) -> Bool {
        let descriptor = artifact.descriptor
        return descriptor.schemaVersion == SimilarityArtifactDescriptor.currentSchemaVersion
            && descriptor.backend == backend.backend
            && descriptor.modelFingerprint == backend.modelFingerprint
            && descriptor.representation == backend.representation
            && descriptor.preprocessingVersion == backend.preprocessingVersion
            && descriptor.normalizationVersion == backend.normalizationVersion
            && descriptor.configurationVersion == backend.configurationVersion
            && descriptor.sourceFingerprint == SourceFingerprint(source: source)
    }
}
