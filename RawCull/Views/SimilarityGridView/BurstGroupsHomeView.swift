import OSLog
import SwiftUI

struct BurstGroupsHomeView: View {
    @Bindable var viewModel: RawCullViewModel
    @Binding var analyzeBurstsRequested: Bool
    let similarityThresholdChanged: () -> Void

    var body: some View {
        HStack(spacing: 0) {
            BurstGroupsSidebar(
                counts: counts,
                groupCount: viewModel.similarityModel.burstGroups.filter { $0.fileIDs.count > 1 }.count,
                resultsAreAvailable: resultsAreAvailable,
                showResults: showResults,
            )
            .frame(width: 270)

            Divider()

            VStack(spacing: 0) {
                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        BurstGroupsHomeHeader(
                            similarityIndexIsRunning: viewModel.similarityModel.isIndexing,
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

                BurstIndexStatusBar(
                    isIndexing: viewModel.similarityModel.isIndexing,
                    hasResults: resultsAreAvailable,
                    indexedCount: viewModel.similarityModel.indexingProgress,
                    totalCount: max(viewModel.similarityModel.indexingTotal, viewModel.activeCatalogFiles.count),
                )
            }
        }
        .background(Color(nsColor: .windowBackgroundColor))
        .frame(minWidth: 760, minHeight: 560)
    }

    private var nextUpCard: some View {
        BurstNextUpCard(
            resultsAreAvailable: resultsAreAvailable,
            isRunning: burstScanIsRunning,
            runningText: burstScanStatusText,
            fileCount: viewModel.activeCatalogFiles.count,
            reviewedCount: completedCount,
            groupCount: burstGroupCount,
            controlsAreBusy: controlsAreBusy,
            analyzeBursts: analyzeBursts,
            openNeedsReview: { showResults(.needsReview) },
        ) {
            burstHomeProgressCounter
        }
    }

    private var queueCards: some View {
        HStack(spacing: 16) {
            BurstQueueActionCard(
                title: "Needs review",
                detail: "Open bursts that need your decision.",
                count: counts.needsReview,
                color: .red,
                systemImage: "exclamationmark.triangle",
                action: { showResults(.needsReview) },
            )
            BurstQueueActionCard(
                title: "Saved for later",
                detail: "Bursts you’ve deferred for later.",
                count: counts.deferred,
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
                viewModel.similarityModel.burstModeActive = true
                viewModel.selectedFileID = pick.file.id
            }
        }
    }

    @ViewBuilder
    private var burstHomeProgressCounter: some View {
        if viewModel.sharpnessModel.isScoring {
            BurstHomeProgressCount(
                progress: viewModel.sharpnessModel.scoringProgress,
                estimatedSeconds: viewModel.sharpnessModel.scoringEstimatedSeconds,
                max: viewModel.sharpnessModel.scoringTotal,
            )
        }

        if viewModel.similarityModel.isIndexing {
            BurstHomeProgressCount(
                progress: viewModel.similarityModel.indexingProgress,
                estimatedSeconds: viewModel.similarityModel.indexingEstimatedSeconds,
                max: viewModel.similarityModel.indexingTotal,
            )
        }
    }

    private var reviewQueueCard: some View {
        BurstDashboardCard(
            title: "Review queue",
            trailing: "\(viewModel.activeCatalogFiles.count) files  ·  \(burstGroupCount) groups",
        ) {
            HStack(spacing: 12) {
                BurstQueueMetric(
                    title: "Needs Review",
                    count: counts.needsReview,
                    detail: "Open burst list to cull",
                    color: .red,
                    isEmphasized: true,
                )
                BurstQueueMetric(
                    title: "Deferred",
                    count: counts.deferred,
                    detail: "Mark for later",
                    color: .orange,
                )
                BurstQueueMetric(
                    title: "Marked Reviewed",
                    count: counts.markedReviewed,
                    detail: "Done this session",
                    color: .green,
                )
            }

            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Catalog coverage")
                    Spacer()
                    Text("\(coveredFileCount) / \(viewModel.activeCatalogFiles.count)")
                        .font(.callout.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
                ProgressView(value: catalogCoverage)
                    .tint(.accentColor)
            }

            HStack(spacing: 12) {
                BurstSummaryValue(title: "Single images", value: "\(counts.singleImages)")
                BurstSimilarityThresholdControl(
                    value: $viewModel.similarityModel.burstSensitivity,
                    valueChanged: similarityThresholdChanged,
                )
            }

            HStack(spacing: 12) {
                Button {
                    showResults(.needsReview)
                } label: {
                    Label("Open Needs Review", systemImage: "arrow.right")
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .disabled(!resultsAreAvailable || counts.needsReview == 0)
            }
        }
        .frame(minWidth: 560)
    }

    private var suggestedPicksCard: some View {
        BurstDashboardCard(title: "Suggested picks", trailing: "From open bursts") {
            if suggestedPicks.isEmpty {
                ContentUnavailableView(
                    "No suggested picks",
                    systemImage: "photo.badge.checkmark",
                    description: Text("Analyze bursts to see recommended frames."),
                )
                .frame(maxWidth: .infinity, minHeight: 100)
            } else {
                ForEach(suggestedPicks) { pick in
                    Button {
                        viewModel.burstReviewQueueFilter = .all
                        viewModel.similarityModel.burstModeActive = true
                        viewModel.selectedFileID = pick.file.id
                    } label: {
                        HStack(spacing: 14) {
                            ThumbnailImageView(
                                file: pick.file,
                                targetSize: 80,
                                style: .grid,
                                showsShimmer: true,
                            )
                            .frame(width: 80, height: 52)
                            .compositingGroup()
                            .clipShape(.rect(cornerRadius: 7))

                            VStack(alignment: .leading, spacing: 3) {
                                Text(pick.file.name)
                                    .font(.headline.monospaced())
                                Text("Burst \(pick.groupID + 1, format: .number)  ·  \(pick.subject ?? "candidate")")
                                    .font(.callout.monospaced())
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Text("Suggested")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.orange)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 5)
                                .background(Color.orange.opacity(0.12), in: .capsule)
                        }
                        .padding(10)
                        .contentShape(.rect)
                    }
                    .buttonStyle(.plain)
                    .background(.quaternary.opacity(0.28), in: .rect(cornerRadius: 10))
                }
            }
        }
    }

    private var counts: BurstGroupsHomeCounts {
        viewModel.burstGroupsHomeCounts
    }

    private var resultsAreAvailable: Bool {
        viewModel.hasCompletedBurstAnalysis
    }

    private var burstGroupCount: Int {
        viewModel.burstGroupsInActiveCatalogScope
            .filter { $0.fileIDs.count > 1 }
            .count
    }

    private var completedCount: Int {
        viewModel.burstReviewQueueCounts.reviewed
    }

    private var coveredFileCount: Int {
        min(
            viewModel.activeCatalogFiles.count,
            counts.singleImages + groupedFileCount,
        )
    }

    private var groupedFileCount: Int {
        viewModel.burstGroupsInActiveCatalogScope
            .filter { $0.fileIDs.count > 1 }
            .reduce(0) { $0 + $1.fileIDs.count }
    }

    private var catalogCoverage: Double {
        guard !viewModel.activeCatalogFiles.isEmpty else { return 0 }
        return Double(coveredFileCount)
            / Double(viewModel.activeCatalogFiles.count)
    }

    private var completionSummary: String {
        resultsAreAvailable ? "Scan complete — categories are ready." : "Run an analysis to build review queues."
    }

    private var burstAnalysisIsBusy: Bool {
        analyzeBurstsRequested || viewModel.burstAnalysisProgress.isRunning
    }

    private var burstScanIsRunning: Bool {
        analyzeBurstsRequested || viewModel.burstAnalysisProgress.isRunning
    }

    private var controlsAreBusy: Bool {
        viewModel.sharpnessModel.isScoring
            || viewModel.similarityModel.isIndexing
            || viewModel.similarityModel.isGrouping
            || burstAnalysisIsBusy
    }

    private var burstScanStatusText: String {
        if viewModel.sharpnessModel.isScoring {
            return "Burst scan in progress — scoring sharpness…"
        }
        if viewModel.similarityModel.isIndexing {
            return viewModel.similarityModel.indexingPhase == .saving
                ? "Burst scan in progress — saving similarity artifacts…"
                : "Burst scan in progress — indexing similarity…"
        }
        if viewModel.similarityModel.isGrouping {
            return "Burst scan in progress — grouping bursts…"
        }
        return viewModel.burstAnalysisProgress.isRunning
            ? viewModel.burstAnalysisProgress.statusText
            : "Burst scan starting…"
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
        viewModel.similarityModel.burstModeActive = true
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
        if viewModel.similarityModel.isIndexing {
            viewModel.similarityModel.cancelIndexing()
        } else {
            Task { await viewModel.indexSimilarity() }
        }
    }
}

private struct BurstGroupsSidebar: View {
    let counts: BurstGroupsHomeCounts
    let groupCount: Int
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
                BurstSidebarRow(title: "All bursts", count: groupCount, systemImage: "square.grid.2x2") {
                    showResults(.all)
                }
                .disabled(!resultsAreAvailable)
                BurstSidebarRow(title: "Needs review", count: counts.needsReview, countColor: .orange, systemImage: "exclamationmark.triangle") {
                    showResults(.needsReview)
                }
                BurstSidebarRow(title: "Reviewed", count: counts.markedReviewed, countColor: .green, systemImage: "checkmark.circle") {
                    showResults(.reviewed)
                }
                BurstSidebarRow(title: "Single images", count: counts.singleImages, countColor: .blue, systemImage: "photo") {
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
    let similarityIndexIsRunning: Bool
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
                    Label(
                        similarityIndexIsRunning ? "Cancel Similarity Index" : "Index Similarity",
                        systemImage: similarityIndexIsRunning ? "xmark.circle" : "scope",
                    )
                }
                .disabled(maintenanceActionsAreDisabled && !similarityIndexIsRunning)
            } label: {
                Label("More", systemImage: "ellipsis")
            }
            .menuStyle(.button)
            .controlSize(.large)
            .help("Catalog maintenance actions")
        }
    }
}

private struct BurstNextUpCard<Trailing: View>: View {
    let resultsAreAvailable: Bool
    let isRunning: Bool
    let runningText: String
    let fileCount: Int
    let reviewedCount: Int
    let groupCount: Int
    let controlsAreBusy: Bool
    let analyzeBursts: () -> Void
    let openNeedsReview: () -> Void
    @ViewBuilder let trailing: Trailing

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
                        Text(resultsAreAvailable ? "Ready to review" : "About a minute")
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

                        if isRunning {
                            trailing
                        }
                    }
                }

                Spacer(minLength: 24)

                BurstReviewProgressRing(
                    reviewedCount: reviewedCount,
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
        if isRunning { return "Finding burst groups" }
        return resultsAreAvailable ? "Continue reviewing your bursts" : "Start by finding burst groups"
    }

    private var detail: String {
        if isRunning { return runningText }
        if resultsAreAvailable {
            return "Compare each sequence side by side and keep the strongest frames."
        }
        return "We’ll cluster visually similar photos so you can compare them side by side."
    }
}

private struct BurstReviewProgressRing: View {
    let reviewedCount: Int
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
                Text("\(reviewedCount) of \(totalCount)")
                    .font(.title3.weight(.bold).monospacedDigit())
                Text("reviewed")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(width: 170, height: 170)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(reviewedCount) of \(totalCount) burst groups reviewed")
    }

    private var progress: Double {
        guard totalCount > 0 else { return 0 }
        return min(Double(reviewedCount) / Double(totalCount), 1)
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

private struct BurstIndexStatusBar: View {
    let isIndexing: Bool
    let hasResults: Bool
    let indexedCount: Int
    let totalCount: Int

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "externaldrive")
            if isIndexing {
                ProgressView().controlSize(.small)
            } else {
                Image(systemName: hasResults ? "checkmark.circle" : "exclamationmark.circle")
                    .foregroundStyle(hasResults ? Color.green : Color.orange)
            }
            Text(hasResults ? "Similarity index ready" : "Similarity index not built")
                .foregroundStyle(hasResults ? Color.secondary : Color.orange)
            Text("·")
            Text("\(displayedCount) of \(totalCount) indexed")
                .monospacedDigit()
        }
        .font(.callout)
        .foregroundStyle(.secondary)
        .padding(.horizontal, 32)
        .frame(maxWidth: .infinity, minHeight: 52, alignment: .leading)
        .background(.quaternary.opacity(0.18))
        .overlay(alignment: .top) { Divider() }
        .accessibilityElement(children: .combine)
    }

    private var displayedCount: Int {
        hasResults ? totalCount : min(indexedCount, totalCount)
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

private struct BurstDashboardCard<Content: View>: View {
    let title: String
    let trailing: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack {
                Text(title).font(.title3.weight(.semibold))
                Spacer()
                Text(trailing)
                    .font(.callout.monospaced())
                    .foregroundStyle(.secondary)
            }
            content
        }
        .padding(22)
        .background(.quaternary.opacity(0.42), in: .rect(cornerRadius: 16))
        .overlay {
            RoundedRectangle(cornerRadius: 16)
                .stroke(.separator.opacity(0.65), lineWidth: 1)
        }
    }
}

private struct BurstQueueMetric: View {
    let title: String
    let count: Int
    let detail: String
    let color: Color
    var isEmphasized = false

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            Text(title).foregroundStyle(.secondary)
            Text(count, format: .number)
                .font(.system(size: 32, weight: .medium, design: .monospaced))
                .foregroundStyle(color)
            Text(detail)
                .font(.callout)
                .foregroundStyle(.secondary)
                .lineLimit(2)
        }
        .frame(maxWidth: .infinity, minHeight: 112, alignment: .topLeading)
        .padding(16)
        .background(color.opacity(isEmphasized ? 0.1 : 0.025), in: .rect(cornerRadius: 12))
        .overlay {
            RoundedRectangle(cornerRadius: 12)
                .stroke(
                    isEmphasized ? color.opacity(0.55) : Color(nsColor: .separatorColor).opacity(0.6),
                    lineWidth: 1,
                )
        }
        .accessibilityElement(children: .combine)
    }
}

private struct BurstSummaryValue: View {
    let title: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(title).foregroundStyle(.secondary)
            Text(value).font(.title3.monospaced())
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(Color.black.opacity(0.12), in: .rect(cornerRadius: 10))
    }
}

private struct BurstSimilarityThresholdControl: View {
    @Binding var value: Float
    let valueChanged: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack {
                Text("Similarity threshold")
                    .foregroundStyle(.secondary)
                Spacer()
                Text(String(format: "%.2f", value))
                    .font(.title3.monospacedDigit())
            }

            Slider(value: $value, in: 0.05 ... 0.60) {
                Text("Similarity threshold")
            }
            .help("Lower values create tighter groups; higher values group similar scenes together")
            .onChange(of: value) { _, _ in
                valueChanged()
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(Color.black.opacity(0.12), in: .rect(cornerRadius: 10))
    }
}

private struct BurstScanBanner<Trailing: View>: View {
    let isComplete: Bool
    let isRunning: Bool
    let runningText: String
    @ViewBuilder let trailing: Trailing

    var body: some View {
        HStack(spacing: 10) {
            if isRunning {
                ProgressView().controlSize(.small)
            } else {
                Image(systemName: isComplete ? "checkmark" : "clock.badge.exclamationmark")
                    .accessibilityHidden(true)
            }
            Text(statusText)
                .lineLimit(1)
            Spacer()
            trailing
        }
        .font(.headline)
        .foregroundStyle(statusColor)
        .padding(.horizontal, 18)
        .padding(.vertical, 13)
        .background(statusColor.opacity(0.1), in: .capsule)
        .overlay { Capsule().stroke(statusColor.opacity(0.45), lineWidth: 1) }
        .accessibilityElement(children: .combine)
    }

    private var statusText: String {
        if isRunning {
            return runningText
        }
        return isComplete
            ? "Burst scan completed — result categories are ready"
            : "Burst scan not completed"
    }

    private var statusColor: Color {
        isRunning ? .blue : (isComplete ? .green : .orange)
    }
}

private struct BurstHomeProgressCount: View {
    let progress: Int
    let estimatedSeconds: Int
    let max: Int

    @State private var displayedEstimatedSeconds = 0

    var body: some View {
        HStack(spacing: 10) {
            ZStack {
                Circle()
                    .stroke(Color.primary.opacity(0.18), lineWidth: 4)

                if max > 0 {
                    Circle()
                        .trim(from: 0, to: completionFraction)
                        .stroke(
                            LinearGradient(
                                colors: [.blue, .cyan],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing,
                            ),
                            style: StrokeStyle(lineWidth: 4, lineCap: .round),
                        )
                        .rotationEffect(.degrees(-90))
                        .animation(.spring(response: 0.6, dampingFraction: 0.8), value: progress)
                }

                Text(progress, format: .number)
                    .font(.callout.weight(.semibold).monospacedDigit())
                    .foregroundStyle(.primary)
                    .contentTransition(.numericText(countsDown: false))
            }
            .frame(width: 44, height: 44)

            Text("Estimated time left: \(formattedTime)")
                .font(.callout.weight(.medium).monospacedDigit())
                .foregroundStyle(.primary)
                .lineLimit(1)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(progress) of \(max). Estimated time left: \(formattedTime)")
        .onAppear {
            updateDisplayedEstimatedSeconds(estimatedSeconds)
        }
        .onChange(of: estimatedSeconds) { _, newValue in
            updateDisplayedEstimatedSeconds(newValue)
        }
    }

    private var completionFraction: Double {
        min(Double(progress) / Double(max), 1)
    }

    private var formattedTime: String {
        if displayedEstimatedSeconds < 60 {
            return "\(displayedEstimatedSeconds)s"
        }
        return "\(displayedEstimatedSeconds / 60)m \(displayedEstimatedSeconds % 60)s"
    }

    private func updateDisplayedEstimatedSeconds(_ newValue: Int) {
        let clampedValue = Swift.max(0, newValue)
        if clampedValue == 0 || displayedEstimatedSeconds == 0 || clampedValue <= displayedEstimatedSeconds {
            displayedEstimatedSeconds = clampedValue
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
