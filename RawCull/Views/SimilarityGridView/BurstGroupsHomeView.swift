import OSLog
import SwiftUI

struct BurstGroupsHomeView: View {
    @Bindable var viewModel: RawCullViewModel
    let similarityFeature: RawCullSimilarityFeature
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

                        nextUpCard

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
            similarityIndexedCount: similarityFeature.indexedFileCount,
            similarityCatalogCount: viewModel.activeCatalogFiles.count,
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

private struct BurstGroupsSidebar: View {
    let summary: BurstReviewSummary
    let resultsAreAvailable: Bool
    let showResults: (BurstReviewQueueFilter) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            HStack(spacing: 12) {
                Text("C")
                    .font(.headline)
                    .foregroundStyle(.white)
                    .frame(width: 40, height: 40)
                    .background(Color.accentColor, in: .rect(cornerRadius: 10))
                VStack(alignment: .leading, spacing: 3) {
                    Text("Culling").font(.headline)
                    Text("Burst Groups").foregroundStyle(.secondary)
                }
            }

            sidebarSection("WORKFLOW") {
                BurstSidebarRow(title: "Overview", systemImage: "house", isSelected: true) {}
                BurstSidebarRow(title: "All bursts", count: summary.burstGroups, systemImage: "square.grid.2x2") {
                    showResults(.all)
                }
                .disabled(!resultsAreAvailable)
                BurstSidebarRow(title: "Needs review", count: summary.needsReview, countColor: .orange, systemImage: "exclamationmark.triangle") {
                    showResults(.needsReview)
                }
                BurstSidebarRow(title: "Completed", count: summary.completed, countColor: .green, systemImage: "checkmark.circle") {
                    showResults(.reviewed)
                }
                BurstSidebarRow(title: "Single images", count: summary.singleImages, countColor: .blue, systemImage: "photo") {
                    showResults(.singleImages)
                }
            }
            .disabled(!resultsAreAvailable)

            Spacer()
        }
        .padding(24)
        .background(Color(nsColor: .underPageBackgroundColor))
    }

    private func sidebarSection(
        _ title: String,
        @ViewBuilder content: () -> some View,
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.caption.monospaced())
                .foregroundStyle(.secondary)
                .padding(.horizontal, 8)
            content()
        }
    }
}

private struct BurstGroupsHomeHeader: View {
    let maintenanceActionsAreDisabled: Bool
    let showScoringParameters: () -> Void
    let reindex: () -> Void
    let indexSimilarity: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 24) {
            VStack(alignment: .leading, spacing: 8) {
                Text("Burst Groups")
                    .font(.system(size: 34, weight: .bold))
                Text("Find the strongest frame from every sequence.")
                    .font(.title3)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer()

            Menu {
                Button(action: showScoringParameters) {
                    Label("Scoring Parameters", systemImage: "slider.horizontal.3")
                }

                Divider()

                Button(action: reindex) {
                    Label("Re-index Catalog", systemImage: "arrow.clockwise")
                }
                .disabled(maintenanceActionsAreDisabled)

                Button(action: indexSimilarity) {
                    Label("Index Similarity", systemImage: "scope")
                }
                .disabled(maintenanceActionsAreDisabled)
            } label: {
                Label("More", systemImage: "ellipsis")
            }
            .menuStyle(.button)
            .controlSize(.large)
            .help("Catalog maintenance actions")
        }
    }
}

private struct BurstNextUpCard: View {
    let resultsAreAvailable: Bool
    let fileCount: Int
    let completedCount: Int
    let groupCount: Int
    let controlsAreBusy: Bool
    let catalogPreparation: BurstCatalogPreparationPresentation
    let analyzeBursts: () -> Void
    let openNeedsReview: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Next up")
                .font(.headline)
                .foregroundStyle(.secondary)

            HStack(spacing: 28) {
                Image(systemName: resultsAreAvailable ? "photo.stack.fill" : "photo.on.rectangle.angled")
                    .font(.system(size: 48, weight: .light))
                    .foregroundStyle(.secondary)
                    .frame(width: 112)
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 10) {
                    Text(title)
                        .font(.title2.weight(.bold))
                    Text(detail)
                        .font(.title3)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)

                    HStack(spacing: 10) {
                        Label("\(fileCount) photos", systemImage: "clock")
                        Text("·")

                        ZStack(alignment: .leading) {
                            Text(resultsAreAvailable ? "Ready to review" : "About a minute")
                                .opacity(catalogPreparation.isRunning ? 0 : 1)
                                .accessibilityHidden(catalogPreparation.isRunning)

                            HStack(spacing: 6) {
                                ProgressView(
                                    value: catalogPreparation.overallCompletionFraction,
                                )
                                .frame(width: 48)

                                Text(catalogPreparationStatus)
                                    .lineLimit(1)
                            }
                            .opacity(catalogPreparation.isRunning ? 1 : 0)
                            .accessibilityHidden(!catalogPreparation.isRunning)
                        }
                        .frame(width: 190, alignment: .leading)
                    }
                    .font(.callout)
                    .foregroundStyle(.secondary)

                    HStack(spacing: 14) {
                        Button(action: resultsAreAvailable ? openNeedsReview : analyzeBursts) {
                            Label(
                                resultsAreAvailable ? "Open Review Queue" : "Find Burst Groups",
                                systemImage: resultsAreAvailable ? "arrow.right" : "waveform.path.ecg",
                            )
                            .frame(minWidth: 250)
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.large)
                        .disabled(controlsAreBusy || fileCount == 0)
                    }
                }

                Spacer(minLength: 24)

                BurstReviewProgressRing(
                    completedCount: completedCount,
                    totalCount: resultsAreAvailable ? groupCount : fileCount,
                )
                .padding(.trailing, 28)
            }
        }
        .padding(24)
        .background(.quaternary.opacity(0.35), in: .rect(cornerRadius: 14))
        .overlay {
            RoundedRectangle(cornerRadius: 14)
                .stroke(.separator.opacity(0.65), lineWidth: 1)
        }
        .accessibilityElement(children: .contain)
    }

    private var title: String {
        resultsAreAvailable ? "Continue reviewing your bursts" : "Start by finding burst groups"
    }

    private var detail: String {
        if resultsAreAvailable {
            return "Compare each sequence side by side and keep the strongest frames."
        }
        return "We’ll cluster visually similar photos so you can compare them side by side."
    }

    private var catalogPreparationStatus: LocalizedStringResource {
        switch catalogPreparation.activeStage {
        case .similarityIndex:
            "Indexing photos…"

        case .sharpness:
            "Scoring sharpness…"

        case .burstGroups:
            "Finding burst groups…"

        case nil:
            "Preparing…"
        }
    }
}

private struct BurstReviewProgressRing: View {
    let completedCount: Int
    let totalCount: Int

    var body: some View {
        ZStack {
            Circle()
                .stroke(.primary.opacity(0.14), lineWidth: 15)
            Circle()
                .trim(from: 0, to: progress)
                .stroke(Color.accentColor, style: StrokeStyle(lineWidth: 15, lineCap: .round))
                .rotationEffect(.degrees(-90))

            VStack(spacing: 5) {
                Image(systemName: "person.2.fill")
                    .foregroundStyle(.secondary)
                Text("\(completedCount) of \(totalCount)")
                    .font(.title3.weight(.bold).monospacedDigit())
                Text("completed")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(width: 170, height: 170)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(completedCount) of \(totalCount) burst groups completed")
    }

    private var progress: Double {
        guard totalCount > 0 else { return 0 }
        return min(Double(completedCount) / Double(totalCount), 1)
    }
}

private struct BurstQueueActionCard: View {
    let title: String
    let detail: String
    let count: Int
    let color: Color
    let systemImage: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 16) {
                Image(systemName: systemImage)
                    .font(.title2)
                    .foregroundStyle(color)
                    .frame(width: 52, height: 52)
                    .background(color.opacity(0.13), in: .rect(cornerRadius: 10))

                VStack(alignment: .leading, spacing: 4) {
                    Text(title).font(.headline)
                    Text(detail)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }

                Spacer(minLength: 8)

                Text(count, format: .number)
                    .font(.system(size: 30, weight: .medium, design: .monospaced))
                    .foregroundStyle(color)
                Image(systemName: "chevron.right")
                    .foregroundStyle(.secondary)
            }
            .padding(18)
            .frame(maxWidth: .infinity, minHeight: 104, alignment: .leading)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .background(.quaternary.opacity(0.35), in: .rect(cornerRadius: 12))
        .overlay {
            RoundedRectangle(cornerRadius: 12)
                .stroke(.separator.opacity(0.65), lineWidth: 1)
        }
        .accessibilityElement(children: .combine)
    }
}

private struct BurstRecentGroupsEmptyState: View {
    let resultsAreAvailable: Bool

    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: "photo.stack")
                .font(.system(size: 42, weight: .light))
                .foregroundStyle(.secondary)
            Text(resultsAreAvailable ? "No recent groups" : "No burst groups yet")
                .font(.title3.weight(.medium))
            Text(resultsAreAvailable
                ? "Open a review queue to continue culling."
                : "Run Find Burst Groups to create your first review queue.")
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, minHeight: 165)
        .background(.quaternary.opacity(0.35), in: .rect(cornerRadius: 12))
        .overlay {
            RoundedRectangle(cornerRadius: 12)
                .stroke(.separator.opacity(0.65), lineWidth: 1)
        }
        .accessibilityElement(children: .combine)
    }
}

private struct BurstRecentGroupsCard: View {
    let picks: [BurstSuggestedPick]
    let action: (BurstSuggestedPick) -> Void

    var body: some View {
        HStack(spacing: 14) {
            ForEach(picks) { pick in
                Button { action(pick) } label: {
                    VStack(alignment: .leading, spacing: 8) {
                        ThumbnailImageView(
                            file: pick.file,
                            targetSize: 220,
                            style: .grid,
                            showsShimmer: true,
                        )
                        .frame(maxWidth: .infinity, minHeight: 100, maxHeight: 130)
                        .clipped()

                        Text("Burst \(pick.groupID + 1, format: .number)")
                            .font(.headline.monospaced())
                        Text(pick.subject ?? pick.file.name)
                            .font(.callout)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(10)
                    .contentShape(.rect)
                }
                .buttonStyle(.plain)
                .background(.quaternary.opacity(0.35), in: .rect(cornerRadius: 12))
                .overlay {
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(.separator.opacity(0.65), lineWidth: 1)
                }
            }
        }
    }
}

private struct BurstSidebarRow: View {
    let title: String
    var count: Int?
    var countColor: Color = .accentColor
    let systemImage: String
    var isSelected = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: systemImage).frame(width: 20)
                Text(title)
                Spacer()
                if let count {
                    Text(count, format: .number)
                        .monospacedDigit()
                        .foregroundStyle(countColor)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .background(isSelected ? Color.accentColor.opacity(0.2) : .clear, in: .rect(cornerRadius: 9))
        .overlay {
            if isSelected {
                RoundedRectangle(cornerRadius: 9)
                    .stroke(Color.accentColor.opacity(0.7), lineWidth: 1)
            }
        }
    }
}

private struct BurstSuggestedPick: Identifiable {
    let groupID: Int
    let file: FileItem
    let subject: String?
    var id: FileItem.ID {
        file.id
    }
}
