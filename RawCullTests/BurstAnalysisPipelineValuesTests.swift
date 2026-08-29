import Foundation
@testable import RawCull
import RawCullCore
import Testing

@MainActor
@Suite(.tags(.smoke))
struct BurstAnalysisPipelineValuesTests {
    @Test
    func `pipeline request equals the legacy input snapshot`() {
        let viewModel = RawCullViewModel()
        let catalog = URL(fileURLWithPath: "/tmp/catalog-\(UUID().uuidString)")
        let first = makePipelineFile("A.ARW", captureSeconds: 1)
        let second = makePipelineFile("B.ARW", captureSeconds: 2)
        let orderedFiles = [first, second]
        let generation = 17

        let legacySharpnessSignature = viewModel.sharpnessModel.scoringSignature
        let legacySimilaritySignature = viewModel.currentBurstSimilaritySignature
        let legacyConfiguration = BurstAnalysisPipelineConfiguration(
            thumbnailMaxPixelSize: viewModel.sharpnessModel.effectiveThumbnailMaxPixelSize,
            grouping: legacySimilaritySignature.groupingConfig,
            cacheSchemaVersion: BurstAnalysisCache.schemaVersion,
            groupingAlgorithmVersion: BurstGroupingConfig.algorithmVersion,
        )
        let expected = BurstAnalysisPipelineRequest(
            catalogIdentity: catalog,
            orderedFiles: orderedFiles,
            sharpnessSignature: legacySharpnessSignature,
            similaritySignature: legacySimilaritySignature,
            generation: generation,
            configuration: legacyConfiguration,
        )

        let request = viewModel.makeBurstAnalysisPipelineRequest(
            catalog: catalog,
            files: orderedFiles,
            generation: generation,
        )

        #expect(request == expected)
        #expect(request.catalogIdentity == catalog)
        #expect(request.orderedFiles.map(\.id) == orderedFiles.map(\.id))
        #expect(request.configuration.grouping == request.similaritySignature.groupingConfig)
    }

    @Test
    func `pipeline request remains an immutable configuration snapshot`() {
        let viewModel = RawCullViewModel()
        let catalog = URL(fileURLWithPath: "/tmp/catalog-\(UUID().uuidString)")
        let files = [makePipelineFile("A.ARW", captureSeconds: 1)]
        let original = viewModel.makeBurstAnalysisPipelineRequest(
            catalog: catalog,
            files: files,
            generation: 3,
        )

        viewModel.similarityModel.burstSensitivity = 0.11
        let replacement = viewModel.makeBurstAnalysisPipelineRequest(
            catalog: catalog,
            files: files,
            generation: 4,
        )

        #expect(original.generation == 3)
        #expect(original.configuration.grouping.visualDistanceThreshold != 0.11)
        #expect(replacement.configuration.grouping.visualDistanceThreshold == 0.11)
        #expect(original != replacement)
    }

    @Test
    func `pipeline result equality covers cache diagnostics and restored state`() {
        let file = makePipelineFile("A.ARW", captureSeconds: 1)
        let group = BurstGroup(id: 4, fileIDs: [file.id])
        let result = BurstAnalysisPipelineResult(
            groups: [group],
            rankings: [],
            restoredReviewStates: [group.id: .deferred],
            cacheOutcome: .miss,
            diagnostics: [.reusedSharpnessScores, .indexedMissingSimilarityArtifacts],
        )
        let equalResult = BurstAnalysisPipelineResult(
            groups: [group],
            rankings: [],
            restoredReviewStates: [group.id: .deferred],
            cacheOutcome: .miss,
            diagnostics: [.reusedSharpnessScores, .indexedMissingSimilarityArtifacts],
        )
        let cacheHit = BurstAnalysisPipelineResult(
            groups: [group],
            rankings: [],
            restoredReviewStates: [group.id: .deferred],
            cacheOutcome: .hit,
            diagnostics: [.reusedSharpnessScores, .indexedMissingSimilarityArtifacts],
        )

        #expect(result == equalResult)
        #expect(result != cacheHit)
        requireSendable(BurstAnalysisPipelineRequest.self)
        requireSendable(BurstAnalysisPipelineResult.self)
    }
}

private nonisolated func makePipelineFile(
    _ name: String,
    captureSeconds: TimeInterval,
) -> FileItem {
    FileItem(
        url: URL(fileURLWithPath: "/tmp/\(name)"),
        name: name,
        size: 1,
        dateModified: Date(timeIntervalSince1970: captureSeconds),
        captureDate: Date(timeIntervalSince1970: captureSeconds),
        exifData: nil,
        afFocusNormalized: nil,
    )
}

private nonisolated func requireSendable(_: (some Sendable).Type) {}
