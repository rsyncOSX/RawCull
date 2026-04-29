//
//  ThumbnailSizesTab.swift
//  RawCull
//
//  Created by Thomas Evensen on 08/02/2026.
//

import SwiftUI

struct ThumbnailSizesTab: View {
    private var settingsManager: SettingsViewModel {
        SettingsViewModel.shared
    }

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
                            range: 1024 ... 1664,
                            step: 128,
                        )

                        Divider()

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

                                Text("When disabled, extracts the embedded JPG from the RAW file for zoom.")
                                    .font(.system(size: 11, weight: .regular))
                                    .foregroundStyle(.secondary)

                                Text("When enabled, uses the thumbnail as the zoom preview.")
                                    .font(.system(size: 11, weight: .regular))
                                    .foregroundStyle(.secondary)
                            }
                        }

                        // Sharpen Zoom Preview Toggle + Amount slider
                        // Only meaningful when useThumbnailAsZoomPreview is on — the
                        // extracted-JPG path is already at full embedded resolution.
                        VStack(alignment: .leading, spacing: 6) {
                            Label("Sharpen Zoom Preview", systemImage: "wand.and.stars")
                                .font(.system(size: 12, weight: .medium))

                            HStack {
                                ToggleViewDefault(
                                    text: "",
                                    binding: Binding<Bool>(
                                        get: { settingsManager.enableThumbnailSharpening },
                                        set: { newValue in
                                            settingsManager.enableThumbnailSharpening = newValue
                                            Task { await settingsManager.saveSettings() }
                                        },
                                    ),
                                )

                                Text("Renders the zoom preview from demosaiced raw via CIRAWFilter, then applies micro-detail sharpening.")
                                    .font(.system(size: 11, weight: .regular))
                                    .foregroundStyle(.secondary)
                            }

                            SettingsSliderRow(
                                title: "Sharpening Amount",
                                systemImage: "slider.horizontal.3",
                                valueText: String(format: "%.2f", settingsManager.thumbnailSharpenAmount),
                                description: "0–1: subtle. 1–2: pronounced. Operates on demosaiced raw, not the embedded JPEG.",
                                value: Binding<Double>(
                                    get: { Double(settingsManager.thumbnailSharpenAmount) },
                                    set: { settingsManager.thumbnailSharpenAmount = Float($0) },
                                ),
                                range: 0.0 ... 2.0,
                                step: 0.05,
                            )
                            .disabled(!settingsManager.enableThumbnailSharpening)
                        }
                        .disabled(!settingsManager.useThumbnailAsZoomPreview)
                        .opacity(settingsManager.useThumbnailAsZoomPreview ? 1.0 : 0.5)
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
    }
}
