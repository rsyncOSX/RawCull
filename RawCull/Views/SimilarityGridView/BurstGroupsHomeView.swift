import SwiftUI

struct BurstGroupsHomeView: View {
    @Bindable var viewModel: RawCullViewModel
    @Binding var analyzeBurstsRequested: Bool

    var body: some View {
        HStack(spacing: 0) {
            BurstGroupsSidebar(
                counts: counts,
                groupCount: viewModel.similarityModel.burstGroups.filter { $0.fileIDs.count > 1 }.count,
                resultsAreAvailable: resultsAreAvailable,
                showResults: showResults,
                showScoringParameters: { viewModel.activeSheet = .scoringParams },
                reindex: reindex,
            )
            .frame(width: 270)

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    header
                    BurstScanBanner(
                        isComplete: resultsAreAvailable,
                        isRunning: burstScanIsRunning,
                        runningText: burstScanStatusText,
                    ) {
                        burstHomeProgressCounter
                    }

                    ViewThatFits(in: .horizontal) {
                        HStack(alignment: .top, spacing: 20) {
                            reviewQueueCard
                            toolsCard
                        }
                        VStack(spacing: 20) {
                            reviewQueueCard
                            toolsCard
                        }
                    }

                    suggestedPicksCard
                }
                .frame(maxWidth: 1400, alignment: .leading)
                .padding(36)
                .frame(maxWidth: .infinity, alignment: .topLeading)
            }
        }
        .background(Color(nsColor: .windowBackgroundColor))
        .frame(minWidth: 760, minHeight: 560)
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 24) {
            VStack(alignment: .leading, spacing: 8) {
                Text("Burst Groups")
                    .font(.system(size: 34, weight: .bold))
                Text("Analyze the catalog, then open a queue to review frames. \(completionSummary)")
                    .font(.title3)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer()

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
        BurstDashboardCard(title: "Review queue", trailing: "\(viewModel.files.count) files  ·  \(burstGroupCount) groups") {
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
                    Text("\(coveredFileCount) / \(viewModel.files.count)")
                        .font(.callout.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
                ProgressView(value: catalogCoverage)
                    .tint(.accentColor)
            }

            HStack(spacing: 12) {
                BurstSummaryValue(title: "Single images", value: "\(counts.singleImages)")
                BurstSummaryValue(
                    title: "Similarity threshold",
                    value: String(format: "%.2f", viewModel.similarityModel.burstSensitivity),
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

    private var toolsCard: some View {
        BurstDashboardCard(title: "Tools", trailing: "Catalog actions") {
            Button(action: analyzeBursts) {
                HStack(spacing: 14) {
                    Image(systemName: "waveform.path.ecg")
                        .font(.title2)
                        .frame(width: 40, height: 40)
                        .background(.quaternary, in: .rect(cornerRadius: 9))
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Analyze Bursts").font(.headline)
                        Text("Cluster similar frames into review groups")
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Text("Run")
                        .fontWeight(.semibold)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .foregroundStyle(.white)
                        .background(Color.accentColor, in: .rect(cornerRadius: 8))
                }
                .padding(14)
                .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .disabled(controlsAreBusy || viewModel.files.isEmpty)
            .background(Color.accentColor.opacity(0.1), in: .rect(cornerRadius: 12))
            .overlay {
                RoundedRectangle(cornerRadius: 12)
                    .stroke(Color.accentColor.opacity(0.55), lineWidth: 1)
            }

            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                BurstToolTile(
                    title: "Scoring Parameters",
                    detail: "Threshold, pick-of-burst, tag weights",
                    systemImage: "slider.horizontal.3",
                    action: { viewModel.activeSheet = .scoringParams },
                )
                BurstToolTile(
                    title: "Re-index",
                    detail: "Refresh embeddings for this catalog",
                    systemImage: "arrow.clockwise",
                    action: reindex,
                )
                BurstToolTile(
                    title: "Single Images",
                    detail: "\(counts.singleImages) frames outside burst groups",
                    systemImage: "photo",
                    action: { showResults(.singleImages) },
                )
                BurstToolTile(
                    title: "Index Similarity",
                    detail: "Build or refresh similarity index",
                    systemImage: "scope",
                    action: indexSimilarity,
                )
            }
        }
        .frame(minWidth: 470)
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
        viewModel.similarityModel.burstGroups.filter { $0.fileIDs.count > 1 }.count
    }

    private var coveredFileCount: Int {
        min(viewModel.files.count, counts.singleImages + groupedFileCount)
    }

    private var groupedFileCount: Int {
        viewModel.similarityModel.burstGroups
            .filter { $0.fileIDs.count > 1 }
            .reduce(0) { $0 + $1.fileIDs.count }
    }

    private var catalogCoverage: Double {
        guard !viewModel.files.isEmpty else { return 0 }
        return Double(coveredFileCount) / Double(viewModel.files.count)
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
            return "Burst scan in progress — indexing similarity…"
        }
        if viewModel.similarityModel.isGrouping {
            return "Burst scan in progress — grouping bursts…"
        }
        return viewModel.burstAnalysisProgress.isRunning
            ? viewModel.burstAnalysisProgress.statusText
            : "Burst scan starting…"
    }

    private var suggestedPicks: [BurstSuggestedPick] {
        let filesByID = Dictionary(uniqueKeysWithValues: viewModel.files.map { ($0.id, $0) })
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

    private func runWithAutoScoring(_ action: @escaping @MainActor () async -> Void) {
        Task {
            if viewModel.sharpnessModel.scores.isEmpty {
                await viewModel.calibrateAndScoreCurrentCatalog()
            }
            await action()
        }
    }

    private func analyzeBursts() {
        analyzeBurstsRequested = true
        runWithAutoScoring {
            defer { analyzeBurstsRequested = false }
            await viewModel.analyzeBursts()
        }
    }

    private func reindex() {
        Task { await viewModel.reindexBurstAnalysis() }
    }

    private func indexSimilarity() {
        if viewModel.similarityModel.isIndexing {
            viewModel.similarityModel.cancelIndexing()
        } else {
            runWithAutoScoring { await viewModel.indexSimilarity() }
        }
    }
}

private struct BurstGroupsSidebar: View {
    let counts: BurstGroupsHomeCounts
    let groupCount: Int
    let resultsAreAvailable: Bool
    let showResults: (BurstReviewQueueFilter) -> Void
    let showScoringParameters: () -> Void
    let reindex: () -> Void

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
                BurstSidebarRow(title: "Burst Groups", systemImage: "line.3.horizontal", isSelected: true) {}
                BurstSidebarRow(title: "All bursts", count: groupCount, systemImage: "square.grid.2x2") {
                    showResults(.all)
                }
                .disabled(!resultsAreAvailable)
                BurstSidebarRow(title: "Cull workspace", systemImage: "rectangle.split.2x1") {
                    showResults(.needsReview)
                }
                .disabled(!resultsAreAvailable)
            }

            sidebarSection("QUEUES") {
                BurstSidebarRow(title: "Deferred", count: counts.deferred, countColor: .orange, systemImage: "clock") {
                    showResults(.deferred)
                }
                BurstSidebarRow(title: "Marked Reviewed", count: counts.markedReviewed, countColor: .green, systemImage: "checkmark.circle") {
                    showResults(.markedReviewed)
                }
                BurstSidebarRow(title: "Needs Review", count: counts.needsReview, countColor: .red, systemImage: "tray.full") {
                    showResults(.needsReview)
                }
                BurstSidebarRow(title: "Single Images", count: counts.singleImages, countColor: .blue, systemImage: "photo") {
                    showResults(.singleImages)
                }
            }
            .disabled(!resultsAreAvailable)

            sidebarSection("TOOLS") {
                BurstSidebarRow(title: "Scoring Parameters", systemImage: "slider.horizontal.3", action: showScoringParameters)
                BurstSidebarRow(title: "Re-index", systemImage: "arrow.clockwise", action: reindex)
            }

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

private struct BurstToolTile: View {
    let title: String
    let detail: String
    let systemImage: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 12) {
                Image(systemName: systemImage)
                    .font(.title3)
                    .frame(width: 38, height: 38)
                    .background(.quaternary, in: .rect(cornerRadius: 9))
                Text(title).font(.headline)
                Text(detail)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, minHeight: 120, alignment: .topLeading)
            .padding(16)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .background(Color.black.opacity(0.08), in: .rect(cornerRadius: 12))
        .overlay {
            RoundedRectangle(cornerRadius: 12)
                .stroke(.separator.opacity(0.6), lineWidth: 1)
        }
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
