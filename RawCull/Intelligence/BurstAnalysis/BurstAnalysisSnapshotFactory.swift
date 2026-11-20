//
//  BurstAnalysisSnapshotFactory.swift
//  RawCull
//
//  Pure builders for burst-analysis requests, contexts and cache snapshots.
//  They used to live inside the workspace view model and read its models directly;
//  here every input is a parameter, so they can be tested and reused without
//  constructing the view model.
//

import Foundation
import PhotoAIContracts
import RawCullCore

enum BurstAnalysisSnapshotFactory {
    static func similaritySignature(
        burstSensitivity: Float,
        backendDescriptor: SimilarityBackendDescriptor,
        artifactBackendDescriptors: [SimilarityBackendDescriptor],
    ) -> BurstSimilaritySignature {
        BurstSimilaritySignature(
            groupingConfig: BurstGroupingConfig(visualDistanceThreshold: burstSensitivity),
            backendDescriptor: backendDescriptor,
            artifactBackendDescriptors: artifactBackendDescriptors,
            artifactSchemaVersion: SimilarityScoringModel.artifactSchemaVersion,
            embeddingThumbnailMaxPixelSize: SimilarityScoringModel.embeddingThumbnailMaxPixelSize,
            embeddingPipelineVersion: SimilarityScoringModel.embeddingPipelineVersion,
        )
    }

    static func pipelineRequest(
        catalog: URL,
        files: [FileItem],
        generation: Int,
        sharpnessSignature: BurstSharpnessSignature,
        similaritySignature: BurstSimilaritySignature,
        thumbnailMaxPixelSize: Int,
    ) -> BurstAnalysisPipelineRequest {
        BurstAnalysisPipelineRequest(
            catalogIdentity: catalog,
            orderedFiles: files,
            sharpnessSignature: sharpnessSignature,
            similaritySignature: similaritySignature,
            generation: generation,
            configuration: BurstAnalysisPipelineConfiguration(
                thumbnailMaxPixelSize: thumbnailMaxPixelSize,
                grouping: similaritySignature.groupingConfig,
                cacheSchemaVersion: BurstAnalysisCache.schemaVersion,
                groupingAlgorithmVersion: BurstGroupingConfig.algorithmVersion,
            ),
        )
    }

    static func completedContext(
        catalog: URL,
        files: [FileItem],
        generation: Int,
        similaritySignature: BurstSimilaritySignature,
    ) -> CompletedBurstAnalysisContext {
        CompletedBurstAnalysisContext(
            catalog: catalog,
            orderedFileIDs: files.map(\.id),
            orderedFilePaths: files.map(\.url.path),
            similaritySignature: similaritySignature,
            generation: generation,
        )
    }

    /// Maps a completed analysis back onto the current catalog files, by ID
    /// first and path second. Returns nil when any analysed file is gone.
    static func files(for context: CompletedBurstAnalysisContext, in files: [FileItem]) -> [FileItem]? {
        let currentByID = Dictionary(uniqueKeysWithValues: files.map { ($0.id, $0) })
        let currentByPath = Dictionary(uniqueKeysWithValues: files.map { ($0.url.path, $0) })
        var resolved: [FileItem] = []
        resolved.reserveCapacity(context.orderedFileIDs.count)

        for (id, path) in zip(context.orderedFileIDs, context.orderedFilePaths) {
            guard let file = currentByID[id] ?? currentByPath[path] else { return nil }
            resolved.append(file)
        }
        return resolved
    }

    static func scoped<Value>(_ dictionary: [UUID: Value], to files: [FileItem]) -> [UUID: Value] {
        let validIDs = Set(files.map(\.id))
        return dictionary.filter { validIDs.contains($0.key) }
    }

    /// Everything a cache snapshot is built from, captured at save time.
    struct CacheInputs {
        let catalog: URL
        let files: [FileItem]
        let configuration: BurstAnalysisPipelineConfiguration?
        let fallbackThumbnailMaxPixelSize: Int
        let sharpnessSignature: BurstSharpnessSignature
        let similaritySignature: BurstSimilaritySignature
        let embeddings: [UUID: SimilarityArtifact]
        let sharpnessScores: [UUID: Float]
        let saliencyInfo: [UUID: SaliencyInfo]
        let groups: [BurstGroup]
        let boundaryEvidence: [BurstBoundaryEvidence]
        let results: [BurstAnalysisResult]
        let reviewStateSnapshots: [BurstReviewStateSnapshot]
    }

    static func cacheSnapshot(_ inputs: CacheInputs) -> BurstAnalysisCacheSnapshot {
        let files = inputs.files
        return BurstAnalysisCacheSnapshot(
            schemaVersion: inputs.configuration?.cacheSchemaVersion ?? BurstAnalysisCache.schemaVersion,
            algorithmVersion: inputs.configuration?.groupingAlgorithmVersion ?? BurstGroupingConfig.algorithmVersion,
            catalogPath: inputs.catalog.path,
            thumbnailMaxPixelSize: inputs.configuration?.thumbnailMaxPixelSize
                ?? inputs.fallbackThumbnailMaxPixelSize,
            sharpnessSignature: inputs.sharpnessSignature,
            similaritySignature: inputs.similaritySignature,
            files: files.map {
                BurstAnalysisCacheFile(
                    id: $0.id,
                    path: $0.url.path,
                    size: $0.size,
                    modificationDate: $0.dateModified,
                )
            },
            embeddings: scoped(inputs.embeddings, to: files),
            sharpnessScores: scoped(inputs.sharpnessScores, to: files),
            saliencyInfo: scoped(inputs.saliencyInfo, to: files),
            groups: inputs.groups,
            boundaryEvidence: inputs.boundaryEvidence,
            results: inputs.results.sorted { $0.groupID < $1.groupID },
            reviewStateSnapshots: inputs.reviewStateSnapshots,
            similarityArtifactSetDigest: BurstAnalysisCache.artifactSetDigest(
                files: files,
                artifacts: inputs.embeddings,
            ),
        )
    }
}
