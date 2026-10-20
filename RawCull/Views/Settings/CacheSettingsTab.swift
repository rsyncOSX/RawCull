//
//  CacheSettingsTab.swift
//  RawCull
//
//  Created by Thomas Evensen on 08/02/2026.
//

import Foundation
import SwiftUI

struct CacheSettingsTab: View {
    let aiSettingsModel: RawCullAISettingsModel
    let viewModel: RawCullViewModel
    @State private var savedFilesSize = 0
    @State private var showDeleteSavedFiles = false
    @State private var isDeletingSavedFiles = false

    let combinedReviewFeature: CombinedReviewFeature
    @State private var combinedReviewSize = 0
    @State private var purgeError: String?
    @State private var currentThumbnailDiskCacheSize = 0
    @State private var currentFullSizeJPGCacheSize = 0
    @State private var currentSimilarityArtifactCacheSize = 0
    @State private var currentBurstAnalysisCacheSize = 0
    @State private var currentGridCacheSize = 0
    @State private var currentPreviewCacheSize = 0
    @State private var isLoadingDiskCaches = false
    @State private var isPurging = false
    // Periphery 3.8 does not follow projected-value reads from SDK 27's macro-backed @State.
    // periphery:ignore
    @State private var showPurgeConfirmation = false

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                SettingsCard {
                    HStack {
                        VStack(alignment: .leading, spacing: 3) {
                            Text("All Cache Data")
                                .font(.headline)
                            Text("Delete memory caches, disk caches and saved Combined Reviews.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        if isPurging {
                            ProgressView()
                                .controlSize(.small)
                        }
                        Text(isLoadingDiskCaches ? "Calculating…" : formatBytes(totalCacheSize))
                            .font(.caption)
                            .monospacedDigit()
                        Button("Delete Cache", role: .destructive) {
                            showPurgeConfirmation = true
                        }
                        .disabled(isLoadingDiskCaches || isPurging || combinedReviewFeature.lease.isHeld)
                    }
                }

                Divider()

                SettingsCard {
                    VStack(spacing: 12) {
                        cacheRow("Preview Cache", size: currentPreviewCacheSize)
                        cacheRow("Grid Thumbnail Cache", size: currentGridCacheSize)
                        cacheRow("Thumbnail Cache", size: currentThumbnailDiskCacheSize)
                        cacheRow("Full-size JPG Cache", size: currentFullSizeJPGCacheSize)
                        cacheRow("Similarity Artifact Cache", size: currentSimilarityArtifactCacheSize)
                        cacheRow("Burst Group Cache", size: currentBurstAnalysisCacheSize)
                        cacheRow("Combined Reviews", size: combinedReviewSize)
                    }
                }
                Divider()

                SettingsCard {
                    HStack {
                        VStack(alignment: .leading, spacing: 3) {
                            Text("Saved Files").font(.headline)
                            Text("Saved catalog records, ratings and analysis results.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Text(ByteCountFormatStyle(style: .memory).format(Int64(savedFilesSize)))
                            .font(.caption)
                            .monospacedDigit()
                        Button("Delete Saved Files", role: .destructive) {
                            showDeleteSavedFiles = true
                        }
                        .disabled(viewModel.isCreatingThumbnails || isDeletingSavedFiles
                            || viewModel.cullingModel.persistenceError != nil)
                    }
                }

                Divider()

                SettingsCard {
                    SavedBurstSimilarityEvidenceView(
                        evidence: aiSettingsModel.savedBurstEvidence,
                        scanFailure: aiSettingsModel.savedBurstScanFailure,
                        isScanning: aiSettingsModel.isScanningSavedBurstData,
                    )
                }
            }
        }
        .alert("Delete Saved Files?", isPresented: $showDeleteSavedFiles) {
            Button("Delete Saved Files", role: .destructive) {
                isDeletingSavedFiles = true
                viewModel.clearAllCullingState()
                Task {
                    _ = await viewModel.cullingModel.flushPersistence()
                    savedFilesSize = await WriteSavedFilesJSON.diskUsage()
                    isDeletingSavedFiles = false
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("All saved catalog records, ratings and analysis results will be deleted. Original photos will be kept.")
        }
        .confirmationDialog("Delete Cache?", isPresented: $showPurgeConfirmation) {
            Button("Delete Cache", role: .destructive) { purge() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("All memory caches, cached thumbnails and previews, similarity artifacts, burst analysis results, and saved Combined Reviews (including masks, retained input images and review history) will be deleted. Original photos, settings and downloaded AI models will be kept.")
        }
        .alert("Could not clear cache", isPresented: Binding(
            get: { purgeError != nil }, set: {
                if !$0 {
                    purgeError = nil
                }
            },
        )) {
            Button("OK") { purgeError = nil }
        } message: {
            Text(purgeError ?? "")
        }
        .onChange(of: combinedReviewFeature.isRunning) { _, running in
            if !running {
                Task { await refreshDiskCacheUsage() }
            }
        }
        .task {
            savedFilesSize = await WriteSavedFilesJSON.diskUsage()
            await SharedMemoryCache.shared.refreshConfig()
            refreshMemoryCacheUsage()
            await refreshDiskCacheUsage()
            await aiSettingsModel.refresh()

            while !Task.isCancelled {
                do {
                    try await Task.sleep(for: .seconds(2))
                } catch {
                    break
                }
                refreshMemoryCacheUsage()
            }
        }
    }

    private func refreshMemoryCacheUsage() {
        currentPreviewCacheSize = SharedMemoryCache.shared.getMemoryCacheCurrentCost()
        currentGridCacheSize = SharedMemoryCache.shared.getGridCacheCurrentCost()
    }

    private func refreshDiskCacheUsage() async {
        isLoadingDiskCaches = true

        async let thumbnailSize = SharedMemoryCache.shared.getDiskCacheSize()
        async let fullSizeJPGSize = SharedMemoryCache.shared.getFullSizeJPGCacheSize()
        async let similarityArtifactUsage = PerFileAnalysisArtifactStore.shared.usage()
        async let burstAnalysisUsage = BurstAnalysisCache.shared.getDiskCacheUsage()
        let (thumbnail, fullSizeJPG, similarityArtifacts, burstAnalysis) = await (
            thumbnailSize,
            fullSizeJPGSize,
            similarityArtifactUsage,
            burstAnalysisUsage,
        )

        guard !Task.isCancelled else { return }
        currentThumbnailDiskCacheSize = thumbnail
        currentFullSizeJPGCacheSize = fullSizeJPG
        currentSimilarityArtifactCacheSize = similarityArtifacts.size
        currentBurstAnalysisCacheSize = burstAnalysis.size
        combinedReviewSize = await (try? combinedReviewFeature.store.usage()) ?? 0
        isLoadingDiskCaches = false
    }

    private func purge() {
        isPurging = true
        Task {
            do {
                try await combinedReviewFeature.clearAllReviews()
                await SharedMemoryCache.shared.clearCaches()
                await PerFileAnalysisArtifactStore.shared.clear()
                await BurstAnalysisCache.shared.clear()
                refreshMemoryCacheUsage()
            } catch {
                purgeError = error.localizedDescription
            }
            await refreshDiskCacheUsage()
            await aiSettingsModel.refresh()
            isPurging = false
        }
    }

    private func formatBytes(_ bytes: Int) -> String {
        guard bytes > 0 else { return "0 B" }
        return ByteCountFormatStyle(style: .memory).format(Int64(bytes))
    }

    private var totalCacheSize: Int {
        currentPreviewCacheSize + currentGridCacheSize + currentThumbnailDiskCacheSize
            + currentFullSizeJPGCacheSize + currentSimilarityArtifactCacheSize
            + currentBurstAnalysisCacheSize + combinedReviewSize
    }

    private func cacheRow(_ title: LocalizedStringKey, size: Int) -> some View {
        HStack {
            Text(title)
            Spacer()
            Text(isLoadingDiskCaches ? "Calculating…" : formatBytes(size))
                .monospacedDigit()
                .foregroundStyle(.secondary)
        }
        .font(.caption)
        .foregroundStyle(.secondary)
        .accessibilityElement(children: .combine)
    }
}

private struct SavedBurstSimilarityEvidenceView: View {
    let evidence: RawCullSavedBurstEvidence?
    let scanFailure: String?
    let isScanning: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Image(systemName: iconName)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(statusColor)
                    .accessibilityHidden(true)

                Text("Saved burst evidence:")
                    .font(.system(size: 12, weight: .medium))

                Text(statusTitle)
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .foregroundStyle(statusColor)

                Spacer()

                if isScanning {
                    ProgressView()
                        .controlSize(.small)
                        .fixedSize()
                }
            }
            Text(detailText)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Saved burst similarity evidence")
        .accessibilityValue("\(statusTitle). \(detailText)")
    }

    private var statusTitle: String {
        if scanFailure != nil {
            return "Unavailable"
        }
        guard let evidence else { return "Scanning..." }
        return switch evidence.backend {
        case .noSavedData: "No saved data"
        case .clip: "CLIP"
        case .visionFeaturePrint: "Vision"
        case .visionFallback: "Vision fallback"
        case .mixed: "Mixed"
        }
    }

    private var iconName: String {
        if scanFailure != nil {
            return "xmark.circle.fill"
        }
        guard let evidence else { return "internaldrive" }
        return switch evidence.backend {
        case .noSavedData: "tray"
        case .clip: "checkmark.circle.fill"
        case .visionFeaturePrint: "eye.circle.fill"
        case .visionFallback: "arrow.counterclockwise.circle.fill"
        case .mixed: "square.stack.3d.up.fill"
        }
    }

    private var statusColor: Color {
        if scanFailure != nil {
            return .red
        }
        guard let evidence else { return .secondary }
        return switch evidence.backend {
        case .noSavedData: .secondary
        case .clip: .green
        case .visionFeaturePrint: .blue
        case .visionFallback, .mixed: .orange
        }
    }

    private var detailText: String {
        if let scanFailure {
            return "RawCull could not inspect saved burst data: \(scanFailure)"
        }
        guard let evidence else {
            return "Scanning RawCull's saved burst analysis caches."
        }
        guard evidence.totalEmbeddingCount > 0 else {
            if evidence.skippedCacheFileCount > 0 {
                return "No current-format burst embeddings were found. " +
                    "\(countLabel(evidence.skippedCacheFileCount, singular: "cache file")) could not be read or was outdated."
            }
            return "No saved burst analysis embeddings were found. Run Analyze Bursts to create cache evidence."
        }

        let embeddings = countLabel(evidence.totalEmbeddingCount, singular: "embedding")
        let catalogs = countLabel(evidence.decodedCatalogCount, singular: "saved catalog")
        let groups = countLabel(evidence.burstGroupCount, singular: "burst group")
        var text = "Found \(embeddings) in \(catalogs) across \(groups): " +
            "\(evidence.clipEmbeddingCount) CLIP and \(evidence.visionEmbeddingCount) Vision."
        if evidence.skippedCacheFileCount > 0 {
            text += " \(countLabel(evidence.skippedCacheFileCount, singular: "cache file")) could not be read or was outdated."
        }
        return text + " Counts come from saved payloads, not the preference control."
    }

    private func countLabel(_ count: Int, singular: String) -> String {
        "\(count) \(singular)\(count == 1 ? "" : "s")"
    }
}
