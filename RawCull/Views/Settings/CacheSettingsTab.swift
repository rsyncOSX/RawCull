//
//  CacheSettingsTab.swift
//  RawCull
//
//  Created by Thomas Evensen on 08/02/2026.
//

import Foundation
import SwiftUI

struct CacheSettingsTab: View {
    private var settingsManager: SettingsViewModel {
        SettingsViewModel.shared
    }

    @State private var currentThumbnailDiskCacheSize = 0
    @State private var currentFullSizeJPGCacheSize = 0
    @State private var currentSimilarityArtifactCacheSize = 0
    @State private var currentSimilarityArtifactCacheCount = 0
    @State private var currentBurstAnalysisCacheSize = 0
    @State private var currentBurstAnalysisCacheCount = 0
    @State private var currentGridCacheSize = 0
    @State private var currentGridCacheCount = 0
    @State private var currentPreviewCacheSize = 0
    @State private var currentPreviewCacheCount = 0
    @State private var isLoadingDiskCaches = false
    @State private var cachePendingPurge: DiskCacheKind?
    @State private var purgingCache: DiskCacheKind?
    // Periphery 3.8 does not follow projected-value reads from SDK 27's macro-backed @State.
    // periphery:ignore
    @State private var showPurgeConfirmation = false
    @State private var memoryModel = MemoryViewModel()

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                MemoryCachesSection(
                    previewSize: formatBytes(currentPreviewCacheSize),
                    previewLimit: formatBytes(SharedMemoryCache.shared.memoryCache.totalCostLimit),
                    previewConfiguredLimit: formatMegabytes(settingsManager.memoryCacheSizeMB),
                    previewCount: currentPreviewCacheCount,
                    gridSize: formatBytes(currentGridCacheSize),
                    gridLimit: formatBytes(SharedMemoryCache.shared.gridThumbnailCache.totalCostLimit),
                    gridConfiguredLimit: formatMegabytes(settingsManager.gridCacheSizeMB),
                    gridCount: currentGridCacheCount,
                    freeMemory: formatBytes(Int(freeMemoryBytes())),
                )

                DiskCachesSection(
                    thumbnailSize: formatBytes(currentThumbnailDiskCacheSize),
                    thumbnailPath: displayPath(SharedMemoryCache.shared.thumbnailDiskCacheDirectory),
                    fullSizeJPGSize: formatBytes(currentFullSizeJPGCacheSize),
                    fullSizeJPGPath: displayPath(SharedMemoryCache.shared.fullSizeJPGDiskCacheDirectory),
                    similarityArtifactSize: formatBytes(currentSimilarityArtifactCacheSize),
                    similarityArtifactCount: currentSimilarityArtifactCacheCount,
                    similarityArtifactPath: displayPath(
                        PerFileAnalysisArtifactStore.shared.storageDirectory,
                    ),
                    burstAnalysisSize: formatBytes(currentBurstAnalysisCacheSize),
                    burstAnalysisCount: currentBurstAnalysisCacheCount,
                    burstAnalysisPath: displayPath(BurstAnalysisCache.shared.storageDirectory),
                    isLoading: isLoadingDiskCaches,
                    purgingCache: purgingCache,
                    cachePendingPurge: $cachePendingPurge,
                    showPurgeConfirmation: $showPurgeConfirmation,
                )
            }
        }
        .confirmationDialog(
            "Clear \(cachePendingPurge?.title ?? "Cache")?",
            isPresented: $showPurgeConfirmation,
        ) {
            if let cachePendingPurge {
                Button("Clear", role: .destructive) {
                    purge(cachePendingPurge)
                }
            }
            Button("Cancel", role: .cancel) {
                cachePendingPurge = nil
            }
        } message: {
            Text(cachePendingPurge?.confirmationMessage ?? "The cache will be rebuilt as needed.")
        }
        .task {
            await SharedMemoryCache.shared.refreshConfig()
            refreshMemoryCacheUsage()
            await memoryModel.updateMemoryStats()
            await refreshDiskCacheUsage()

            while !Task.isCancelled {
                do {
                    try await Task.sleep(for: .seconds(2))
                } catch {
                    break
                }
                refreshMemoryCacheUsage()
                await memoryModel.updateMemoryStats()
            }
        }
    }

    private func refreshMemoryCacheUsage() {
        currentPreviewCacheSize = SharedMemoryCache.shared.getMemoryCacheCurrentCost()
        currentPreviewCacheCount = SharedMemoryCache.shared.getMemoryCacheCount()
        currentGridCacheSize = SharedMemoryCache.shared.getGridCacheCurrentCost()
        currentGridCacheCount = SharedMemoryCache.shared.getGridCacheCount()
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
        currentSimilarityArtifactCacheCount = similarityArtifacts.entryCount
        currentBurstAnalysisCacheSize = burstAnalysis.size
        currentBurstAnalysisCacheCount = burstAnalysis.fileCount
        isLoadingDiskCaches = false
    }

    private func purge(_ cache: DiskCacheKind) {
        cachePendingPurge = nil
        purgingCache = cache

        Task {
            switch cache {
            case .thumbnails:
                await SharedMemoryCache.shared.pruneDiskCache(maxAgeInDays: 0)

            case .fullSizeJPGs:
                await SharedMemoryCache.shared.pruneFullSizeJPGCache(maxAgeInDays: 0)

            case .similarityArtifacts:
                await PerFileAnalysisArtifactStore.shared.clear()

            case .burstAnalysis:
                await BurstAnalysisCache.shared.clear()
            }

            await refreshDiskCacheUsage()
            purgingCache = nil
        }
    }

    private func formatBytes(_ bytes: Int) -> String {
        guard bytes > 0 else { return "0 B" }
        return ByteCountFormatStyle(style: .memory).format(Int64(bytes))
    }

    private func formatMegabytes(_ megabytes: Int) -> String {
        formatBytes(megabytes * 1024 * 1024)
    }

    private func displayPath(_ url: URL) -> String {
        (url.path as NSString).abbreviatingWithTildeInPath
    }

    private func freeMemoryBytes() -> UInt64 {
        let physical = ProcessInfo.processInfo.physicalMemory
        return memoryModel.usedMemory < physical
            ? physical - memoryModel.usedMemory
            : 0
    }
}

private enum DiskCacheKind: Hashable, Identifiable {
    case thumbnails
    case fullSizeJPGs
    case similarityArtifacts
    case burstAnalysis

    var id: Self {
        self
    }

    var title: String {
        switch self {
        case .thumbnails: "Thumbnail Cache"
        case .fullSizeJPGs: "Full-size JPG Cache"
        case .similarityArtifacts: "Similarity Artifact Cache"
        case .burstAnalysis: "Burst Group Cache"
        }
    }

    var confirmationMessage: String {
        switch self {
        case .thumbnails:
            "Cached thumbnails will be deleted and generated again when needed."

        case .fullSizeJPGs:
            "Cached full-size previews will be deleted and generated again when needed."

        case .similarityArtifacts:
            "Saved per-file similarity artifacts will be deleted and indexed again when needed."

        case .burstAnalysis:
            "Saved burst groups and analysis results for all catalogs will be deleted and analyzed again when needed."
        }
    }
}

private struct MemoryCachesSection: View {
    let previewSize: String
    let previewLimit: String
    let previewConfiguredLimit: String
    let previewCount: Int
    let gridSize: String
    let gridLimit: String
    let gridConfiguredLimit: String
    let gridCount: Int
    let freeMemory: String

    var body: some View {
        SettingsCard {
            VStack(alignment: .leading, spacing: 12) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("In Memory")
                        .font(.headline)
                    Text("Temporary image data kept in RAM and discarded when RawCull quits.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Divider()

                MemoryCacheRow(
                    icon: "photo",
                    title: "Preview Cache",
                    size: previewSize,
                    detail: "\(previewCount) previews · \(previewLimit) current limit · \(previewConfiguredLimit) configured maximum",
                )

                MemoryCacheRow(
                    icon: "square.grid.2x2",
                    title: "Grid Thumbnail Cache",
                    size: gridSize,
                    detail: "\(gridCount) thumbnails · \(gridLimit) current limit · \(gridConfiguredLimit) configured maximum",
                )

                Divider()

                Text("Supported configured limits: \(formatRange(CacheSettingsLimits.memoryMinMB, CacheSettingsLimits.memoryMaxMB)) for previews and \(formatRange(CacheSettingsLimits.gridMinMB, CacheSettingsLimits.gridMaxMB)) for grid thumbnails.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)

                Text("Free memory: \(freeMemory)")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func formatRange(_ lower: Int, _ upper: Int) -> String {
        let style = ByteCountFormatStyle(style: .memory)
        let lowerValue = style.format(Int64(lower * 1024 * 1024))
        let upperValue = style.format(Int64(upper * 1024 * 1024))
        return "\(lowerValue)–\(upperValue)"
    }
}

private struct MemoryCacheRow: View {
    let icon: String
    let title: String
    let size: String
    let detail: String

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: icon)
                .frame(width: 18)
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 3) {
                HStack {
                    Text(title)
                        .font(.subheadline.weight(.medium))
                    Spacer()
                    Text(size)
                        .font(.subheadline.monospacedDigit().weight(.semibold))
                }
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .accessibilityElement(children: .combine)
    }
}

private struct DiskCachesSection: View {
    let thumbnailSize: String
    let thumbnailPath: String
    let fullSizeJPGSize: String
    let fullSizeJPGPath: String
    let similarityArtifactSize: String
    let similarityArtifactCount: Int
    let similarityArtifactPath: String
    let burstAnalysisSize: String
    let burstAnalysisCount: Int
    let burstAnalysisPath: String
    let isLoading: Bool
    let purgingCache: DiskCacheKind?
    @Binding var cachePendingPurge: DiskCacheKind?
    @Binding var showPurgeConfirmation: Bool

    var body: some View {
        SettingsCard {
            VStack(alignment: .leading, spacing: 12) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("On Disk")
                        .font(.headline)
                    Text("Persistent, purgeable cache data. RawCull rebuilds deleted data when it is needed again.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Divider()

                DiskCacheRow(
                    kind: .thumbnails,
                    icon: "photo.stack",
                    size: thumbnailSize,
                    detail: "JPEG thumbnails",
                    path: thumbnailPath,
                    isLoading: isLoading,
                    isPurging: purgingCache == .thumbnails,
                    isPurgeInProgress: purgingCache != nil,
                    cachePendingPurge: $cachePendingPurge,
                    showPurgeConfirmation: $showPurgeConfirmation,
                )

                Divider()

                DiskCacheRow(
                    kind: .fullSizeJPGs,
                    icon: "photo.on.rectangle.angled",
                    size: fullSizeJPGSize,
                    detail: "Full-size JPEG previews",
                    path: fullSizeJPGPath,
                    isLoading: isLoading,
                    isPurging: purgingCache == .fullSizeJPGs,
                    isPurgeInProgress: purgingCache != nil,
                    cachePendingPurge: $cachePendingPurge,
                    showPurgeConfirmation: $showPurgeConfirmation,
                )

                Divider()

                DiskCacheRow(
                    kind: .similarityArtifacts,
                    icon: "point.3.connected.trianglepath.dotted",
                    size: similarityArtifactSize,
                    detail: "\(similarityArtifactCount) reusable per-file \(similarityArtifactCount == 1 ? "artifact" : "artifacts")",
                    path: similarityArtifactPath,
                    isLoading: isLoading,
                    isPurging: purgingCache == .similarityArtifacts,
                    isPurgeInProgress: purgingCache != nil,
                    cachePendingPurge: $cachePendingPurge,
                    showPurgeConfirmation: $showPurgeConfirmation,
                )

                Divider()

                DiskCacheRow(
                    kind: .burstAnalysis,
                    icon: "square.stack.3d.up",
                    size: burstAnalysisSize,
                    detail: "\(burstAnalysisCount) catalog \(burstAnalysisCount == 1 ? "snapshot" : "snapshots") with burst groups and analysis results",
                    path: burstAnalysisPath,
                    isLoading: isLoading,
                    isPurging: purgingCache == .burstAnalysis,
                    isPurgeInProgress: purgingCache != nil,
                    cachePendingPurge: $cachePendingPurge,
                    showPurgeConfirmation: $showPurgeConfirmation,
                )
            }
        }
    }
}

private struct DiskCacheRow: View {
    let kind: DiskCacheKind
    let icon: String
    let size: String
    let detail: String
    let path: String
    let isLoading: Bool
    let isPurging: Bool
    let isPurgeInProgress: Bool
    @Binding var cachePendingPurge: DiskCacheKind?
    @Binding var showPurgeConfirmation: Bool

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: icon)
                .frame(width: 18)
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 3) {
                HStack {
                    Text(kind.title)
                        .font(.subheadline.weight(.medium))
                    Spacer()
                    if isLoading || isPurging {
                        ProgressView()
                            .controlSize(.small)
                            .fixedSize()
                    } else {
                        Text(size)
                            .font(.subheadline.monospacedDigit().weight(.semibold))
                    }
                }

                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Text(path)
                    .font(.caption2.monospaced())
                    .foregroundStyle(.tertiary)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Button {
                cachePendingPurge = kind
                showPurgeConfirmation = true
            } label: {
                Image(systemName: "trash")
                    .frame(width: 22, height: 22)
                    .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .disabled(isLoading || isPurgeInProgress)
            .help("Clear \(kind.title)")
            .accessibilityLabel("Clear \(kind.title)")
        }
    }
}
