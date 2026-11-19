import CoreGraphics
import Foundation
import PhotoAnalysisKit
import PhotoAIContracts
@testable import RawCull
import RawCullCore

@MainActor
final class CoordinatorCacheRepository: BurstAnalysisCacheRepository {
    var snapshot: BurstAnalysisCacheSnapshot?
    var migrationCandidate: BurstAnalysisCacheSnapshot?
    var invalidateOnLoad = false
    var isValid = true
    private(set) var loadCount = 0
    private(set) var migrationLoadCount = 0
    private(set) var savedSnapshots: [BurstAnalysisCacheSnapshot] = []

    func load(
        catalog _: URL,
        files _: [FileItem],
        thumbnailMaxPixelSize _: Int,
        sharpnessSignature _: BurstSharpnessSignature,
        similaritySignature _: BurstSimilaritySignature,
    ) async -> BurstAnalysisCacheSnapshot? {
        loadCount += 1
        if invalidateOnLoad {
            isValid = false
        }
        return snapshot
    }

    func loadMigrationCandidate(catalog _: URL) async -> BurstAnalysisCacheSnapshot? {
        migrationLoadCount += 1
        return migrationCandidate
    }

    func save(_ snapshot: BurstAnalysisCacheSnapshot, catalog _: URL) async -> Bool {
        savedSnapshots.append(snapshot)
        return true
    }

    func delete(catalog _: URL) async {}
}

@MainActor
struct CoordinatorComputeHarness {
    let coordinator: BurstAnalysisCoordinator
    let repository: CoordinatorCacheRepository
    let request: BurstAnalysisPipelineRequest
    let sharpnessModel: SharpnessScoringModel
    let similarityModel: SimilarityScoringModel
}

@MainActor
func makeCoordinatorComputeHarness(
    catalog: URL,
    files: [FileItem],
) -> CoordinatorComputeHarness {
    makeCoordinatorHarness(catalog: catalog, files: files)
}

@MainActor
func makeCoordinatorHarness(
    catalog: URL,
    files: [FileItem],
    sharpnessAdapter: RawCullPhotoAnalysisAdapter? = nil,
) -> CoordinatorComputeHarness {
    let model = SimilarityScoringModel(
        artifactStore: makeIsolatedSimilarityArtifactStore(),
    )
    let feature = RawCullSimilarityFeature(similarityModel: model)
    let repository = CoordinatorCacheRepository()
    let sharpnessModel = SharpnessScoringModel(analysisAdapterOverride: sharpnessAdapter)
    let coordinator = BurstAnalysisCoordinator(
        sharpnessModel: sharpnessModel,
        similarityFeature: feature,
        similarityModel: model,
        cacheRepository: repository,
    )
    let similaritySignature = BurstSimilaritySignature(
        groupingConfig: BurstGroupingConfig(),
        backendDescriptor: model.backendDescriptor,
        artifactBackendDescriptors: model.artifactBackendDescriptors,
        artifactSchemaVersion: SimilarityArtifactDescriptor.currentSchemaVersion,
        embeddingThumbnailMaxPixelSize: SimilarityScoringModel.embeddingThumbnailMaxPixelSize,
        embeddingPipelineVersion: SimilarityScoringModel.embeddingPipelineVersion,
    )
    let request = BurstAnalysisPipelineRequest(
        catalogIdentity: catalog,
        orderedFiles: files,
        sharpnessSignature: sharpnessModel.scoringSignature,
        similaritySignature: similaritySignature,
        generation: 1,
        configuration: BurstAnalysisPipelineConfiguration(
            thumbnailMaxPixelSize: sharpnessModel.effectiveThumbnailMaxPixelSize,
            grouping: similaritySignature.groupingConfig,
            cacheSchemaVersion: BurstAnalysisCache.schemaVersion,
            groupingAlgorithmVersion: BurstGroupingConfig.algorithmVersion,
        ),
    )
    return CoordinatorComputeHarness(
        coordinator: coordinator,
        repository: repository,
        request: request,
        sharpnessModel: sharpnessModel,
        similarityModel: model,
    )
}

extension BurstAnalysisPipelineRequest {
    func withSharpnessSignature(_ signature: BurstSharpnessSignature) -> BurstAnalysisPipelineRequest {
        BurstAnalysisPipelineRequest(
            catalogIdentity: catalogIdentity,
            orderedFiles: orderedFiles,
            sharpnessSignature: signature,
            similaritySignature: similaritySignature,
            generation: generation,
            configuration: configuration,
        )
    }
}

/// Synthetic adapter that returns a checkerboard for every file, so scoring
/// runs without touching the file system.
nonisolated func makeCoordinatorSharpnessAdapter() -> RawCullPhotoAnalysisAdapter {
    RawCullPhotoAnalysisAdapter(inputLoaderOverride: { file, _, _ in
        guard let image = makeCoordinatorCheckerboard() else { return nil }
        return PhotoAnalysisInput(
            image: image,
            iso: file.iso,
            aperture: file.aperture,
            normalizedAFPoint: file.normalizedAFPoint,
        )
    })
}

nonisolated func makeCoordinatorCheckerboard(size: Int = 128) -> CGImage? {
    guard let colorSpace = CGColorSpace(name: CGColorSpace.sRGB),
          let context = CGContext(
              data: nil,
              width: size,
              height: size,
              bitsPerComponent: 8,
              bytesPerRow: size * 4,
              space: colorSpace,
              bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue,
          )
    else { return nil }
    context.setFillColor(gray: 0.08, alpha: 1)
    context.fill(CGRect(x: 0, y: 0, width: size, height: size))
    context.setFillColor(gray: 0.92, alpha: 1)
    for y in stride(from: 0, to: size, by: 8) {
        for x in stride(from: 0, to: size, by: 8) where (x / 8 + y / 8).isMultiple(of: 2) {
            context.fill(CGRect(x: x, y: y, width: 8, height: 8))
        }
    }
    return context.makeImage()
}

nonisolated func makeCoordinatorFile(_ name: String) -> FileItem {
    FileItem(
        url: URL(fileURLWithPath: "/tmp/\(name)"),
        name: name,
        size: 1,
        dateModified: Date(timeIntervalSince1970: 1),
        captureDate: Date(timeIntervalSince1970: 1),
        exifData: nil,
        afFocusNormalized: nil,
    )
}

nonisolated func makeCoordinatorArtifact(
    file: FileItem,
    backend: SimilarityBackendDescriptor,
) -> SimilarityArtifact {
    SimilarityArtifact(
        descriptor: SimilarityArtifactDescriptor(
            backend: backend,
            dimensions: 1,
            sourceFingerprint: SourceFingerprint(
                standardizedPath: file.url.standardizedFileURL.path,
                fileSize: file.size,
                modificationDate: file.dateModified,
            ),
        ),
        payload: Data([0]),
    )
}

@MainActor
func makeCoordinatorSnapshot(
    request: BurstAnalysisPipelineRequest,
    files: [FileItem]? = nil,
    groups: [BurstGroup] = [],
    reviewStates: [BurstReviewStateSnapshot] = [],
) -> BurstAnalysisCacheSnapshot {
    let files = files ?? request.orderedFiles
    return BurstAnalysisCacheSnapshot(
        schemaVersion: request.configuration.cacheSchemaVersion,
        algorithmVersion: request.configuration.groupingAlgorithmVersion,
        catalogPath: request.catalogIdentity.path,
        thumbnailMaxPixelSize: request.configuration.thumbnailMaxPixelSize,
        sharpnessSignature: request.sharpnessSignature,
        similaritySignature: request.similaritySignature,
        files: files.map {
            BurstAnalysisCacheFile(
                id: $0.id,
                path: $0.url.path,
                size: $0.size,
                modificationDate: $0.dateModified,
            )
        },
        embeddings: [:],
        sharpnessScores: [:],
        saliencyInfo: [:],
        groups: groups,
        boundaryEvidence: [],
        results: [],
        reviewStateSnapshots: reviewStates,
        similarityArtifactSetDigest: BurstAnalysisCache.artifactSetDigest(
            files: request.orderedFiles,
            artifacts: [:],
        ),
    )
}

/// Suspends the first `index` call until released.
actor CoordinatorIndexGate {
    private(set) var hasStarted = false
    private var released = false
    private var waiter: CheckedContinuation<Void, Never>?

    func enter() async {
        hasStarted = true
        guard !released else { return }
        await withCheckedContinuation { waiter = $0 }
    }

    func release() {
        released = true
        waiter?.resume()
        waiter = nil
    }
}

/// Indexes every source into a valid artifact after the gate opens; all
/// adjacent pairs are near-identical.
nonisolated struct CoordinatorGatedSimilarityService: RawCullSimilarityServicing {
    let backendDescriptor: SimilarityBackendDescriptor
    let gate: CoordinatorIndexGate

    func index(
        sources: [AIImageSource],
        maxPixelSize _: Int,
        progress _: (@Sendable (RawCullSimilarityIndexingProgress) async -> Void)?,
    ) async throws -> RawCullSimilarityIndexingOutput {
        await gate.enter()
        let artifacts = Dictionary(uniqueKeysWithValues: sources.map { source in
            (
                source.id,
                SimilarityArtifact(
                    descriptor: SimilarityArtifactDescriptor(
                        backend: backendDescriptor,
                        dimensions: 1,
                        sourceFingerprint: SourceFingerprint(source: source),
                    ),
                    payload: Data([0]),
                ),
            )
        })
        return RawCullSimilarityIndexingOutput(artifacts: artifacts, failures: [])
    }

    func distance(from _: SimilarityArtifact, to _: SimilarityArtifact) throws -> Float? {
        0.01
    }
}
