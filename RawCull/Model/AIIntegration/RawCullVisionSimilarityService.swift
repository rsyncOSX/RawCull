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

nonisolated enum RawCullCLIPFailureStage: String, Equatable, Sendable {
    case imageDecoding = "image decoding"
    case clipInference = "CLIP inference"
}

nonisolated struct RawCullCLIPPrimaryFailure: Equatable, Sendable {
    let source: AIImageSource
    let stage: RawCullCLIPFailureStage
    let message: String
}

nonisolated struct RawCullSimilarityIndexingOutput: Sendable {
    let artifacts: [UUID: SimilarityArtifact]
    let failures: [RawCullSimilarityIndexingFailure]
    let primaryFailures: [RawCullCLIPPrimaryFailure]
    let usedWholeBatchFallback: Bool
    let primaryFailureDiagnostic: String?

    init(
        artifacts: [UUID: SimilarityArtifact],
        failures: [RawCullSimilarityIndexingFailure],
        primaryFailures: [RawCullCLIPPrimaryFailure] = [],
        usedWholeBatchFallback: Bool = false,
        primaryFailureDiagnostic: String? = nil,
    ) {
        self.artifacts = artifacts
        self.failures = failures
        self.primaryFailures = primaryFailures
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

/// CLIP similarity with finite-output validation and targeted recovery.
///
/// Valid CLIP artifacts are retained per image. A non-finite embedding is
/// retried once with the loaded provider, then once with a newly constructed
/// provider. Images that still fail remain without a similarity artifact and
/// are excluded from burst grouping by `SimilarityScoringModel`.
nonisolated struct RawCullCLIPSimilarityService: RawCullSimilarityServicing {
    static let defaultConcurrencyLimit = 1

    let backendDescriptor: SimilarityBackendDescriptor
    let artifactBackendDescriptors: [SimilarityBackendDescriptor]
    let requiresHomogeneousBatch = false

    private let primaryProvider: any ImageSimilarityArtifactProviding
    private let primaryComparator: any ImageSimilarityArtifactComparing
    private let replacementProviderFactory: (@Sendable () throws -> any ImageSimilarityArtifactProviding)?
    private let concurrencyLimit: Int

    init(
        backend: any ImageSimilarityBackend,
        replacementProviderFactory: (@Sendable () throws -> any ImageSimilarityArtifactProviding)? = nil,
        concurrencyLimit: Int = Self.defaultConcurrencyLimit,
    ) {
        self.init(
            primaryProvider: backend,
            primaryComparator: backend,
            replacementProviderFactory: replacementProviderFactory,
            concurrencyLimit: concurrencyLimit,
        )
    }

    init(
        primaryProvider: any ImageSimilarityArtifactProviding,
        primaryComparator: any ImageSimilarityArtifactComparing,
        replacementProviderFactory: (@Sendable () throws -> any ImageSimilarityArtifactProviding)? = nil,
        concurrencyLimit: Int = Self.defaultConcurrencyLimit,
    ) {
        self.primaryProvider = primaryProvider
        self.primaryComparator = primaryComparator
        self.replacementProviderFactory = replacementProviderFactory
        self.backendDescriptor = primaryProvider.backendDescriptor
        self.artifactBackendDescriptors = [primaryProvider.backendDescriptor]
        self.concurrencyLimit = max(1, concurrencyLimit)
    }

    func index(
        sources: [AIImageSource],
        maxPixelSize: Int,
        progress: (@Sendable (RawCullSimilarityIndexingProgress) async -> Void)? = nil,
    ) async throws -> RawCullSimilarityIndexingOutput {
        let failureRecorder = RawCullCLIPFailureRecorder()
        let recoveringProvider = RawCullRecoveringCLIPArtifactProvider(
            provider: primaryProvider,
            replacementProviderFactory: replacementProviderFactory,
        )
        let indexer = SimilarityArtifactIndexer(
            primaryProvider: RawCullDiagnosingArtifactProvider(
                provider: recoveringProvider,
                failureRecorder: failureRecorder,
            ),
            decoder: RawCullDiagnosingImageDecoder(
                decoder: RawCullSimilarityImageDecoder(maxPixelSize: maxPixelSize),
                failureRecorder: failureRecorder,
            ),
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
        let primaryFailures: [RawCullCLIPPrimaryFailure]
        let diagnostic: String?
        if result.failures.isEmpty {
            primaryFailures = []
            diagnostic = nil
        } else {
            let report = await failureRecorder.report(
                backend: backendDescriptor,
            )
            primaryFailures = report.failures
            diagnostic = report.diagnostic
        }
        return RawCullSimilarityIndexingOutput(
            artifacts: result.artifacts,
            failures: result.failures.map {
                RawCullSimilarityIndexingFailure(
                    source: $0.source,
                    message: $0.message,
                )
            },
            primaryFailures: primaryFailures,
            usedWholeBatchFallback: false,
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
    private var failures: [RawCullCLIPPrimaryFailure] = []

    func record(
        source: AIImageSource,
        stage: RawCullCLIPFailureStage,
        message: String,
    ) {
        guard !failures.contains(where: {
            $0.source.id == source.id && $0.stage == stage
        }) else { return }
        failures.append(
            RawCullCLIPPrimaryFailure(
                source: source,
                stage: stage,
                message: message,
            ),
        )
    }

    func report(backend: SimilarityBackendDescriptor) -> RawCullCLIPFailureReport {
        let sortedFailures = failures.sorted {
            if $0.source.displayName == $1.source.displayName {
                return $0.source.url.path < $1.source.url.path
            }
            return $0.source.displayName < $1.source.displayName
        }
        guard let firstFailure = sortedFailures.first else {
            return RawCullCLIPFailureReport(
                failures: [],
                diagnostic: "CLIP indexing failed, but no image-level failure was captured.",
            )
        }
        return RawCullCLIPFailureReport(
            failures: sortedFailures,
            diagnostic: "CLIP backend \(backend.modelFingerprint) failed for "
                + "\(sortedFailures.count) image(s); first failure "
                + "[\(firstFailure.source.displayName)] during \(firstFailure.stage.rawValue): "
                + firstFailure.message,
        )
    }
}

private actor RawCullRecoveringCLIPArtifactProvider:
    ImageSimilarityArtifactProviding
{
    nonisolated let backendDescriptor: SimilarityBackendDescriptor

    private var provider: any ImageSimilarityArtifactProviding
    private let replacementProviderFactory: (@Sendable () throws -> any ImageSimilarityArtifactProviding)?

    init(
        provider: any ImageSimilarityArtifactProviding,
        replacementProviderFactory: (@Sendable () throws -> any ImageSimilarityArtifactProviding)?,
    ) {
        self.provider = provider
        self.replacementProviderFactory = replacementProviderFactory
        self.backendDescriptor = provider.backendDescriptor
    }

    func artifact(
        for image: CGImage,
        source: AIImageSource,
    ) async throws -> SimilarityArtifact {
        do {
            return try await validatedArtifact(
                from: provider,
                image: image,
                source: source,
            )
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            guard Self.isNonFiniteEmbeddingError(error) else { throw error }
        }

        try Task.checkCancellation()
        do {
            return try await validatedArtifact(
                from: provider,
                image: image,
                source: source,
            )
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            guard Self.isNonFiniteEmbeddingError(error) else { throw error }
        }

        try Task.checkCancellation()
        guard let replacementProviderFactory else {
            throw RawCullCLIPRecoveryError.nonFiniteEmbedding
        }
        let replacement = try replacementProviderFactory()
        guard replacement.backendDescriptor == backendDescriptor else {
            throw RawCullCLIPRecoveryError.replacementBackendChanged
        }
        provider = replacement
        return try await validatedArtifact(
            from: replacement,
            image: image,
            source: source,
        )
    }

    private func validatedArtifact(
        from provider: any ImageSimilarityArtifactProviding,
        image: CGImage,
        source: AIImageSource,
    ) async throws -> SimilarityArtifact {
        let artifact = try await provider.artifact(for: image, source: source)
        guard backendDescriptor.representation == "normalized-float-vector-json-v1" else {
            return artifact
        }
        let embedding = try JSONDecoder().decode(ImageEmbedding.self, from: artifact.payload)
        guard !embedding.values.isEmpty,
              embedding.values.allSatisfy(\.isFinite)
        else {
            throw RawCullCLIPRecoveryError.nonFiniteEmbedding
        }
        return artifact
    }

    private nonisolated static func isNonFiniteEmbeddingError(_ error: Error) -> Bool {
        if let error = error as? RawCullCLIPRecoveryError {
            return error == .nonFiniteEmbedding
        }
        guard case let EncodingError.invalidValue(value, _) = error else {
            return false
        }
        if let value = value as? Float {
            return !value.isFinite
        }
        if let value = value as? Double {
            return !value.isFinite
        }
        return false
    }
}

private nonisolated enum RawCullCLIPRecoveryError: Error, Equatable, Sendable {
    case nonFiniteEmbedding
    case replacementBackendChanged
}

private nonisolated struct RawCullCLIPFailureReport: Sendable {
    let failures: [RawCullCLIPPrimaryFailure]
    let diagnostic: String
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
                source: source,
                stage: .clipInference,
                message: String(reflecting: error),
            )
            throw error
        }
    }
}

private nonisolated struct RawCullDiagnosingImageDecoder: ImageDecoding {
    private let decoder: any ImageDecoding
    private let failureRecorder: RawCullCLIPFailureRecorder

    init(
        decoder: any ImageDecoding,
        failureRecorder: RawCullCLIPFailureRecorder,
    ) {
        self.decoder = decoder
        self.failureRecorder = failureRecorder
    }

    func image(for source: AIImageSource) async throws -> CGImage {
        do {
            return try await decoder.image(for: source)
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            await failureRecorder.record(
                source: source,
                stage: .imageDecoding,
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
