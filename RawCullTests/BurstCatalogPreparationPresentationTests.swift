@testable import RawCull
import Testing

@MainActor
@Suite("Burst catalog preparation presentation")
struct BurstCatalogPreparationPresentationTests {
    @Test
    func `semantic indexing is the first visible stage`() throws {
        let presentation = makePresentation(
            semanticIndexedCount: 200,
            isIndexing: true,
            indexingProgress: 200,
            indexingTotal: 905,
            indexingEstimatedSeconds: 80,
        )

        #expect(presentation.activeStage == .semanticIndex)
        #expect(presentation.estimatedSeconds == 80)
        #expect(
            presentation.overallCompletionFraction
                == (Double(200) / Double(905)) / 3,
        )
        #expect(try status(for: .semanticIndex, in: presentation) == .running(
            activity: .indexing,
            completed: 200,
            total: 905,
        ))
        #expect(try status(for: .sharpness, in: presentation) == .pending)
        #expect(try status(for: .burstGroups, in: presentation) == .pending)
    }

    @Test
    func `sharpness calibration is visible even before scoring begins`() throws {
        let presentation = makePresentation(
            semanticIndexedCount: 905,
            isCalibratingSharpness: true,
        )

        #expect(presentation.activeStage == .sharpness)
        #expect(presentation.overallCompletionFraction == Double(1) / 3)
        #expect(try status(for: .semanticIndex, in: presentation) == .complete(
            completed: 905,
            total: 905,
        ))
        #expect(try status(for: .sharpness, in: presentation) == .running(
            activity: .calibratingSharpness,
            completed: nil,
            total: nil,
        ))
        #expect(try status(for: .burstGroups, in: presentation) == .pending)
    }

    @Test
    func `burst grouping follows completed indexing and sharpness stages`() throws {
        let presentation = makePresentation(
            isPreparingCatalog: true,
            semanticIndexedCount: 905,
            sharpnessScoreCount: 905,
            isFindingBurstGroups: true,
            burstAnalysisStep: .grouping,
        )

        #expect(presentation.activeStage == .burstGroups)
        #expect(presentation.overallCompletionFraction == Double(2) / 3)
        #expect(try status(for: .semanticIndex, in: presentation) == .complete(
            completed: 905,
            total: 905,
        ))
        #expect(try status(for: .sharpness, in: presentation) == .complete(
            completed: 905,
            total: 905,
        ))
        #expect(try status(for: .burstGroups, in: presentation) == .running(
            activity: .findingBurstGroups(.grouping),
            completed: nil,
            total: nil,
        ))
    }

    private func status(
        for stage: BurstCatalogPreparationStage,
        in presentation: BurstCatalogPreparationPresentation,
    ) throws -> BurstCatalogPreparationStageStatus {
        try #require(
            presentation.stages.first(where: { $0.stage == stage }),
        ).status
    }

    private func makePresentation(
        isPreparingCatalog: Bool = false,
        semanticIndexedCount: Int = 0,
        isIndexing: Bool = false,
        indexingProgress: Int = 0,
        indexingTotal: Int = 0,
        indexingEstimatedSeconds: Int = 0,
        isSavingIndex: Bool = false,
        isCalibratingSharpness: Bool = false,
        isScoringSharpness: Bool = false,
        sharpnessScoreCount: Int = 0,
        sharpnessProgress: Int = 0,
        sharpnessTotal: Int = 0,
        sharpnessEstimatedSeconds: Int = 0,
        isFindingBurstGroups: Bool = false,
        burstAnalysisStep: BurstAnalysisStep = .idle,
        resultsAreAvailable: Bool = false,
        burstGroupCount: Int = 0,
    ) -> BurstCatalogPreparationPresentation {
        BurstCatalogPreparationPresentation(
            isPreparingCatalog: isPreparingCatalog,
            fileCount: 905,
            semanticIndexedCount: semanticIndexedCount,
            semanticCatalogCount: 905,
            isIndexing: isIndexing,
            indexingProgress: indexingProgress,
            indexingTotal: indexingTotal,
            indexingEstimatedSeconds: indexingEstimatedSeconds,
            isSavingIndex: isSavingIndex,
            isCalibratingSharpness: isCalibratingSharpness,
            isScoringSharpness: isScoringSharpness,
            sharpnessScoreCount: sharpnessScoreCount,
            sharpnessProgress: sharpnessProgress,
            sharpnessTotal: sharpnessTotal,
            sharpnessEstimatedSeconds: sharpnessEstimatedSeconds,
            isFindingBurstGroups: isFindingBurstGroups,
            burstAnalysisStep: burstAnalysisStep,
            resultsAreAvailable: resultsAreAvailable,
            burstGroupCount: burstGroupCount,
        )
    }
}
