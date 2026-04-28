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
    @State private var numRawFilesSlider: Double = 2500
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
                                    // slider still uses the real internal values (1000 ... 8000)
                                    Slider(
                                        value: Binding<Double>(
                                            get: { Double(settingsManager.memoryCacheSizeMB) },
                                            set: { settingsManager.memoryCacheSizeMB = Int($0) },
                                        ),
                                        in: 1000 ... 8000,
                                        step: 250,
                                    )
                                    .frame(height: 18)
                                    /*
                                    HStack(spacing: 4) {
                                        Text("Projected RawCull RAM: ~" +
                                            formatBytes(Int(projectedRawCullMemoryBytes())) +
                                            " · Physical: " +
                                            formatBytes(Int(ProcessInfo.processInfo.physicalMemory)))
                                            .font(.system(size: 10, weight: .regular))
                                            .foregroundStyle(isProjectedOverPhysicalRAM() ? .red : .secondary)
                                        Spacer()
                                    }
                                     */
                                    HStack(spacing: 4) {
                                        Text("Free: " +
                                            formatBytes(Int(freeMemoryBytes())))
                                        .font(.system(size: 10, weight: .regular))
                                        .foregroundStyle(.secondary)
                                             /*
                                            " · Budget: " +
                                            formatBytes(Int(freeMemoryBudgetBytes())))
                                            .font(.system(size: 10, weight: .regular))
                                            .foregroundStyle(.secondary)
                                              */
                                        Spacer()
                                    }
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

                            // Estimator — display-only, not persisted
                            SettingsCard {
                                VStack(alignment: .leading, spacing: 8) {
                                    Text("Estimate for RAW files")
                                        .font(.system(size: 12, weight: .semibold))
                                    Divider()
                                    VStack(alignment: .leading, spacing: 4) {
                                        HStack(spacing: 4) {
                                            Image(systemName: "memorychip")
                                                .font(.system(size: 10, weight: .medium))
                                            Text("Memory")
                                                .font(.system(size: 10, weight: .medium))
                                            Spacer()
                                            Text("Approx images in memory cache: \(estimatedMemCacheImages(for: Int(numRawFilesSlider)))")
                                                .font(.system(size: 10, weight: .semibold, design: .rounded))
                                        }
                                        HStack(spacing: 4) {
                                            Image(systemName: "square.grid.2x2")
                                                .font(.system(size: 10, weight: .medium))
                                            Text("Grid cache (200px)")
                                                .font(.system(size: 10, weight: .medium))
                                            Spacer()
                                            Text("Max capacity: ~\(estimatedGridCacheImages(for: Int(numRawFilesSlider)))")
                                                .font(.system(size: 10, weight: .semibold, design: .rounded))
                                        }
                                        Slider(
                                            value: $numRawFilesSlider,
                                            in: 500 ... 5000,
                                            step: 100,
                                        )
                                        .frame(height: 18)
                                        // .tint(isOverFreeMemoryBudget() ? .red : .accentColor)
                                        HStack {
                                            Text("\(Int(numRawFilesSlider)) files")
                                                .font(.system(size: 10, weight: .medium))
                                                .foregroundStyle(.secondary)
                                            Spacer()
                                            /*
                                            if isOverFreeMemoryBudget() {
                                                Label("Exceeds safe memory limit", systemImage: "exclamationmark.triangle")
                                                    .font(.system(size: 10, weight: .medium))
                                                    .foregroundStyle(.red)
                                            }
                                             */
                                        }
                                    }
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
            .task(id: settingsManager.thumbnailCostPerPixel) {
                await SharedMemoryCache.shared.setCacheCostsFromSavedSettings()
                await SharedMemoryCache.shared.setCostPerPixel(settingsManager.thumbnailCostPerPixel)
                await SharedMemoryCache.shared.refreshConfig()
                cacheConfig = await SharedMemoryCache.shared.getCacheCostsAfterSettingsUpdate()
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

        // Use 4 bytes/pixel (real RGBA) to show real-RAM capacity, not NSCache cost capacity.
        // NSCache cost uses thumbnailCostPerPixel (e.g. 6) for conservative eviction; actual
        // CGImage memory is always 4 bytes/pixel RGBA regardless of that setting.
        if currentGridCacheCount > 0, currentGridCacheSize > 0 {
            let avgNSCacheCost = currentGridCacheSize / currentGridCacheCount
            let cacheCostPerPixel = settingsManager.thumbnailCostPerPixel
            let realBytesPerThumb = cacheCostPerPixel > 0
                ? max(1, Int(Double(avgNSCacheCost) * 4.0 / Double(cacheCostPerPixel)))
                : avgNSCacheCost
            return String(max(1, bytes / realBytesPerThumb))
        }

        let s = settingsManager.thumbnailSizeGrid * 2
        let costPerImage = Int(Double(s * s * 4) * 1.1) // 4 bytes/pixel actual RGBA + 10% overhead
        guard costPerImage > 0 else { return "0" }
        return String(max(1, bytes / costPerImage))
    }

    private func estimatedMemCacheImages(for numFiles: Int) -> Int {
        let bytes = settingsManager.memoryCacheSizeMB * 1024 * 1024
        let costPerImage = settingsManager.thumbnailSizePreview
            * settingsManager.thumbnailSizePreview
            * settingsManager.thumbnailCostPerPixel
        guard costPerImage > 0 else { return 0 }
        return min(numFiles, bytes / costPerImage)
    }

    private func estimatedGridCacheImages(for numFiles: Int) -> Int {
        let bytes = settingsManager.gridCacheSizeMB * 1024 * 1024
        let costPerImage: Int
        if currentGridCacheCount > 0, currentGridCacheSize > 0 {
            let avg = currentGridCacheSize / currentGridCacheCount
            costPerImage = avg > 0 ? avg : 1
        } else {
            let s = settingsManager.thumbnailSizeGrid * 2
            costPerImage = Int(Double(s * s * 4) * 1.1)
        }
        guard costPerImage > 0 else { return 0 }
        return min(numFiles, bytes / costPerImage)
    }

/*
    /// Live free-memory budget: the calibrated `projectedRawCullMemoryBytes()`
    /// must fit within `physical × 0.85 − usedByOtherApps − 512 MB safety`.
    /// `projectedRawCullMemoryBytes()` already represents RawCull's *total*
    /// expected RSS (baseline + caches), so we compare it directly against the
    /// budget — adding `appMemory` on top would double-count RawCull.
    /// Uses `MemoryViewModel`'s polled `usedMemory` / `appMemory` so the
    /// threshold reflects what's actually free right now, not a static
    /// fraction of physical RAM.
    private func isOverFreeMemoryBudget() -> Bool {
        let physical = ProcessInfo.processInfo.physicalMemory
        let threshold = UInt64(Double(physical) * 0.85)
        let safetyBuffer: UInt64 = 512 * 1024 * 1024
        let usedByOthers = memoryModel.usedMemory > memoryModel.appMemory
            ? memoryModel.usedMemory - memoryModel.appMemory
            : 0
        guard threshold > usedByOthers + safetyBuffer else { return true }
        let budget = threshold - usedByOthers - safetyBuffer
        return projectedRawCullMemoryBytes() >= budget
    }

    private func freeMemoryBudgetBytes() -> UInt64 {
        let physical = ProcessInfo.processInfo.physicalMemory
        let threshold = UInt64(Double(physical) * 0.85)
        let usedByOthers = memoryModel.usedMemory > memoryModel.appMemory
            ? memoryModel.usedMemory - memoryModel.appMemory
            : 0
        return threshold > usedByOthers ? threshold - usedByOthers : 0
    }
 */
    private func freeMemoryBytes() -> UInt64 {
        let physical = ProcessInfo.processInfo.physicalMemory
        return memoryModel.usedMemory < physical
            ? physical - memoryModel.usedMemory
            : 0
    }

/*
    /// Centralized in `SettingsViewModel.projectedRawCullMemoryBytes()` so the
    /// Memory Diagnostics console logs the same projection this tab displays.
    private func projectedRawCullMemoryBytes() -> UInt64 {
        settingsManager.projectedRawCullMemoryBytes()
    }

    private func isProjectedOverPhysicalRAM() -> Bool {
        isOverFreeMemoryBudget()
    }
 */
    
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
