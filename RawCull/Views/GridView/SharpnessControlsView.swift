//
//  SharpnessControlsView.swift
//  RawCull
//
//  Created by Thomas Evensen on 10/04/2026.
//

import SwiftUI

enum SharpnessIntentControlsStyle {
    case inline
    case compactInfo
}

struct SharpnessIntentControlsView: View {
    @Bindable var viewModel: RawCullViewModel
    var isDisabled: Bool
    var showsParametersButton: Bool = false
    var style: SharpnessIntentControlsStyle = .inline

    var body: some View {
        if style == .compactInfo {
            HStack(spacing: 6) {
                Label("Scoring settings are in Scoring Parameters.", systemImage: "info.circle")
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .help("Photo type, quality, and thumbnail size are configured in Scoring Parameters")
            }
            .font(.caption)
            .disabled(isDisabled)
        } else {
            HStack(spacing: 6) {
                Picker("Type", selection: $viewModel.sharpnessModel.photoType) {
                    ForEach(SharpnessPhotoType.allCases) { type in
                        Text(type.title).tag(type)
                    }
                }
                .pickerStyle(.menu)
                .font(.caption)
                .frame(width: 130)
                .help("Tune sharpness scoring for the kind of photos in this catalog")
                .onChange(of: viewModel.sharpnessModel.photoType) { _, newValue in
                    SettingsViewModel.shared.scoringPhotoType = newValue
                    Task(priority: .background) {
                        await SettingsViewModel.shared.saveSettings()
                    }
                }

                Picker("Quality", selection: $viewModel.sharpnessModel.scoringQuality) {
                    ForEach(SharpnessScoringQuality.allCases) { quality in
                        Text(quality.title).tag(quality)
                    }
                }
                .pickerStyle(.menu)
                .font(.caption)
                .frame(width: 122)
                .help("Choose the sharpness scoring speed/precision trade-off")
                .onChange(of: viewModel.sharpnessModel.scoringQuality) { _, newValue in
                    if newValue == .highPrecision {
                        viewModel.sharpnessModel.thumbnailMaxPixelSize = SharpnessScoringSizeOption.highPrecisionDefaultPixelSize
                        SettingsViewModel.shared.scoringThumbnailMaxPixelSize = SharpnessScoringSizeOption.highPrecisionDefaultPixelSize
                    } else if viewModel.sharpnessModel.thumbnailMaxPixelSize <= 0 {
                        viewModel.sharpnessModel.thumbnailMaxPixelSize = newValue.minimumThumbnailMaxPixelSize
                        SettingsViewModel.shared.scoringThumbnailMaxPixelSize = newValue.minimumThumbnailMaxPixelSize
                    }
                    SettingsViewModel.shared.scoringQuality = newValue
                    Task(priority: .background) {
                        await SettingsViewModel.shared.saveSettings()
                    }
                }

                Picker("Source", selection: $viewModel.sharpnessModel.scoringSource) {
                    ForEach(SharpnessScoringSource.allCases) { source in
                        Text(source.title).tag(source)
                    }
                }
                .pickerStyle(.menu)
                .font(.caption)
                .frame(width: 150)
                .help(viewModel.sharpnessModel.scoringSource.help)
                .onChange(of: viewModel.sharpnessModel.scoringSource) { _, newValue in
                    SettingsViewModel.shared.scoringSource = newValue
                    Task(priority: .background) {
                        await SettingsViewModel.shared.saveSettings()
                    }
                }

                if viewModel.sharpnessModel.scoringQuality == .highPrecision {
                    Picker("Size", selection: $viewModel.sharpnessModel.thumbnailMaxPixelSize) {
                        ForEach(SharpnessScoringSizeOption.allCases) { option in
                            Text(option.title).tag(option.rawValue)
                        }
                    }
                    .pickerStyle(.menu)
                    .font(.caption)
                    .frame(width: 92)
                    .help("High Precision scoring size")
                    .onChange(of: viewModel.sharpnessModel.thumbnailMaxPixelSize) { _, newValue in
                        SettingsViewModel.shared.scoringThumbnailMaxPixelSize = newValue
                        Task(priority: .background) {
                            await SettingsViewModel.shared.saveSettings()
                        }
                    }
                }
            }
            .disabled(isDisabled)
        }

        if showsParametersButton {
            Button {
                viewModel.activeSheet = .scoringParams
            } label: {
                Label("Scoring Parameters", systemImage: "slider.horizontal.3")
            }
            .font(.caption)
            .disabled(isDisabled)
            .help("Configure sharpness scoring parameters")
        }
    }
}

struct SharpnessControlsView: View {
    @Bindable var viewModel: RawCullViewModel

    var body: some View {
        SharpnessIntentControlsView(
            viewModel: viewModel,
            isDisabled: viewModel.sharpnessModel.isScoring,
            // showsScoringBadgeToggle: true,
            showsParametersButton: true,
            style: .compactInfo,
        )

        // Score button — calibrates from the burst then scores
        Button {
            Task { await viewModel.calibrateAndScoreCurrentCatalog() }
        } label: {
            if viewModel.sharpnessModel.isScoring {
                Label("Scoring…", systemImage: "scope")
            } else if viewModel.sharpnessModel.scores.isEmpty {
                Label("Score Sharpness", systemImage: "scope")
            } else {
                Label("Re-score", systemImage: "scope")
            }
        }
        .font(.caption)
        .disabled(viewModel.sharpnessModel.isScoring || viewModel.files.isEmpty)
        .help("Calibrate the visual edge threshold from this catalog, then score sharpness")

        // Cancel button — only visible while scoring
        if viewModel.sharpnessModel.isScoring {
            Button(role: .cancel) {
                viewModel.sharpnessModel.cancelScoring()
            } label: {
                Label("Cancel", systemImage: "xmark.circle")
            }
            .font(.caption)
            .tint(.red)
            .help("Abort sharpness scoring and discard results")
            .transition(.opacity.combined(with: .scale(scale: 0.9)))
        }

        // Sort toggle — only visible once scores exist and not currently scoring
        if !viewModel.sharpnessModel.scores.isEmpty, !viewModel.sharpnessModel.isScoring {
            Toggle(isOn: $viewModel.sharpnessModel.sortBySharpness) {
                Label("Sharpness", systemImage: "arrow.up.arrow.down")
            }
            .toggleStyle(.button)
            .font(.caption)
            .help("Sort thumbnails sharpest-first")
            .onChange(of: viewModel.sharpnessModel.sortBySharpness) { _, _ in
                Task(priority: .background) {
                    await viewModel.handleSortOrderChange()
                }
            }
        }

        // Spinner shown while calibrating is in progress
        if viewModel.sharpnessModel.isCalibratingSharpnessScoring {
            HStack {
                ProgressView()
                Text("Calibrating focus-mask threshold, please wait...")
            }
        }
    }
}
