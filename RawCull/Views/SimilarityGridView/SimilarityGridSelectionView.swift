//
//  SimilarityGridSelectionView.swift
//  RawCull
//
//  Similarity and burst-grouping home with category-based result browsing.
//

import AppKit
import SwiftUI

struct SimilarityGridSelectionView: View {
    @Bindable var viewModel: RawCullViewModel

    @State private var analyzeBurstsRequested: Bool = false
    @State private var pendingRegroupTask: Task<Void, Never>?

    @Binding var nsImage: NSImage?
    @Binding var cgImage: CGImage?

    var body: some View {
        if viewModel.similarityModel.burstModeActive {
            CullingGridView(viewModel: viewModel) {
                burstGroupHeaderControls
            }
        } else {
            BurstGroupsHomeView(
                viewModel: viewModel,
                analyzeBurstsRequested: $analyzeBurstsRequested,
            )
        }
    }

    @ViewBuilder
    private var burstGroupHeaderControls: some View {
        let isIndexing = viewModel.similarityModel.isIndexing
        let isGrouping = viewModel.similarityModel.isGrouping
        let burstAnalysisIsBusy = analyzeBurstsRequested || viewModel.burstAnalysisProgress.isRunning
        let sharpnessControlsDisabled = viewModel.sharpnessModel.isScoring
            || isIndexing
            || isGrouping
            || burstAnalysisIsBusy

        SharpnessIntentControlsView(
            viewModel: viewModel,
            isDisabled: sharpnessControlsDisabled,
            showsParametersButton: true,
            style: .compactInfo,
        )

        Divider().frame(height: 16)

        HStack(spacing: 4) {
            Slider(
                value: $viewModel.similarityModel.burstSensitivity,
                in: 0.05 ... 0.60,
            )
            .frame(width: 70)
            .help("Burst sensitivity — lower = tighter groups, higher = similar scenes grouped together")
            .onChange(of: viewModel.similarityModel.burstSensitivity) { _, _ in
                pendingRegroupTask?.cancel()
                pendingRegroupTask = Task {
                    try? await Task.sleep(nanoseconds: 200_000_000)
                    if Task.isCancelled {
                        return
                    }
                    await viewModel.reGroupBursts()
                }
            }

            Text(
                String(
                    format: "%.2f · %d groups",
                    viewModel.similarityModel.burstSensitivity,
                    viewModel.similarityModel.burstGroups.count,
                ),
            )
            .font(.caption2.monospacedDigit())
            .foregroundStyle(.secondary)
            .frame(minWidth: 84, alignment: .leading)
        }

        Button {
            viewModel.similarityModel.burstModeActive = false
            viewModel.burstReviewQueueFilter = .all
        } label: {
            Label("Exit Groups", systemImage: "xmark.circle")
        }
        .font(.caption)
        .help("Return to the burst groups home")

        if viewModel.sharpnessModel.isCalibratingSharpnessScoring {
            HStack {
                ProgressView()
                Text("Calibrating focus-mask threshold, please wait...")
            }
        }
    }
}

private struct BurstGroupsHomeView: View {
    @Bindable var viewModel: RawCullViewModel
    @Binding var analyzeBurstsRequested: Bool

    private let columns = [
        GridItem(.adaptive(minimum: 160, maximum: 210), spacing: 12)
    ]

    var body: some View {
        ZStack {
            ScrollView {
                VStack(spacing: 16) {
                    VStack(spacing: 6) {
                        Text("Burst Groups")
                            .font(.largeTitle.weight(.semibold))
                        Text("Analyze the catalog, then open a category to review its images.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    .multilineTextAlignment(.center)

                    BurstScanStatusView(
                        isComplete: resultsAreAvailable,
                        isRunning: burstScanIsRunning,
                        runningText: burstScanStatusText,
                    )

                    LazyVGrid(columns: columns, spacing: 12) {
                        BurstHomeButton(
                            title: "Scoring Parameters",
                            systemImage: "slider.horizontal.3",
                            help: "Configure sharpness scoring parameters",
                            isDisabled: controlsAreBusy,
                        ) {
                            viewModel.activeSheet = .scoringParams
                        }

                        BurstHomeButton(
                            title: indexButtonTitle,
                            systemImage: viewModel.similarityModel.isIndexing ? "xmark.circle" : "wand.and.sparkles",
                            help: viewModel.similarityModel.isIndexing
                                ? "Cancel similarity indexing"
                                : "Compute visual feature embeddings for all images in this catalog",
                            isDisabled: burstAnalysisIsBusy || viewModel.files.isEmpty,
                        ) {
                            if viewModel.similarityModel.isIndexing {
                                viewModel.similarityModel.cancelIndexing()
                            } else {
                                runWithAutoScoring { await viewModel.indexSimilarity() }
                            }
                        }

                        BurstHomeButton(
                            title: "Analyze Bursts",
                            systemImage: "square.stack.3d.up",
                            help: "Group burst sequences and recommend best frames",
                            isDisabled: controlsAreBusy || viewModel.files.isEmpty,
                        ) {
                            analyzeBurstsRequested = true
                            runWithAutoScoring {
                                defer { analyzeBurstsRequested = false }
                                await viewModel.analyzeBursts()
                            }
                        }

                        BurstHomeButton(
                            title: "Single Images",
                            count: counts.singleImages,
                            countColor: .blue,
                            systemImage: "photo",
                            help: "Show images that are not in a burst group",
                            isDisabled: !resultsAreAvailable,
                        ) {
                            showResults(.singleImages)
                        }

                        BurstHomeButton(
                            title: "Deferred",
                            count: counts.deferred,
                            countColor: .orange,
                            systemImage: "clock",
                            help: "Show deferred burst groups",
                            isDisabled: !resultsAreAvailable,
                        ) {
                            showResults(.deferred)
                        }

                        BurstHomeButton(
                            title: "Marked Reviewed",
                            count: counts.markedReviewed,
                            countColor: .green,
                            systemImage: "checkmark.circle",
                            help: "Show reviewed burst groups",
                            isDisabled: !resultsAreAvailable,
                        ) {
                            showResults(.markedReviewed)
                        }

                        BurstHomeButton(
                            title: "Needs Review",
                            count: counts.needsReview,
                            countColor: .red,
                            systemImage: "tray.full",
                            help: "Show burst groups that need review",
                            isDisabled: !resultsAreAvailable,
                        ) {
                            showResults(.needsReview)
                        }
                    }
                    .frame(maxWidth: 720)
                }
                .frame(maxWidth: .infinity)
                .padding(24)
            }

            CullingGridProgressOverlay(viewModel: viewModel)
        }
        .frame(minWidth: 400, minHeight: 400)
    }

    private var counts: BurstGroupsHomeCounts {
        viewModel.burstGroupsHomeCounts
    }

    private var burstAnalysisIsBusy: Bool {
        analyzeBurstsRequested || viewModel.burstAnalysisProgress.isRunning
    }

    private var burstScanIsRunning: Bool {
        analyzeBurstsRequested || viewModel.burstAnalysisProgress.isRunning
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

    private var controlsAreBusy: Bool {
        viewModel.sharpnessModel.isScoring
            || viewModel.similarityModel.isIndexing
            || viewModel.similarityModel.isGrouping
            || burstAnalysisIsBusy
    }

    private var resultsAreAvailable: Bool {
        viewModel.hasCompletedBurstAnalysis
    }

    private var indexButtonTitle: String {
        if viewModel.similarityModel.isIndexing {
            return "Cancel Indexing"
        }
        return viewModel.similarityModel.embeddings.isEmpty ? "Index Similarity" : "Re-index"
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
}

private struct BurstHomeButton: View {
    let title: String
    let count: Int?
    let countColor: Color
    let systemImage: String
    let help: String
    let isDisabled: Bool
    let action: () -> Void

    init(
        title: String,
        count: Int? = nil,
        countColor: Color = .accentColor,
        systemImage: String,
        help: String,
        isDisabled: Bool,
        action: @escaping () -> Void,
    ) {
        self.title = title
        self.count = count
        self.countColor = countColor
        self.systemImage = systemImage
        self.help = help
        self.isDisabled = isDisabled
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            VStack(spacing: 8) {
                Image(systemName: systemImage)
                    .font(.system(size: 20, weight: .medium))
                    .accessibilityHidden(true)
                buttonTitle
            }
            .frame(maxWidth: .infinity, minHeight: 64)
            .padding(8)
        }
        .buttonStyle(.bordered)
        .controlSize(.regular)
        .disabled(isDisabled)
        .help(help)
        .accessibilityLabel(accessibilityTitle)
        .accessibilityHint(help)
    }

    @ViewBuilder
    private var buttonTitle: some View {
        if let count {
            HStack(spacing: 4) {
                Text(count, format: .number)
                    .fontWeight(.bold)
                    .monospacedDigit()
                    .foregroundStyle(countColor)
                Text(title)
            }
            .font(.subheadline.weight(.semibold))
            .multilineTextAlignment(.center)
        } else {
            Text(title)
                .font(.subheadline.weight(.semibold))
                .multilineTextAlignment(.center)
        }
    }

    private var accessibilityTitle: String {
        if let count {
            return "\(count) \(title)"
        }
        return title
    }
}

private struct BurstScanStatusView: View {
    let isComplete: Bool
    let isRunning: Bool
    let runningText: String

    var body: some View {
        HStack(spacing: 8) {
            if isRunning {
                ProgressView()
                    .controlSize(.small)
            } else {
                Image(systemName: isComplete ? "checkmark.circle.fill" : "clock.badge.exclamationmark")
                    .accessibilityHidden(true)
            }

            Text(statusText)
        }
        .font(.callout.weight(.medium))
        .foregroundStyle(statusColor)
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
        .background(statusColor.opacity(0.12), in: .capsule)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(statusText)
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
        if isRunning {
            return .blue
        }
        return isComplete ? .green : .orange
    }
}
