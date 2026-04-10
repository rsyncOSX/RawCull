//
//  ThumbnailSizesTab.swift
//  RawCull
//
//  Created by Thomas Evensen on 08/02/2026.
//

import SwiftUI

struct ThumbnailSizesTab: View {
    private var settingsManager: SettingsViewModel { SettingsViewModel.shared }
    @State private var showResetConfirmation = false
    @State private var showSaveSettingsConfirmation = false

    var body: some View {
        VStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 20) {
                // Thumbnail Settings Section
                SettingsCard {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Thumbnail Sizes")
                            .font(.system(size: 14, weight: .semibold))

                        Divider()

                        // Grid Size
                        SettingsSliderRow(
                            title: "Thumbnail Size Vertical/Horizontal Table View",
                            systemImage: "arrow.left.and.right.text.vertical",
                            valueText: "\(settingsManager.thumbnailSizeGrid) px",
                            description: "Thumbnail size in the main file list",
                            value: Binding<Double>(
                                get: { Double(settingsManager.thumbnailSizeGrid) },
                                set: { settingsManager.thumbnailSizeGrid = Int($0) },
                            ),
                            range: 100 ... 300,
                            step: 10,
                        )

                        SettingsSliderRow(
                            title: "Thumbnail Size Grid View",
                            systemImage: "square.grid.2x2",
                            valueText: "\(settingsManager.thumbnailSizeGridView) px",
                            description: "Thumbnail size in the grid window",
                            value: Binding<Double>(
                                get: { Double(settingsManager.thumbnailSizeGridView) },
                                set: { settingsManager.thumbnailSizeGridView = Int($0) },
                            ),
                            range: 200 ... 500,
                            step: 50,
                        )

                        // Preview Size
                        SettingsSliderRow(
                            title: "Preview Thumbnail Size",
                            systemImage: "photo",
                            valueText: "\(settingsManager.thumbnailSizePreview) px",
                            description: "Size for preview view thumbnails",
                            value: Binding<Double>(
                                get: { Double(settingsManager.thumbnailSizePreview) },
                                set: { settingsManager.thumbnailSizePreview = Int($0) },
                            ),
                            range: 1024 ... 2048,
                            step: 128,
                        )

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
                                    },
                                ),
                                in: 4 ... 8,
                                step: 1,
                            )
                            HStack(spacing: 8) {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("Lower values use less memory, at the cost of quality.")
                                        .font(.system(size: 11, weight: .regular))
                                        .foregroundStyle(.secondary)
                                    Text("Higher values improve quality but use more memory.")
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
                                        },
                                    ),
                                )

                                Text("When disabled, extracts the JPG from ARW file for zoom.")
                                    .font(.system(size: 11, weight: .regular))
                                    .foregroundStyle(.secondary)

                                Text("When enabled, uses the thumbnail as the zoom preview.")
                                    .font(.system(size: 11, weight: .regular))
                                    .foregroundStyle(.secondary)
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
                    onReset: { Task { await settingsManager.resetToDefaultsThumbnails() } },
                    onSave: { Task { await settingsManager.saveSettings() } },
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
