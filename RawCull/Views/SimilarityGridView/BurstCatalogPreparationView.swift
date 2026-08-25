import SwiftUI

enum BurstCatalogPreparationStage: Int, CaseIterable, Identifiable {
    case semanticIndex
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

    init(
        isPreparingCatalog: Bool,
        fileCount: Int,
        semanticIndexedCount: Int,
        semanticCatalogCount: Int,
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
        let semanticTotal = max(semanticCatalogCount, fileCount)
        let semanticIsComplete = semanticTotal > 0
            && semanticIndexedCount >= semanticTotal
        let sharpnessTarget = max(sharpnessTotal, fileCount)
        let sharpnessIsComplete = sharpnessTarget > 0
            && sharpnessScoreCount >= sharpnessTarget

        let activeStage: BurstCatalogPreparationStage? = if isIndexing {
            .semanticIndex
        } else if isCalibratingSharpness || isScoringSharpness {
            .sharpness
        } else if isFindingBurstGroups {
            .burstGroups
        } else if isPreparingCatalog, !semanticIsComplete {
            .semanticIndex
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
                total: indexingTotal > 0 ? indexingTotal : semanticTotal,
            )
        } else if semanticIsComplete || activeStage.map({ $0.rawValue > BurstCatalogPreparationStage.semanticIndex.rawValue }) == true {
            .complete(completed: semanticTotal, total: semanticTotal)
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
                stage: .semanticIndex,
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
        case .semanticIndex where indexingEstimatedSeconds > 0:
            indexingEstimatedSeconds

        case .sharpness where sharpnessEstimatedSeconds > 0:
            sharpnessEstimatedSeconds

        default:
            nil
        }
    }
}

struct BurstCatalogPreparationView: View {
    let presentation: BurstCatalogPreparationPresentation
    let cancel: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            header

            ViewThatFits(in: .horizontal) {
                HStack(alignment: .top, spacing: 0) {
                    stageViews(axis: .horizontal)
                }

                VStack(alignment: .leading, spacing: 0) {
                    stageViews(axis: .vertical)
                }
            }

            Label(
                "You can keep browsing. Review queues become available when catalog setup finishes.",
                systemImage: "info.circle",
            )
            .font(.callout)
            .foregroundStyle(.secondary)
        }
        .padding(24)
        .background(.quaternary.opacity(0.35), in: .rect(cornerRadius: 14))
        .overlay {
            RoundedRectangle(cornerRadius: 14)
                .stroke(.separator.opacity(0.65), lineWidth: 1)
        }
        .accessibilityElement(children: .contain)
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 20) {
            VStack(alignment: .leading, spacing: 5) {
                Text("CATALOG SETUP · STEP \(activeStepNumber) OF 3")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Color.accentColor)
                Text("Preparing your catalog")
                    .font(.title2.weight(.bold))
                Text(activeStageDetail)
                    .font(.title3)
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 16)

            Button("Cancel", role: .cancel, action: cancel)
                .buttonStyle(.bordered)
                .keyboardShortcut(.cancelAction)
                .accessibilityHint("Stops the active catalog setup operation.")
        }
    }

    private func stageViews(axis: Axis) -> some View {
        ForEach(presentation.stages) { stage in
            BurstCatalogPreparationStageView(presentation: stage)
                .frame(
                    maxWidth: axis == .horizontal ? .infinity : nil,
                    alignment: .leading,
                )

            if stage.id != BurstCatalogPreparationStage.allCases.last {
                if axis == .horizontal {
                    Divider()
                        .padding(.horizontal, 18)
                } else {
                    Divider()
                        .padding(.vertical, 14)
                }
            }
        }
    }

    private var activeStepNumber: Int {
        (presentation.activeStage?.rawValue ?? 0) + 1
    }

    private var activeStageDetail: LocalizedStringResource {
        guard let activeStage = presentation.activeStage,
              let stage = presentation.stages.first(where: { $0.stage == activeStage })
        else {
            return "Preparing catalog setup…"
        }

        return stage.status.activityDetail
    }
}

private struct BurstCatalogPreparationStageView: View {
    let presentation: BurstCatalogPreparationStagePresentation

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            statusIcon

            VStack(alignment: .leading, spacing: 5) {
                Text(presentation.status.statusLabel)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(statusColor)
                Text(presentation.stage.title)
                    .font(.headline)
                Text(presentation.status.detail(for: presentation.stage))
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                if case let .running(_, completed?, total?) = presentation.status,
                   total > 0 {
                    ProgressView(
                        value: Double(completed),
                        total: Double(total),
                    )
                    .padding(.top, 3)
                }
            }
        }
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private var statusIcon: some View {
        switch presentation.status {
        case .pending:
            Image(systemName: "circle")
                .foregroundStyle(.secondary)

        case .running:
            ProgressView()
                .controlSize(.small)
                .frame(width: 16, height: 16)

        case .complete:
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(.green)
        }
    }

    private var statusColor: Color {
        switch presentation.status {
        case .pending: .secondary
        case .running: .accentColor
        case .complete: .green
        }
    }
}

private extension BurstCatalogPreparationStage {
    var title: LocalizedStringResource {
        switch self {
        case .semanticIndex: "Indexing semantic search"
        case .sharpness: "Calibrating sharpness"
        case .burstGroups: "Finding burst groups"
        }
    }
}

private extension BurstCatalogPreparationStageStatus {
    var statusLabel: LocalizedStringResource {
        switch self {
        case .pending: "UP NEXT"
        case .running: "IN PROGRESS"
        case .complete: "COMPLETED"
        }
    }

    var activityDetail: LocalizedStringResource {
        switch self {
        case .pending:
            "Waiting for the previous stage…"

        case let .running(activity, _, _):
            activity.detail

        case .complete:
            "Stage completed."
        }
    }

    func detail(
        for stage: BurstCatalogPreparationStage,
    ) -> LocalizedStringResource {
        switch self {
        case .pending:
            switch stage {
            case .semanticIndex: "Waiting to index catalog photos"
            case .sharpness: "Waiting to calculate scoring parameters"
            case .burstGroups: "Waiting to analyze photo sequences"
            }

        case let .running(activity, completed, total):
            if let completed, let total, total > 0 {
                switch activity {
                case .indexing:
                    "\(completed) of \(total) photos indexed"

                case .savingIndex:
                    "\(completed) of \(total) artifacts saved"

                case .scoringSharpness:
                    "\(completed) of \(total) photos scored"

                default:
                    activity.detail
                }
            } else {
                activity.detail
            }

        case let .complete(completed, total):
            switch stage {
            case .semanticIndex:
                "\(completed) of \(total) photos indexed"

            case .sharpness:
                "Sharpness scoring is ready for \(total) photos"

            case .burstGroups:
                "\(completed) burst groups ready to review"
            }
        }
    }
}

private extension BurstCatalogPreparationActivity {
    var detail: LocalizedStringResource {
        switch self {
        case .indexing:
            "Creating semantic search artifacts…"

        case .savingIndex:
            "Saving semantic search artifacts…"

        case .calibratingSharpness:
            "Calculating sharpness scoring parameters…"

        case .scoringSharpness:
            "Scoring catalog photos for sharpness…"

        case let .findingBurstGroups(step):
            switch step {
            case .idle, .loadingCache:
                "Checking for an existing burst analysis…"

            case .scoringSharpness:
                "Preparing sharpness results…"

            case .indexingSimilarity:
                "Preparing semantic search results…"

            case .grouping:
                "Grouping visually related photos…"

            case .ranking:
                "Ranking the strongest frames…"

            case .savingCache:
                "Saving burst groups…"
            }
        }
    }
}
