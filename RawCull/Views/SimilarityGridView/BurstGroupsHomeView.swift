import OSLog
import SwiftUI

struct BurstGroupsHomeView: View {
    @Bindable var viewModel: RawCullViewModel
    let similarityFeature: RawCullSimilarityFeature
    let semanticSearchFeature: RawCullSemanticSearchFeature
    @Binding var analyzeBurstsRequested: Bool
    let similarityThresholdChanged: () -> Void

    var body: some View {
        HStack(spacing: 0) {
            BurstGroupsSidebar(
                summary: summary,
                resultsAreAvailable: resultsAreAvailable,
                showResults: showResults,
            )
            .frame(width: 270)

            Divider()

            VStack(spacing: 0) {
                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        BurstGroupsHomeHeader(
                            maintenanceActionsAreDisabled: controlsAreBusy,
                            showScoringParameters: { viewModel.activeSheet = .scoringParams },
                            reindex: reindex,
                            indexSimilarity: indexSimilarity,
                        )

                        ViewThatFits(in: .horizontal) {
                            HStack(alignment: .top, spacing: 16) {
                                nextUpCard.frame(minWidth: 680)
                                reviewDataCard.frame(width: 290)
                            }
                            VStack(spacing: 16) {
                                nextUpCard
                                reviewDataCard
                            }
                        }

                        Text("Your queue")
                            .font(.headline)
                            .padding(.horizontal, 4)

                        queueCards

                        Text("Recent groups")
                            .font(.headline)
                            .padding(.horizontal, 4)

                        recentGroupsCard
                    }
                    .frame(maxWidth: 1320, alignment: .leading)
                    .padding(32)
                    .frame(maxWidth: .infinity, alignment: .topLeading)
                }
            }
        }
        .background(Color(nsColor: .windowBackgroundColor))
        .frame(minWidth: 760, minHeight: 560)
    }

    private var nextUpCard: some View {
        BurstNextUpCard(
            resultsAreAvailable: resultsAreAvailable,
            fileCount: viewModel.activeCatalogFiles.count,
            completedCount: completedCount,
            groupCount: burstGroupCount,
            controlsAreBusy: controlsAreBusy,
            catalogPreparation: catalogPreparationPresentation,
            analyzeBursts: analyzeBursts,
            openNeedsReview: { showResults(.needsReview) },
        )
    }

    private var reviewDataCard: some View {
        burstDataStatus
            .padding(24)
            .frame(maxWidth: .infinity, minHeight: 300, alignment: .topLeading)
            .background(.quaternary.opacity(0.35), in: .rect(cornerRadius: 14))
            .overlay {
                RoundedRectangle(cornerRadius: 14)
                    .stroke(.separator.opacity(0.65), lineWidth: 1)
            }
            .accessibilityElement(children: .contain)
    }

    private var queueCards: some View {
        HStack(spacing: 16) {
            BurstQueueActionCard(
                title: "Needs review",
                detail: "Open bursts that need your decision.",
                count: summary.needsReview,
                color: .red,
                systemImage: "exclamationmark.triangle",
                action: { showResults(.needsReview) },
            )
            BurstQueueActionCard(
                title: "Saved for later",
                detail: "Bursts you’ve deferred for later.",
                count: summary.deferred,
                color: .orange,
                systemImage: "bookmark",
                action: { showResults(.deferred) },
            )
            BurstQueueActionCard(
                title: "Completed",
                detail: "Bursts you’ve finished reviewing.",
                count: completedCount,
                color: .green,
                systemImage: "checkmark.circle",
                action: { showResults(.reviewed) },
            )
        }
        .disabled(!resultsAreAvailable)
    }

    private var burstDataStatus: some View {
        let files = viewModel.activeCatalogFiles
        let sharpness = viewModel.sharpnessModel
        let backend = similarityFeature.backend.kind
        return VStack(alignment: .leading, spacing: 12) {
            Text("Review data").font(.subheadline.weight(.semibold))
            BurstDataStatusRow(
                title: "Sharpness",
                detail: "Ranks the strongest frames.",
                count: files.count { sharpness.scores[$0.id] != nil },
                total: files.count,
                isRunning: sharpness.isScoring || sharpness.isCalibratingSharpnessScoring,
            )
            BurstDataStatusRow(
                title: "CLIP index",
                detail: "Groups visually similar photos.",
                count: similarityFeature.indexedFileCount(for: files, backend: .clip),
                total: files.count,
                isRunning: backend == .clip && similarityFeature.indexing.isIndexing,
                isUsed: backend == .clip,
            )
            BurstDataStatusRow(
                title: "Vision",
                detail: backend == .clip ? "CLIP is used for similarity." : "Groups visually similar photos.",
                count: similarityFeature.indexedFileCount(for: files, backend: .vision),
                total: files.count,
                isRunning: backend == .vision && similarityFeature.indexing.isIndexing,
                isUsed: backend == .vision,
            )
            BurstDataStatusRow(
                title: "Subject evidence",
                detail: "Optional aid for subject-aware ranking.",
                count: files.count { sharpness.saliencyInfo[$0.id] != nil },
                total: files.count,
                isRunning: sharpness.isScoring,
                isOptional: true,
            )
            BurstDataStatusRow(
                title: "Burst groups",
                detail: "Combines similarity and capture order.",
                count: resultsAreAvailable ? files.count : 0,
                total: files.count,
                isRunning: similarityFeature.isGrouping || viewModel.burstAnalysisProgress.isRunning,
            )
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private var recentGroupsCard: some View {
        if suggestedPicks.isEmpty {
            BurstRecentGroupsEmptyState(resultsAreAvailable: resultsAreAvailable)
        } else {
            BurstRecentGroupsCard(picks: suggestedPicks) { pick in
                viewModel.burstReviewQueueFilter = .all
                viewModel.similarityFeature.burstModeActive = true
                viewModel.selectedFileID = pick.file.id
            }
        }
    }

    private var summary: BurstReviewSummary {
        viewModel.burstReviewSummary
    }

    private var resultsAreAvailable: Bool {
        viewModel.hasCompletedBurstAnalysis
    }

    private var burstGroupCount: Int {
        summary.burstGroups
    }

    private var completedCount: Int {
        summary.completed
    }

    private var burstAnalysisIsBusy: Bool {
        analyzeBurstsRequested || viewModel.burstAnalysisProgress.isRunning
    }

    private var controlsAreBusy: Bool {
        viewModel.isPreparingBurstCatalog
            || viewModel.sharpnessModel.isCalibratingSharpnessScoring
            || viewModel.sharpnessModel.isScoring
            || similarityFeature.isBusy
            || burstAnalysisIsBusy
    }

    private var catalogPreparationPresentation: BurstCatalogPreparationPresentation {
        let indexing = similarityFeature.indexing
        let sharpnessModel = viewModel.sharpnessModel
        return BurstCatalogPreparationPresentation(
            isPreparingCatalog: viewModel.isPreparingBurstCatalog,
            fileCount: viewModel.activeCatalogFiles.count,
            semanticIndexedCount: semanticSearchFeature.indexedFileCount,
            semanticCatalogCount: semanticSearchFeature.catalogFileCount,
            isIndexing: indexing.isIndexing,
            indexingProgress: indexing.completed,
            indexingTotal: indexing.total,
            indexingEstimatedSeconds: indexing.estimatedSeconds,
            isSavingIndex: indexing.phase == .saving,
            isCalibratingSharpness: sharpnessModel.isCalibratingSharpnessScoring,
            isScoringSharpness: sharpnessModel.isScoring,
            sharpnessScoreCount: sharpnessModel.scores.count,
            sharpnessProgress: sharpnessModel.scoringProgress,
            sharpnessTotal: sharpnessModel.scoringTotal,
            sharpnessEstimatedSeconds: sharpnessModel.scoringEstimatedSeconds,
            isFindingBurstGroups: similarityFeature.isGrouping
                || (viewModel.isPreparingBurstCatalog
                    && viewModel.burstAnalysisProgress.isRunning),
            burstAnalysisStep: viewModel.burstAnalysisProgress.step,
            resultsAreAvailable: resultsAreAvailable,
            burstGroupCount: burstGroupCount,
        )
    }

    private var suggestedPicks: [BurstSuggestedPick] {
        let filesByID = Dictionary(
            uniqueKeysWithValues: viewModel.activeCatalogFiles.map { ($0.id, $0) },
        )
        return viewModel.burstAnalysisResults.values
            .sorted { $0.groupID < $1.groupID }
            .compactMap { result in
                guard let id = result.recommendedFileID, let file = filesByID[id] else { return nil }
                return BurstSuggestedPick(
                    groupID: result.groupID,
                    file: file,
                    subject: viewModel.sharpnessModel.saliencyInfo[id]?.subjectLabel,
                )
            }
            .prefix(3)
            .map { $0 }
    }

    private func showResults(_ filter: BurstReviewQueueFilter) {
        viewModel.burstReviewQueueFilter = filter
        viewModel.similarityFeature.burstModeActive = true
    }

    private func analyzeBursts() {
        Logger.process.debugMessageOnly(
            "BurstGroupsHomeView.analyzeBursts(): Run button pressed",
        )
        analyzeBurstsRequested = true
        Task {
            defer { analyzeBurstsRequested = false }
            let restored = await viewModel.restoreExistingFullCatalogBurstAnalysis()
            guard !Task.isCancelled else { return }
            if !restored {
                viewModel.burstFullReindexRequest = .analyzeBursts
            }
        }
    }

    private func reindex() {
        Task {
            _ = await viewModel.restoreExistingFullCatalogBurstAnalysis()
            guard !Task.isCancelled else { return }
            viewModel.burstFullReindexRequest = .catalogTools
        }
    }

    private func indexSimilarity() {
        Task { await similarityFeature.indexCurrentCatalog() }
    }
}
