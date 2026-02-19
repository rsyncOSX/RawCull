//
//  ThumbnailSizesTab.swift
//  RawCull
//
//  Created by Thomas Evensen on 08/02/2026.
//

import SwiftUI

struct ThumbnailSizesTab: View {
    @Environment(SettingsViewModel.self) var settingsManager
    @State private var showResetConfirmation = false

    var body: some View {
        VStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 20) {
                // Thumbnail Settings Section
                VStack(alignment: .leading, spacing: 12) {
                    Text("Thumbnail Sizes")
                        .font(.system(size: 14, weight: .semibold))

                    Divider()

                    // Grid Size
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Label("Grid Thumbnail Size", systemImage: "square.grid.2x2")
                                .font(.system(size: 12, weight: .medium))
                            Spacer()
                            Text("\(settingsManager.thumbnailSizeGrid) px")
                                .font(.system(size: 12, weight: .semibold, design: .rounded))
                        }
                        Slider(
                            value: Binding<Double>(
                                get: { Double(settingsManager.thumbnailSizeGrid) },
                                set: { settingsManager.thumbnailSizeGrid = Int($0) }
                            ),
                            in: 50 ... 200,
                            step: 10
                        )
                        Text("Size for grid view thumbnails in Main View")
                            .font(.system(size: 11, weight: .regular))
                            .foregroundStyle(.secondary)
                    }

                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Label("Grid View Thumbnail Size", systemImage: "square.grid.2x2")
                                .font(.system(size: 12, weight: .medium))
                            Spacer()
                            Text("\(settingsManager.thumbnailSizeGridView) px")
                                .font(.system(size: 12, weight: .semibold, design: .rounded))
                        }
                        Slider(
                            value: Binding<Double>(
                                get: { Double(settingsManager.thumbnailSizeGridView) },
                                set: { settingsManager.thumbnailSizeGridView = Int($0) }
                            ),
                            in: 200 ... 500,
                            step: 50
                        )
                        Text("Size for view thumbnails in Grid View")
                            .font(.system(size: 11, weight: .regular))
                            .foregroundStyle(.secondary)
                    }

                    // Preview Size
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Label("Preview Thumbnail Size", systemImage: "photo")
                                .font(.system(size: 12, weight: .medium))
                            Spacer()
                            Text("\(settingsManager.thumbnailSizePreview) px")
                                .font(.system(size: 12, weight: .semibold, design: .rounded))
                        }
                        Slider(
                            value: Binding<Double>(
                                get: { Double(settingsManager.thumbnailSizePreview) },
                                set: { settingsManager.thumbnailSizePreview = Int($0) }
                            ),
                            in: 256 ... 2048,
                            step: 128
                        )
                        Text("Size for preview view thumbnails")
                            .font(.system(size: 11, weight: .regular))
                            .foregroundStyle(.secondary)
                    }

                    // Cost Per Pixel
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Label("Quality/Memory Trade-off", systemImage: "function")
                                .font(.system(size: 12, weight: .medium))
                            Spacer()
                            Text("\(settingsManager.thumbnailCostPerPixel) bytes")
                                .font(.system(size: 12, weight: .semibold, design: .rounded))
                        }
                        Slider(
                            value: Binding<Double>(
                                get: { Double(settingsManager.thumbnailCostPerPixel) },
                                set: { newValue in
                                    let intValue = Int(newValue)
                                    settingsManager.thumbnailCostPerPixel = intValue
                                    Task {
                                        await SharedMemoryCache.shared.setCostPerPixel(intValue)
                                    }
                                }
                            ),
                            in: 1 ... 8,
                            step: 1
                        )
                        HStack(spacing: 8) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Lower values = lower quality/less memory.")
                                    .font(.system(size: 11, weight: .regular))
                                    .foregroundStyle(.secondary)
                                Text("Higher values = better quality/more memory")
                                    .font(.system(size: 11, weight: .regular))
                                    .foregroundStyle(.secondary)
                            }

                            // Calculate estimated costs
                            let gridCost = (settingsManager.thumbnailSizeGrid *
                                settingsManager.thumbnailSizeGrid *
                                settingsManager.thumbnailCostPerPixel) / 1024
                            let previewCost = (settingsManager.thumbnailSizePreview *
                                settingsManager.thumbnailSizePreview *
                                settingsManager.thumbnailCostPerPixel) / 1024
                            let fullCost = (settingsManager.thumbnailSizeFullSize *
                                settingsManager.thumbnailSizeFullSize *
                                settingsManager.thumbnailCostPerPixel) / 1024

                            VStack(alignment: .leading, spacing: 2) {
                                Text("Est. Grid: \(gridCost) KB")
                                    .font(.system(size: 10, weight: .regular))
                                    .foregroundStyle(.secondary)
                                Text("Est. Preview: \(previewCost) KB (\(previewCost / 1024) MB)")
                                    .font(.system(size: 10, weight: .regular))
                                    .foregroundStyle(.secondary)
                                Text("Est. Full: \(fullCost) KB (\(fullCost / 1024) MB)")
                                    .font(.system(size: 10, weight: .regular))
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }

                    // Use Thumbnail as Zoom Preview Toggle
                    VStack(alignment: .leading, spacing: 6) {
                        Label("Use Thumbnail for Zoom", systemImage: "magnifyingglass")
                            .font(.system(size: 12, weight: .medium))

                        HStack {
                            ToggleViewDefault(
                                text: "",
                                binding: Binding<Bool>(
                                    get: { settingsManager.useThumbnailAsZoomPreview },
                                    set: { newValue in
                                        settingsManager.useThumbnailAsZoomPreview = newValue
                                        Task { await settingsManager.saveSettings() }
                                    }
                                )
                            )

                            Text("When enabled, uses the thumbnail as the zoom preview. When disabled, extracts the JPG from ARW file for zoom.")
                                .font(.system(size: 11, weight: .regular))
                                .foregroundStyle(.secondary)
                        }
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
                        await SharedMemoryCache.shared.refreshConfig()
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
                                await settingsManager.resetToDefaultsThumbnails()
                            }
                        }
                        Button("Cancel", role: .cancel) {}
                    },
                    message: {
                        Text("Are you sure you want to reset all settings to their default values?")
                    }
                )
            }
        }
        .onAppear {
            // Initialize ThumbnailProvider with saved cost per pixel setting
            Task {
                await SharedMemoryCache.shared.setCostPerPixel(settingsManager.thumbnailCostPerPixel)
            }
        }
    }
}
