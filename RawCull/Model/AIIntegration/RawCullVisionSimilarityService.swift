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
    let usedWholeBatchFallback: Bool
    let primaryFailureDiagnostic: String?

    init(
        artifacts: [UUID: SimilarityArtifact],
        failures: [RawCullSimilarityIndexingFailure],
        usedWholeBatchFallback: Bool = false,
        primaryFailureDiagnostic: String? = nil,
    ) {
        self.artifacts = artifacts
        self.failures = failures
        self.usedWholeBatchFallback = usedWholeBatchFallback
        self.primaryFailureDiagnostic = primaryFailureDiagnostic
    }
}

/// Narrow application boundary consumed by RawCull's similarity feature model.
/// RawCull owns source decoding and culling policy; PhotoAIKit owns artifacts,
/// backend generation, validation identity, and distance semantics.
nonisolated protocol RawCullSimilarityServicing: Sendable {
    var backendDescriptor: SimilarityBackendDescriptor { get }
    var artifactBackendDescriptors: [SimilarityBackendDescriptor] { get }
    var requiresHomogeneousBatch: Bool { get }

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

extension RawCullSimilarityServicing {
    nonisolated var artifactBackendDescriptors: [SimilarityBackendDescriptor] {
        [backendDescriptor]
    }

    nonisolated var requiresHomogeneousBatch: Bool { false }
}

/// Vision feature-print similarity service.
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

/// CLIP similarity with catalog-homogeneous Vision fallback.
///
/// PhotoAIKit retries the complete requested batch with Vision when any CLIP
/// artifact fails. RawCull records CLIP as the selected backend while accepting
/// either the CLIP descriptor or the exact Vision fallback descriptor in that
/// batch's persisted artifacts.
nonisolated struct RawCullCLIPSimilarityService: RawCullSimilarityServicing {
    static let defaultConcurrencyLimit = 2

    let backendDescriptor: SimilarityBackendDescriptor
    let artifactBackendDescriptors: [SimilarityBackendDescriptor]
    let requiresHomogeneousBatch = true

    private let primaryProvider: any ImageSimilarityArtifactProviding
    private let primaryComparator: any ImageSimilarityArtifactComparing
    private let fallbackProvider: any ImageSimilarityArtifactProviding
    private let fallbackComparator: any ImageSimilarityArtifactComparing
    private let concurrencyLimit: Int

    init(
        backend: any ImageSimilarityBackend,
        visionBackend: VisionFeaturePrintBackend = VisionFeaturePrintBackend(),
        concurrencyLimit: Int = Self.defaultConcurrencyLimit,
    ) {
        self.init(
            primaryProvider: backend,
            primaryComparator: backend,
            fallbackProvider: RawCullParallelVisionArtifactProvider(
                revision: visionBackend.revision,
            ),
            fallbackComparator: visionBackend,
            concurrencyLimit: concurrencyLimit,
        )
    }

    init(
        primaryProvider: any ImageSimilarityArtifactProviding,
        primaryComparator: any ImageSimilarityArtifactComparing,
        fallbackProvider: any ImageSimilarityArtifactProviding,
        fallbackComparator: any ImageSimilarityArtifactComparing,
        concurrencyLimit: Int = Self.defaultConcurrencyLimit,
    ) {
        self.primaryProvider = primaryProvider
        self.primaryComparator = primaryComparator
        self.fallbackProvider = fallbackProvider
        self.fallbackComparator = fallbackComparator
        self.backendDescriptor = primaryProvider.backendDescriptor
        self.artifactBackendDescriptors = [
            primaryProvider.backendDescriptor,
            fallbackProvider.backendDescriptor,
        ]
        self.concurrencyLimit = max(1, concurrencyLimit)
    }

    func index(
        sources: [AIImageSource],
        maxPixelSize: Int,
        progress: (@Sendable (RawCullSimilarityIndexingProgress) async -> Void)? = nil,
    ) async throws -> RawCullSimilarityIndexingOutput {
        let failureRecorder = RawCullCLIPFailureRecorder()
        let indexer = SimilarityArtifactIndexer(
            primaryProvider: RawCullDiagnosingArtifactProvider(
                provider: primaryProvider,
                failureRecorder: failureRecorder,
            ),
            fallbackProvider: fallbackProvider,
            decoder: RawCullSimilarityImageDecoder(maxPixelSize: maxPixelSize),
            fallbackPolicy: .wholeBatch,
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
        let diagnostic: String?
        if result.usedWholeBatchFallback {
            diagnostic = await failureRecorder.diagnostic(
                backend: backendDescriptor,
            ) ?? "CLIP whole-batch fallback was triggered before provider inference; "
                + "no CLIP provider error was captured."
        } else {
            diagnostic = nil
        }
        return RawCullSimilarityIndexingOutput(
            artifacts: result.artifacts,
            failures: result.failures.map {
                RawCullSimilarityIndexingFailure(
                    source: $0.source,
                    message: $0.message,
                )
            },
            usedWholeBatchFallback: result.usedWholeBatchFallback,
            primaryFailureDiagnostic: diagnostic,
        )
    }

    func distance(
        from left: SimilarityArtifact,
        to right: SimilarityArtifact,
    ) throws -> Float? {
        if Self.matches(left, right, backend: primaryComparator.backendDescriptor) {
            return try primaryComparator.distance(from: left, to: right)
        }
        if Self.matches(left, right, backend: fallbackComparator.backendDescriptor) {
            return try fallbackComparator.distance(from: left, to: right)
        }
        return nil
    }

    private static func matches(
        _ left: SimilarityArtifact,
        _ right: SimilarityArtifact,
        backend: SimilarityBackendDescriptor,
    ) -> Bool {
        left.descriptor.isCompatibleForDistance(with: right.descriptor)
            && left.descriptor.backend == backend.backend
            && left.descriptor.modelFingerprint == backend.modelFingerprint
            && left.descriptor.representation == backend.representation
            && left.descriptor.preprocessingVersion == backend.preprocessingVersion
            && left.descriptor.normalizationVersion == backend.normalizationVersion
            && left.descriptor.configurationVersion == backend.configurationVersion
    }
}

private actor RawCullCLIPFailureRecorder {
    private struct FailureGroup {
        var count: Int
        let sampleSource: String
    }

    private var failures: [String: FailureGroup] = [:]

    func record(sourceName: String, message: String) {
        if var existing = failures[message] {
            existing.count += 1
            failures[message] = existing
        } else {
            failures[message] = FailureGroup(
                count: 1,
                sampleSource: sourceName,
            )
        }
    }

    func diagnostic(backend: SimilarityBackendDescriptor) -> String? {
        guard !failures.isEmpty else { return nil }
        let total = failures.values.reduce(0) { $0 + $1.count }
        let details = failures
            .sorted { $0.key < $1.key }
            .prefix(8)
            .map { message, group in
                "\(group.count)x [\(group.sampleSource)] \(message)"
            }
            .joined(separator: " | ")
        let omitted = max(0, failures.count - 8)
        return "CLIP backend \(backend.modelFingerprint) failed for \(total) artifact(s): "
            + details
            + (omitted > 0 ? " | \(omitted) additional distinct error(s) omitted" : "")
    }
}

private nonisolated struct RawCullDiagnosingArtifactProvider:
    ImageSimilarityArtifactProviding
{
    let backendDescriptor: SimilarityBackendDescriptor

    private let provider: any ImageSimilarityArtifactProviding
    private let failureRecorder: RawCullCLIPFailureRecorder

    init(
        provider: any ImageSimilarityArtifactProviding,
        failureRecorder: RawCullCLIPFailureRecorder,
    ) {
        self.provider = provider
        self.failureRecorder = failureRecorder
        self.backendDescriptor = provider.backendDescriptor
    }

    func artifact(
        for image: CGImage,
        source: AIImageSource,
    ) async throws -> SimilarityArtifact {
        do {
            return try await provider.artifact(for: image, source: source)
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            await failureRecorder.record(
                sourceName: source.displayName,
                message: String(reflecting: error),
            )
            throw error
        }
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

    static func isCurrent(
        _ artifact: SimilarityArtifact,
        for source: AIImageSource,
        backends: [SimilarityBackendDescriptor],
    ) -> Bool {
        backends.contains { backend in
            isCurrent(artifact, for: source, backend: backend)
        }
    }
}
