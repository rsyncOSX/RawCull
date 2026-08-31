enum BurstCatalogPreparationStage: Int, CaseIterable, Identifiable {
    case similarityIndex
    case sharpness
    case burstGroups

    var id: Self {
        self
    }
}

enum BurstCatalogPreparationActivity: Equatable {
    case indexing
    case savingIndex
    case calibratingSharpness
    case scoringSharpness
    case findingBurstGroups(BurstAnalysisStep)
}

enum BurstCatalogPreparationStageStatus: Equatable {
    case pending
    case running(
        activity: BurstCatalogPreparationActivity,
        completed: Int?,
        total: Int?,
    )
    case complete(completed: Int, total: Int)

    var completionFraction: Double {
        switch self {
        case .pending:
            0

        case let .running(_, completed?, total?) where total > 0:
            min(max(Double(completed) / Double(total), 0), 1)

        case .running:
            0

        case .complete:
            1
        }
    }
}

struct BurstCatalogPreparationStagePresentation: Identifiable, Equatable {
    let stage: BurstCatalogPreparationStage
    let status: BurstCatalogPreparationStageStatus

    var id: BurstCatalogPreparationStage {
        stage
    }
}

struct BurstCatalogPreparationPresentation: Equatable {
    let activeStage: BurstCatalogPreparationStage?
    let stages: [BurstCatalogPreparationStagePresentation]
    let estimatedSeconds: Int?

    var isRunning: Bool {
        activeStage != nil
    }

    var overallCompletionFraction: Double {
        guard !stages.isEmpty else { return 0 }
        let completed = stages.reduce(0) { result, stage in
            result + stage.status.completionFraction
        }
        return completed / Double(stages.count)
    }

    init(
        isPreparingCatalog: Bool,
        fileCount: Int,
        similarityIndexedCount: Int,
        similarityCatalogCount: Int,
        isIndexing: Bool,
        indexingProgress: Int,
        indexingTotal: Int,
        indexingEstimatedSeconds: Int,
        isSavingIndex: Bool,
        isCalibratingSharpness: Bool,
        isScoringSharpness: Bool,
        sharpnessScoreCount: Int,
        sharpnessProgress: Int,
        sharpnessTotal: Int,
        sharpnessEstimatedSeconds: Int,
        isFindingBurstGroups: Bool,
        burstAnalysisStep: BurstAnalysisStep,
        resultsAreAvailable: Bool,
        burstGroupCount: Int,
    ) {
        let similarityTotal = max(similarityCatalogCount, fileCount)
        let similarityIsComplete = similarityTotal > 0
            && similarityIndexedCount >= similarityTotal
        let sharpnessTarget = max(sharpnessTotal, fileCount)
        let sharpnessIsComplete = sharpnessTarget > 0
            && sharpnessScoreCount >= sharpnessTarget

        let activeStage: BurstCatalogPreparationStage? = if isIndexing {
            .similarityIndex
        } else if isCalibratingSharpness || isScoringSharpness {
            .sharpness
        } else if isFindingBurstGroups {
            .burstGroups
        } else if isPreparingCatalog, !similarityIsComplete {
            .similarityIndex
        } else if isPreparingCatalog, !sharpnessIsComplete {
            .sharpness
        } else if isPreparingCatalog {
            .burstGroups
        } else {
            nil
        }
        self.activeStage = activeStage

        let indexStatus: BurstCatalogPreparationStageStatus = if isIndexing {
            .running(
                activity: isSavingIndex ? .savingIndex : .indexing,
                completed: indexingProgress,
                total: indexingTotal > 0 ? indexingTotal : similarityTotal,
            )
        } else if similarityIsComplete || activeStage.map({ $0.rawValue > BurstCatalogPreparationStage.similarityIndex.rawValue }) == true {
            .complete(completed: similarityTotal, total: similarityTotal)
        } else {
            .pending
        }

        let sharpnessStatus: BurstCatalogPreparationStageStatus = if isCalibratingSharpness {
            .running(
                activity: .calibratingSharpness,
                completed: nil,
                total: nil,
            )
        } else if isScoringSharpness {
            .running(
                activity: .scoringSharpness,
                completed: sharpnessProgress,
                total: sharpnessTotal > 0 ? sharpnessTotal : fileCount,
            )
        } else if sharpnessIsComplete || activeStage == .burstGroups {
            .complete(
                completed: sharpnessTarget,
                total: sharpnessTarget,
            )
        } else {
            .pending
        }

        let burstStatus: BurstCatalogPreparationStageStatus = if activeStage == .burstGroups {
            .running(
                activity: .findingBurstGroups(burstAnalysisStep),
                completed: nil,
                total: nil,
            )
        } else if resultsAreAvailable {
            .complete(
                completed: burstGroupCount,
                total: burstGroupCount,
            )
        } else {
            .pending
        }

        stages = [
            BurstCatalogPreparationStagePresentation(
                stage: .similarityIndex,
                status: indexStatus,
            ),
            BurstCatalogPreparationStagePresentation(
                stage: .sharpness,
                status: sharpnessStatus,
            ),
            BurstCatalogPreparationStagePresentation(
                stage: .burstGroups,
                status: burstStatus,
            )
        ]

        estimatedSeconds = switch activeStage {
        case .similarityIndex where indexingEstimatedSeconds > 0:
            indexingEstimatedSeconds

        case .sharpness where sharpnessEstimatedSeconds > 0:
            sharpnessEstimatedSeconds

        default:
            nil
        }
    }
}
