//
//  CacheSettingsTab.swift
//  RawCull
//
//  Created by Thomas Evensen on 08/02/2026.
//

import OSLog
import SwiftUI

struct CacheSettingsTab: View {
    private var settingsManager: SettingsViewModel {
        SettingsViewModel.shared
    }

    @State private var showPruneConfirmation = false
    @State private var showPruneJPGConfirmation = false
    @State private var currentDiskCacheSize: Int = 0
    @State private var currentFullSizeJPGCacheSize: Int = 0
    @State private var currentGridCacheSize: Int = 0
    @State private var currentGridCacheCount: Int = 0
    @State private var currentMemCacheSize: Int = 0
    @State private var currentMemCacheCount: Int = 0
    @State private var isLoadingDiskCacheSize = false
    @State private var isPruningDiskCache = false
    @State private var isPruningJPGCache = false

    @State private var memoryModel = MemoryViewModel()

    var body: some View {
        VStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 20) {
                // Memory Cache Section
                SettingsCard {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Memory & Disk Cache")
                            .font(.system(size: 14, weight: .semibold))
                        Divider()

                        VStack(alignment: .leading, spacing: 8) {
                            limitRow(
                                icon: "memorychip",
                                title: "Memory cache",
                                value: "\(formatMegabytes(settingsManager.memoryCacheSizeMB)) max",
                                detail: "Approx \(displayValue(for: settingsManager.memoryCacheSizeMB)) preview images",
                            )

                            limitRow(
                                icon: "square.grid.2x2",
                                title: "Grid cache",
                                value: "\(formatMegabytes(settingsManager.gridCacheSizeMB)) max",
                                detail: "Approx \(gridDisplayValue(for: settingsManager.gridCacheSizeMB)) grid thumbnails",
                            )

                            limitRow(
                                icon: "gauge.with.dots.needle.50percent",
                                title: "Supported limits",
                                value: "\(formatMegabytes(CacheSettingsLimits.memoryMinMB))-\(formatMegabytes(CacheSettingsLimits.memoryMaxMB)) memory, \(formatMegabytes(CacheSettingsLimits.gridMinMB))-\(formatMegabytes(CacheSettingsLimits.gridMaxMB)) grid",
                                detail: "RawCull uses the maximum cache limits by default.",
                            )

                            Divider()

                            cacheUseRows
                        }
                    }
                }
            }

            Spacer()

            HStack {
                clearDiskCacheButton
                clearJPGCacheButton
            }
            .onAppear(perform: refreshDiskCacheSize)
            .task {
                await SharedMemoryCache.shared.refreshConfig()
                currentMemCacheSize = SharedMemoryCache.shared.getMemoryCacheCurrentCost()
                currentMemCacheCount = SharedMemoryCache.shared.getMemoryCacheCount()
                currentGridCacheSize = SharedMemoryCache.shared.getGridCacheCurrentCost()
                currentGridCacheCount = SharedMemoryCache.shared.getGridCacheCount()
            }
            .task {
                let (timerStream, continuation) = AsyncStream.makeStream(of: Void.self)
                let producer = Task {
                    while !Task.isCancelled {
                        continuation.yield()
                        try? await Task.sleep(for: .seconds(5))
                    }
                    continuation.finish()
                }
                continuation.onTermination = { _ in producer.cancel() }
                for await _ in timerStream {
                    currentGridCacheSize = SharedMemoryCache.shared.getGridCacheCurrentCost()
                    currentGridCacheCount = SharedMemoryCache.shared.getGridCacheCount()
                    currentMemCacheSize = SharedMemoryCache.shared.getMemoryCacheCurrentCost()
                    currentMemCacheCount = SharedMemoryCache.shared.getMemoryCacheCount()
                }
            }
            .task {
                let (timerStream, continuation) = AsyncStream.makeStream(of: Void.self)
                let producer = Task {
                    while !Task.isCancelled {
                        continuation.yield()
                        try? await Task.sleep(for: .seconds(2))
                    }
                    continuation.finish()
                }
                continuation.onTermination = { _ in producer.cancel() }
                for await _ in timerStream {
                    await memoryModel.updateMemoryStats()
                }
            }
        }
    }

    private var cacheUseRows: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 4) {
                Image(systemName: "internaldrive")
                    .font(.system(size: 12, weight: .medium))
                Text("Thumbnail disk cache:")
                    .font(.system(size: 12, weight: .medium))
                if isLoadingDiskCacheSize {
                    ProgressView()
                        .fixedSize()
                } else {
                    Text(formatBytes(currentDiskCacheSize))
                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                }
                Spacer()
            }

            cacheUseRow(
                icon: "photo",
                title: "Full-size JPG cache:",
                value: formatBytes(currentFullSizeJPGCacheSize),
            )

            cacheUseRow(
                icon: "square.grid.2x2",
                title: "Grid cache:",
                value: "\(formatBytes(currentGridCacheSize)) / \(formatBytes(SharedMemoryCache.shared.gridThumbnailCache.totalCostLimit)) · \(currentGridCacheCount) thumbnails",
            )

            cacheUseRow(
                icon: "memorychip",
                title: "Memory cache:",
                value: "\(formatBytes(currentMemCacheSize)) / \(formatBytes(SharedMemoryCache.shared.memoryCache.totalCostLimit)) · \(currentMemCacheCount) previews",
            )

            Text("Free memory: \(formatBytes(Int(freeMemoryBytes())))")
                .font(.system(size: 10, weight: .regular))
                .foregroundStyle(.secondary)
        }
    }

    private var clearDiskCacheButton: some View {
        Button(
            action: { showPruneConfirmation = true },
            label: {
                Label(isPruningDiskCache ? "Clearing..." : "Clear Disk Cache", systemImage: "trash")
                    .font(.system(size: 12, weight: .medium))
            },
        )
        .disabled(isPruningDiskCache)
        .buttonStyle(RefinedGlassButtonStyle())
        .confirmationDialog(
            "Clear Disk Cache",
            isPresented: $showPruneConfirmation,
            actions: {
                Button("Clear", role: .destructive) {
                    pruneDiskCache()
                }
                Button("Cancel", role: .cancel) {}
            },
            message: {
                Text("Are you sure you want to clear the thumbnail disk cache?")
            },
        )
    }

    private var clearJPGCacheButton: some View {
        Button(
            action: { showPruneJPGConfirmation = true },
            label: {
                Label(isPruningJPGCache ? "Clearing..." : "Clear JPG Cache", systemImage: "trash")
                    .font(.system(size: 12, weight: .medium))
            },
        )
        .disabled(isPruningJPGCache)
        .buttonStyle(RefinedGlassButtonStyle())
        .confirmationDialog(
            "Clear JPG Cache",
            isPresented: $showPruneJPGConfirmation,
            actions: {
                Button("Clear", role: .destructive) {
                    pruneJPGCache()
                }
                Button("Cancel", role: .cancel) {}
            },
            message: {
                Text("Are you sure you want to clear the full-size JPG cache?")
            },
        )
    }

    private func limitRow(icon: String, title: String, value: String, detail: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.system(size: 10, weight: .medium))
                Text(title)
                    .font(.system(size: 10, weight: .medium))
                Spacer()
                Text(value)
                    .font(.system(size: 10, weight: .semibold, design: .rounded))
            }
            Text(detail)
                .font(.system(size: 10, weight: .regular))
                .foregroundStyle(.secondary)
        }
    }

    private func cacheUseRow(icon: String, title: String, value: String) -> some View {
        HStack(spacing: 4) {
            Image(systemName: icon)
                .font(.system(size: 12, weight: .medium))
            Text(title)
                .font(.system(size: 12, weight: .medium))
            Text(value)
                .font(.system(size: 12, weight: .semibold, design: .rounded))
            Spacer()
        }
    }

    private func refreshDiskCacheSize() {
        isLoadingDiskCacheSize = true
        Task {
            let diskSize = await SharedMemoryCache.shared.getDiskCacheSize()
            let jpgSize = await SharedMemoryCache.shared.getFullSizeJPGCacheSize()
            let gridSize = SharedMemoryCache.shared.getGridCacheCurrentCost()
            let gridCount = SharedMemoryCache.shared.getGridCacheCount()
            let memSize = SharedMemoryCache.shared.getMemoryCacheCurrentCost()
            let memCount = SharedMemoryCache.shared.getMemoryCacheCount()
            await MainActor.run {
                currentDiskCacheSize = diskSize
                currentFullSizeJPGCacheSize = jpgSize
                currentGridCacheSize = gridSize
                currentGridCacheCount = gridCount
                currentMemCacheSize = memSize
                currentMemCacheCount = memCount
                isLoadingDiskCacheSize = false
            }
        }
    }

    private func pruneDiskCache() {
        isPruningDiskCache = true
        Task {
            await SharedMemoryCache.shared.pruneDiskCache(maxAgeInDays: 0)
            // Refresh the size after pruning
            let size = await SharedMemoryCache.shared.getDiskCacheSize()
            await MainActor.run {
                currentDiskCacheSize = size
                isPruningDiskCache = false
            }
        }
    }

    private func pruneJPGCache() {
        isPruningJPGCache = true
        Task {
            await SharedMemoryCache.shared.pruneFullSizeJPGCache(maxAgeInDays: 0)
            let size = await SharedMemoryCache.shared.getFullSizeJPGCacheSize()
            await MainActor.run {
                currentFullSizeJPGCacheSize = size
                isPruningJPGCache = false
            }
        }
    }

    private func formatBytes(_ bytes: Int) -> String {
        if bytes == 0 { return "0 B" }
        return ByteCountFormatStyle(style: .memory).format(Int64(bytes))
    }

    private func formatMegabytes(_ megabytes: Int) -> String {
        formatBytes(megabytes * 1024 * 1024)
    }

    private func gridDisplayValue(for megabytes: Int) -> String {
        let bytes = megabytes * 1024 * 1024

        if currentGridCacheCount > 0, currentGridCacheSize > 0 {
            let avgNSCacheCost = max(1, currentGridCacheSize / currentGridCacheCount)
            return String(max(1, bytes / avgNSCacheCost))
        }

        let s = settingsManager.thumbnailSizeGrid * 2
        let costPerImage = Int(Double(s * s * SharedMemoryCache.shared.costPerPixel) * 1.1)
        guard costPerImage > 0 else { return "0" }
        return String(max(1, bytes / costPerImage))
    }

    private func freeMemoryBytes() -> UInt64 {
        let physical = ProcessInfo.processInfo.physicalMemory
        return memoryModel.usedMemory < physical
            ? physical - memoryModel.usedMemory
            : 0
    }

    private func displayValue(for megabytes: Int) -> String {
        let bytes = megabytes * 1024 * 1024

        if currentMemCacheCount > 0, currentMemCacheSize > 0 {
            let avgNSCacheCost = max(1, currentMemCacheSize / currentMemCacheCount)
            return String(max(1, bytes / avgNSCacheCost))
        }

        let thumbnailSize = settingsManager.thumbnailSizePreview
        let costPerPixel = SharedMemoryCache.shared.costPerPixel
        let costPerImage = thumbnailSize * thumbnailSize * costPerPixel
        guard costPerImage > 0 else { return "0" }
        return String(max(1, bytes / costPerImage))
    }
}
