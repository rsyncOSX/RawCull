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

    @State private var showResetConfirmation = false
    @State private var showPruneConfirmation = false
    @State private var showSaveSettingsConfirmation = false
    @State private var currentDiskCacheSize: Int = 0
    @State private var currentGridCacheSize: Int = 0
    @State private var currentGridCacheCount: Int = 0
    @State private var isLoadingDiskCacheSize = false
    @State private var isPruningDiskCache = false

    @State private var cacheConfig: CacheConfig?

    var body: some View {
        VStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 20) {
                // Memory Cache Section
                SettingsCard {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Memory & Disk Cache")
                            .font(.system(size: 14, weight: .semibold))
                        Divider()
                        // Cache Size
                        VStack(alignment: .leading, spacing: 8) {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Adjust memory cache")
                                    .font(.system(size: 10, weight: .regular))
                                    .foregroundStyle(.secondary)
                            }

                            HStack(spacing: 16) {
                                // Cache Size
                                VStack(alignment: .leading, spacing: 4) {
                                    HStack(spacing: 4) {
                                        Image(systemName: "memorychip")
                                            .font(.system(size: 10, weight: .medium))
                                        Text("Memory")
                                            .font(.system(size: 10, weight: .medium))
                                        Spacer()
                                        // Only the label uses the converted display value
                                        Text("Approx images in memory cache: " +
                                            displayValue(for: settingsManager.memoryCacheSizeMB))
                                            .font(.system(size: 10, weight: .semibold, design: .rounded))
                                    }
                                    // slider still uses the real internal values (3000–20000)
                                    Slider(
                                        value: Binding<Double>(
                                            get: { Double(settingsManager.memoryCacheSizeMB) },
                                            set: { settingsManager.memoryCacheSizeMB = Int($0) },
                                        ),
                                        in: 5000 ... 20000,
                                        step: 250,
                                    )
                                    .frame(height: 18)
                                }
                            }

                            HStack(spacing: 16) {
                                // Grid Cache Size (200px thumbnails)
                                VStack(alignment: .leading, spacing: 4) {
                                    HStack(spacing: 4) {
                                        Image(systemName: "square.grid.2x2")
                                            .font(.system(size: 10, weight: .medium))
                                        Text("Grid cache (200px)")
                                            .font(.system(size: 10, weight: .medium))
                                        Spacer()
                                        Text("Max capacity: ~" +
                                            gridDisplayValue(for: settingsManager.gridCacheSizeMB))
                                            .font(.system(size: 10, weight: .semibold, design: .rounded))
                                    }
                                    Slider(
                                        value: Binding<Double>(
                                            get: { Double(settingsManager.gridCacheSizeMB) },
                                            set: { settingsManager.gridCacheSizeMB = Int($0) },
                                        ),
                                        in: 400 ... 2000,
                                        step: 50,
                                    )
                                    .frame(height: 18)
                                }
                            }

                            // Current Disk Cache Size
                            SettingsCard {
                                VStack(alignment: .leading, spacing: 8) {
                                    HStack(spacing: 8) {
                                        HStack(spacing: 4) {
                                            Image(systemName: "internaldrive")
                                                .font(.system(size: 12, weight: .medium))
                                            Text("Current use: ")
                                                .font(.system(size: 12, weight: .medium))

                                            if isLoadingDiskCacheSize {
                                                ProgressView()
                                                    .fixedSize()
                                            } else {
                                                Text(formatBytes(currentDiskCacheSize))
                                                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                                            }
                                        }

                                        Spacer()
                                    }

                                    HStack(spacing: 8) {
                                        HStack(spacing: 4) {
                                            Image(systemName: "memorychip")
                                                .font(.system(size: 12, weight: .medium))
                                            Text("Grid cache (200px): ")
                                                .font(.system(size: 12, weight: .medium))
                                            Text(formatBytes(currentGridCacheSize))
                                                .font(.system(size: 12, weight: .semibold, design: .rounded))
                                            Text("/ \(formatBytes(SharedMemoryCache.shared.gridThumbnailCache.totalCostLimit))")
                                                .font(.system(size: 12, weight: .regular))
                                                .foregroundStyle(.secondary)
                                            Text("· \(currentGridCacheCount) thumbnails")
                                                .font(.system(size: 12, weight: .regular))
                                                .foregroundStyle(.secondary)
                                        }

                                        Spacer()
                                    }
                                }
                            }

                            // Cache Limits Summary
                            SettingsCard {
                                VStack(alignment: .leading, spacing: 8) {
                                    Text("Cache Limits")
                                        .font(.system(size: 12, weight: .semibold))

                                    Divider()

                                    HStack(spacing: 16) {
                                        VStack(alignment: .leading, spacing: 4) {
                                            Text("Total Cost Limit")
                                                .font(.system(size: 10, weight: .medium))
                                                .foregroundStyle(.secondary)
                                            Text(formatBytes(cacheConfig?.totalCostLimit ?? 0))
                                                .font(.system(size: 11, weight: .semibold, design: .rounded))
                                        }

                                        Divider()

                                        VStack(alignment: .leading, spacing: 4) {
                                            Text("Count Limit")
                                                .font(.system(size: 10, weight: .medium))
                                                .foregroundStyle(.secondary)
                                            if let countLimit = cacheConfig?.countLimit {
                                                Text("\(String(countLimit))")
                                                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                                            }
                                        }

                                        Divider()

                                        VStack(alignment: .leading, spacing: 4) {
                                            Text("Cost Per Pixel")
                                                .font(.system(size: 10, weight: .medium))
                                                .foregroundStyle(.secondary)
                                            if let costPerPixel = cacheConfig?.costPerPixel {
                                                Text("\(String(costPerPixel)) bytes")
                                                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }

            Spacer()

            HStack {
                SettingsResetSaveButtons(
                    showResetConfirmation: $showResetConfirmation,
                    showSaveConfirmation: $showSaveSettingsConfirmation,
                    resetMessage: "Are you sure you want to reset all settings to their default values?",
                    saveMessage: "Save Settings to disk?",
                    onReset: { Task { await settingsManager.resetToDefaultsMemoryCache() } },
                    onSave: { Task { await settingsManager.saveSettings() } },
                ) {
                    // Prune Disk Cache Button
                    Button(
                        action: { showPruneConfirmation = true },
                        label: {
                            Label("Prune Disk Cache", systemImage: "trash")
                                .font(.system(size: 12, weight: .medium))
                        },
                    )
                    .buttonStyle(RefinedGlassButtonStyle())
                    .confirmationDialog(
                        "Prune Disk Cache",
                        isPresented: $showPruneConfirmation,
                        actions: {
                            Button("Prune", role: .destructive) {
                                pruneDiskCache()
                            }
                            Button("Cancel", role: .cancel) {}
                        },
                        message: {
                            Text("Are you sure you want to prune the disk cache?")
                        },
                    )
                }
            }
            .onAppear(perform: refreshDiskCacheSize)
            .task {
                // Initialize ThumbnailProvider with saved cost per pixel setting
                // The ThumbnailProvider.init get the saved settings an update cost by
                // setCacheCostsFromSavedSettings()
                await SharedMemoryCache.shared.setCostPerPixel(settingsManager.thumbnailCostPerPixel)
                await SharedMemoryCache.shared.refreshConfig()
                cacheConfig = await SharedMemoryCache.shared.getCacheCostsAfterSettingsUpdate()
            }
            .task(id: settingsManager.memoryCacheSizeMB) {
                await SharedMemoryCache.shared.setCacheCostsFromSavedSettings()
                await SharedMemoryCache.shared.refreshConfig()
                cacheConfig = await SharedMemoryCache.shared.getCacheCostsAfterSettingsUpdate()
                // await updateImageCapacity()
            }
            .task(id: settingsManager.gridCacheSizeMB) {
                await SharedMemoryCache.shared.refreshConfig()
                cacheConfig = await SharedMemoryCache.shared.getCacheCostsAfterSettingsUpdate()
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
                }
            }
            .task(id: settingsManager.thumbnailCostPerPixel) {
                await SharedMemoryCache.shared.setCacheCostsFromSavedSettings()
                await SharedMemoryCache.shared.setCostPerPixel(settingsManager.thumbnailCostPerPixel)
                await SharedMemoryCache.shared.refreshConfig()
                cacheConfig = await SharedMemoryCache.shared.getCacheCostsAfterSettingsUpdate()
            }
            .safeAreaInset(edge: .bottom) {
                CacheStatisticsView()
                    .padding()
            }
        }
    }

    private func refreshDiskCacheSize() {
        isLoadingDiskCacheSize = true
        Task {
            let diskSize = await SharedMemoryCache.shared.getDiskCacheSize()
            let gridSize = SharedMemoryCache.shared.getGridCacheCurrentCost()
            let gridCount = SharedMemoryCache.shared.getGridCacheCount()
            await MainActor.run {
                currentDiskCacheSize = diskSize
                currentGridCacheSize = gridSize
                currentGridCacheCount = gridCount
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

    private func formatBytes(_ bytes: Int) -> String {
        if bytes == 0 { return "0 B" }
        return ByteCountFormatStyle(style: .memory).format(Int64(bytes))
    }

    private func gridDisplayValue(for megabytes: Int) -> String {
        let bytes = megabytes * 1024 * 1024

        if currentGridCacheCount > 0, currentGridCacheSize > 0 {
            let avgCost = currentGridCacheSize / currentGridCacheCount
            if avgCost > 0 { return String(max(1, bytes / avgCost)) }
        }

        let s = settingsManager.thumbnailSizeGrid * 2
        let raw = s * s * settingsManager.thumbnailCostPerPixel
        let costPerImage = Int(Double(raw) * 1.1)
        guard costPerImage > 0 else { return "0" }
        return String(max(1, bytes / costPerImage))
    }

    private func displayValue(for megabytes: Int) -> String {
        // Convert MB to bytes
        let bytes = megabytes * 1024 * 1024

        // Calculate actual image capacity based on bytes and cost per image
        // Cost per image = thumbnail_size × thumbnail_size × costPerPixel
        // Use the preview size setting (user-configurable)
        let thumbnailSize = settingsManager.thumbnailSizePreview
        let costPerPixel = settingsManager.thumbnailCostPerPixel
        let costPerImage = thumbnailSize * thumbnailSize * costPerPixel

        if costPerImage > 0 {
            let calculatedCapacity = bytes / costPerImage
            let imageCapacity = max(1, Int(calculatedCapacity))
            Logger.process.debugMessageOnly(
                "Image capacity: ~\(imageCapacity) images, " +
                    "\(settingsManager.memoryCacheSizeMB) MB, " +
                    "\(thumbnailSize)×\(thumbnailSize) size, " +
                    "\(costPerImage) bytes/image",
            )
            return String(imageCapacity)
        }

        return "0"
    }
}
