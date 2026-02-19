//
//  CacheSettingsTab.swift
//  RawCull
//
//  Created by Thomas Evensen on 08/02/2026.
//

import OSLog
import SwiftUI

struct CacheSettingsTab: View {
    @Environment(SettingsViewModel.self) var settingsManager

    @State private var showResetConfirmation = false
    @State private var currentDiskCacheSize: Int = 0
    @State private var isLoadingDiskCacheSize = false
    @State private var isPruningDiskCache = false

    @State private var cacheConfig: CacheConfig?

    var body: some View {
        VStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 20) {
                // Memory Cache Section
                VStack(alignment: .leading, spacing: 12) {
                    Text("Memory & Disk Cache")
                        .font(.system(size: 14, weight: .semibold))
                    Divider()
                    // Cache Size
                    VStack(alignment: .leading, spacing: 8) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Adjust memory cache size (3000-20000 MB)")
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
                                    Text("Approx images in Memory Cache " +
                                        displayValue(for: settingsManager.memoryCacheSizeMB))
                                        .font(.system(size: 10, weight: .semibold, design: .rounded))
                                }
                                // slider still uses the real internal values (3000–20000)
                                Slider(
                                    value: Binding<Double>(
                                        get: { Double(settingsManager.memoryCacheSizeMB) },
                                        set: { settingsManager.memoryCacheSizeMB = Int($0) }
                                    ),
                                    in: 3000 ... 20000,
                                    step: 250
                                )
                                .frame(height: 18)
                            }
                        }

                        // Current Disk Cache Size with Prune Button
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

                            ConditionalGlassButton(
                                systemImage: "trash",
                                text: "Prune Disk Cache",
                                helpText: "Prune disk cache to free up space."
                            ) {
                                pruneDiskCache()
                            }
                            .disabled(isPruningDiskCache)
                        }
                        .padding(12)
                        .background(Color(.controlBackgroundColor))
                        .cornerRadius(8)

                        // Cache Limits Summary
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
                        .padding(12)
                        .background(Color(.controlBackgroundColor))
                        .cornerRadius(8)
                    }
                }
                .padding(12)
                .background(Color(.controlBackgroundColor))
                .cornerRadius(8)
            }

            Spacer()

            HStack {
                ConditionalGlassButton(
                    systemImage: "square.and.arrow.down.fill",
                    text: "Save Settings",
                    helpText: "Save settings"
                ) {
                    Task {
                        await settingsManager.saveSettings()
                    }
                }

                // Reset Button
                Button(
                    action: { showResetConfirmation = true },
                    label: {
                        Label("Reset to Defaults", systemImage: "arrow.uturn.backward")
                            .font(.system(size: 12, weight: .medium))
                    }
                )
                .buttonStyle(RefinedGlassButtonStyle())
                .confirmationDialog(
                    "Reset Settings",
                    isPresented: $showResetConfirmation,
                    actions: {
                        Button("Reset", role: .destructive) {
                            Task {
                                await settingsManager.resetToDefaultsMemoryCache()
                            }
                        }
                        Button("Cancel", role: .cancel) {}
                    },
                    message: {
                        Text("Are you sure you want to reset all settings to their default values?")
                    }
                )
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
            .task(id: settingsManager.thumbnailCostPerPixel) {
                await SharedMemoryCache.shared.setCacheCostsFromSavedSettings()
                await SharedMemoryCache.shared.setCostPerPixel(settingsManager.thumbnailCostPerPixel)
                await SharedMemoryCache.shared.refreshConfig()
                cacheConfig = await SharedMemoryCache.shared.getCacheCostsAfterSettingsUpdate()
            }
            .safeAreaInset(edge: .bottom) {
                CacheStatisticsView(requestthumbnail: SharedRequestThumbnail.shared)
                    .padding()
            }
        }
    }

    private func refreshDiskCacheSize() {
        isLoadingDiskCacheSize = true
        Task {
            let size = await SharedRequestThumbnail.shared.getDiskCacheSize()
            await MainActor.run {
                currentDiskCacheSize = size
                isLoadingDiskCacheSize = false
            }
        }
    }

    private func pruneDiskCache() {
        isPruningDiskCache = true
        Task {
            await SharedRequestThumbnail.shared.pruneDiskCache(maxAgeInDays: 0)
            // Refresh the size after pruning
            let size = await SharedRequestThumbnail.shared.getDiskCacheSize()
            await MainActor.run {
                currentDiskCacheSize = size
                isPruningDiskCache = false
            }
        }
    }

    private func formatBytes(_ bytes: Int) -> String {
        if bytes == 0 { return "0 B" }
        let units = ["B", "KB", "MB", "GB"]
        let unitIndex = Int(log2(Double(bytes)) / 10)
        let size = Double(bytes) / pow(1024, Double(unitIndex))
        return String(format: "%.1f %@", size, units[min(unitIndex, units.count - 1)])
    }

    func formatted_memory_GiB() -> String {
        let availableMemory = ProcessInfo.processInfo.physicalMemory
        return NumberFormatter.localizedString(
            from: NSNumber(value: availableMemory / 1_073_741_824),
            number: NumberFormatter.Style.decimal
        )
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
            Logger.process.debugMessageOnly("Image capacity: ~\(imageCapacity) images, \(settingsManager.memoryCacheSizeMB) MB, \(thumbnailSize)×\(thumbnailSize) size, \(costPerImage) bytes/image")
            return String(imageCapacity)
        }

        return "0"
    }
}
