import CoreGraphics
import Foundation
import ImageIO
import PhotoAnalysisKit

nonisolated struct AIImageSource: Codable, Equatable, Sendable {
    let id: UUID
    let url: URL
    let displayName: String
    let fileSize: Int64?
    let modificationDate: Date?

    init(id: UUID, url: URL, displayName: String) {
        self.id = id
        self.url = url
        self.displayName = displayName
        let values = try? url.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey])
        fileSize = values?.fileSize.map(Int64.init)
        modificationDate = values?.contentModificationDate
    }
}

nonisolated struct SourceFingerprint: Codable, Equatable, Hashable, Sendable {
    let standardizedPath: String
    let fileSize: Int64?
    let modificationDate: Date?

    init(source: AIImageSource) {
        standardizedPath = source.url.standardizedFileURL.path
        fileSize = source.fileSize
        modificationDate = source.modificationDate
    }
}

nonisolated struct SimilarityBackendDescriptor: Codable, Equatable, Hashable, Sendable {
    let backend: String
    let modelFingerprint: String
    let representation: String
    let preprocessingVersion: Int
    let normalizationVersion: Int
    let configurationVersion: Int

    static func vision(revision: Int) -> Self {
        Self(
            backend: "vision-feature-print",
            modelFingerprint: "apple-vision-revision-\(revision)",
            representation: "secure-vision-feature-print-v\(VisionFeaturePrint.currentRepresentationVersion)",
            preprocessingVersion: 1,
            normalizationVersion: 0,
            configurationVersion: revision,
        )
    }
}

nonisolated struct SimilarityArtifactDescriptor: Codable, Equatable, Hashable, Sendable {
    static let currentSchemaVersion = 2

    let schemaVersion: Int
    let backend: String
    let modelFingerprint: String
    let representation: String
    let preprocessingVersion: Int
    let normalizationVersion: Int
    let configurationVersion: Int
    let sourceFingerprint: SourceFingerprint

    init(source: AIImageSource, backend: SimilarityBackendDescriptor) {
        schemaVersion = Self.currentSchemaVersion
        self.backend = backend.backend
        modelFingerprint = backend.modelFingerprint
        representation = backend.representation
        preprocessingVersion = backend.preprocessingVersion
        normalizationVersion = backend.normalizationVersion
        configurationVersion = backend.configurationVersion
        sourceFingerprint = SourceFingerprint(source: source)
    }

    var backendDescriptor: SimilarityBackendDescriptor {
        SimilarityBackendDescriptor(
            backend: backend,
            modelFingerprint: modelFingerprint,
            representation: representation,
            preprocessingVersion: preprocessingVersion,
            normalizationVersion: normalizationVersion,
            configurationVersion: configurationVersion,
        )
    }
}

nonisolated struct SimilarityArtifact: Codable, Equatable, Sendable {
    let descriptor: SimilarityArtifactDescriptor
    let featurePrint: VisionFeaturePrint
}

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

nonisolated protocol RawCullSimilarityServicing: Sendable {
    var backendDescriptor: SimilarityBackendDescriptor { get }
    var artifactBackendDescriptors: [SimilarityBackendDescriptor] { get }
    var requiresHomogeneousBatch: Bool { get }

    func index(
        sources: [AIImageSource],
        maxPixelSize: Int,
        progress: (@Sendable (RawCullSimilarityIndexingProgress) async -> Void)?,
    ) async throws -> RawCullSimilarityIndexingOutput

    func distance(from left: SimilarityArtifact, to right: SimilarityArtifact) throws -> Float?
}

extension RawCullSimilarityServicing {
    nonisolated var artifactBackendDescriptors: [SimilarityBackendDescriptor] {
        [backendDescriptor]
    }

    nonisolated var requiresHomogeneousBatch: Bool { false }
}

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
        backendDescriptor = .vision(revision: backend.revision)
        self.concurrencyLimit = max(1, concurrencyLimit)
    }

    func index(
        sources: [AIImageSource],
        maxPixelSize: Int,
        progress: (@Sendable (RawCullSimilarityIndexingProgress) async -> Void)? = nil,
    ) async throws -> RawCullSimilarityIndexingOutput {
        var artifacts: [UUID: SimilarityArtifact] = [:]
        var failures: [RawCullSimilarityIndexingFailure] = []
        var nextIndex = 0
        var completed = 0

        await withTaskGroup(of: IndexedSource.self) { group in
            func addNext() {
                guard nextIndex < sources.count else { return }
                let source = sources[nextIndex]
                nextIndex += 1
                group.addTask {
                    do {
                        try Task.checkCancellation()
                        let image = try Self.decode(source.url, maxPixelSize: maxPixelSize)
                        let print = try await backend.featurePrint(for: image)
                        return .artifact(
                            source,
                            SimilarityArtifact(
                                descriptor: SimilarityArtifactDescriptor(
                                    source: source,
                                    backend: backendDescriptor,
                                ),
                                featurePrint: print,
                            ),
                        )
                    } catch {
                        return .failure(source, String(describing: error))
                    }
                }
            }

            for _ in 0 ..< min(concurrencyLimit, sources.count) { addNext() }
            while let result = await group.next() {
                switch result {
                case let .artifact(source, artifact):
                    artifacts[source.id] = artifact
                case let .failure(source, message):
                    failures.append(RawCullSimilarityIndexingFailure(source: source, message: message))
                }
                completed += 1
                await progress?(
                    RawCullSimilarityIndexingProgress(
                        completed: completed,
                        total: sources.count,
                        currentSourceID: result.source.id,
                    ),
                )
                addNext()
            }
        }
        try Task.checkCancellation()
        return RawCullSimilarityIndexingOutput(artifacts: artifacts, failures: failures)
    }

    func distance(from left: SimilarityArtifact, to right: SimilarityArtifact) throws -> Float? {
        guard left.descriptor.backendDescriptor == backendDescriptor,
              right.descriptor.backendDescriptor == backendDescriptor
        else { return nil }
        return try backend.distance(from: left.featurePrint, to: right.featurePrint)
    }

    private static func decode(_ url: URL, maxPixelSize: Int) throws -> CGImage {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else {
            throw VisionIndexingError.imageDecodeFailed(url.path)
        }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: max(1, maxPixelSize),
            kCGImageSourceShouldCacheImmediately: true,
        ]
        guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
        else { throw VisionIndexingError.imageDecodeFailed(url.path) }
        return image
    }
}

private nonisolated enum IndexedSource: Sendable {
    case artifact(AIImageSource, SimilarityArtifact)
    case failure(AIImageSource, String)

    var source: AIImageSource {
        switch self {
        case let .artifact(source, _), let .failure(source, _): source
        }
    }
}

private nonisolated enum VisionIndexingError: Error, Sendable {
    case imageDecodeFailed(String)
}

nonisolated enum RawCullSimilarityArtifactValidation {
    static func isCurrent(
        _ artifact: SimilarityArtifact,
        for source: AIImageSource,
        backend: SimilarityBackendDescriptor,
    ) -> Bool {
        artifact.descriptor.schemaVersion == SimilarityArtifactDescriptor.currentSchemaVersion
            && artifact.descriptor.backendDescriptor == backend
            && artifact.descriptor.sourceFingerprint == SourceFingerprint(source: source)
            && artifact.featurePrint.revision == backend.configurationVersion
            && artifact.featurePrint.representationVersion
                == VisionFeaturePrint.currentRepresentationVersion
    }

    static func isCurrent(
        _ artifact: SimilarityArtifact,
        for source: AIImageSource,
        backends: [SimilarityBackendDescriptor],
    ) -> Bool {
        backends.contains { isCurrent(artifact, for: source, backend: $0) }
    }
}
