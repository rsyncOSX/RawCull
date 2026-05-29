//
//  ScoringParametersSheetView.swift
//  RawCull
//

import SwiftUI

struct ScoringParametersSheetView: View {
    @Environment(\.dismiss) private var dismiss
    @Binding var config: FocusDetectorConfig
    @Binding var thumbnailMaxPixelSize: Int
    @Binding var scoringQuality: SharpnessScoringQuality
    @Binding var scoringSource: SharpnessScoringSource

    var body: some View {
        VStack(spacing: 0) {
            // Title bar
            HStack {
                Label("Scoring Parameters", systemImage: "slider.horizontal.3")
                    .font(.title3.bold())
                Spacer()
                Button("Reset") {
                    let defaults = FocusDetectorConfig()
                    config = defaults
                    thumbnailMaxPixelSize = 512
                    scoringQuality = .fast
                    scoringSource = .embeddedPreview
                    saveScoringSettings()
                }
                .buttonStyle(.borderless)
                .foregroundStyle(.secondary)
                Button("Done") {
                    saveScoringSettings()
                    dismiss()
                }
                .keyboardShortcut(.return)
                .buttonStyle(.borderedProminent)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 14)

            Divider()

            Form {
                Section("Scoring Resolution") {
                    Picker("Quality", selection: $scoringQuality) {
                        ForEach(SharpnessScoringQuality.allCases) { quality in
                            Text(quality.title).tag(quality)
                        }
                    }
                    .pickerStyle(.inline)
                    .onChange(of: scoringQuality) { _, newValue in
                        if newValue == .highPrecision {
                            thumbnailMaxPixelSize = SharpnessScoringSizeOption.highPrecisionDefaultPixelSize
                        } else if thumbnailMaxPixelSize <= 0 {
                            thumbnailMaxPixelSize = newValue.minimumThumbnailMaxPixelSize
                        }
                    }
                    Text("Fast preserves today's scoring path. Balanced and High Precision decode larger previews and blend a fine-detail pass for better small-subject ranking at higher compute cost.")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    Picker("Thumbnail size", selection: $thumbnailMaxPixelSize) {
                        if scoringQuality == .highPrecision {
                            ForEach(SharpnessScoringSizeOption.allCases) { option in
                                Text(option.title).tag(option.rawValue)
                            }
                        } else {
                            Text("512 px  (fast)").tag(512)
                            Text("768 px").tag(768)
                            Text("1024 px  (accurate)").tag(1024)
                        }
                    }
                    .pickerStyle(.inline)
                    Text("Larger thumbnails give more accurate sharpness scores, especially at high ISO, but scoring takes proportionally longer.")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    Picker("Source", selection: $scoringSource) {
                        ForEach(SharpnessScoringSource.allCases) { source in
                            Text(source.title).tag(source)
                        }
                    }
                    .pickerStyle(.inline)
                    Text(scoringSource.help)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Section("Border") {
                    VStack(alignment: .leading, spacing: 2) {
                        HStack {
                            Text("Border inset")
                                .font(.caption)
                            Spacer()
                            Text("\(Int((config.borderInsetFraction * 100).rounded()))%")
                                .font(.caption.monospacedDigit())
                                .foregroundStyle(.secondary)
                        }
                        Slider(value: $config.borderInsetFraction, in: 0.0 ... 0.10, step: 0.01)
                            .controlSize(.small)
                        Text("Excludes the outer N% of pixels on each edge from scoring, preventing blur-border artifacts from inflating the score")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                Section("Subject Detection") {
                    Toggle("Classify subject during scoring", isOn: $config.enableSubjectClassification)
                    Text("Runs an additional Vision classification pass to label each thumbnail with the detected subject (e.g. \"animal\", \"bird\"). Adds ~10–20% to scoring time. Disable for faster re-scores when the badge label is not needed.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Section("Subject Weighting") {
                    LabeledSlider(
                        label: "Subject weight",
                        value: $config.salientWeight,
                        range: 0.0 ... 1.0,
                        hint: "0 = full-frame score only · 1 = subject region only. Higher values make the score reflect how sharp the subject is rather than the background",
                    )

                    LabeledSlider(
                        label: "Subject size bonus",
                        value: $config.subjectSizeFactor,
                        range: 0.0 ... 3.0,
                        hint: "Gives a proportional score bonus for larger subjects in frame (closer subjects fill more of the frame). 0 = disabled",
                    )
                }
            }
            .formStyle(.grouped)
        }
        .frame(width: 420)
        .fixedSize(horizontal: false, vertical: true)
        .onAppear {
            thumbnailMaxPixelSize = SharpnessScoringSizeOption.normalizedPixelSize(
                thumbnailMaxPixelSize,
                for: scoringQuality,
            )
        }
    }

    private func saveScoringSettings() {
        SettingsViewModel.shared.scoringBorderInsetFraction = config.borderInsetFraction
        SettingsViewModel.shared.scoringEnableSubjectClassification = config.enableSubjectClassification
        SettingsViewModel.shared.scoringSalientWeight = config.salientWeight
        SettingsViewModel.shared.scoringSubjectSizeFactor = config.subjectSizeFactor
        SettingsViewModel.shared.scoringThumbnailMaxPixelSize = SharpnessScoringSizeOption.normalizedPixelSize(
            thumbnailMaxPixelSize,
            for: scoringQuality,
        )
        SettingsViewModel.shared.scoringQuality = scoringQuality
        SettingsViewModel.shared.scoringSource = scoringSource
        Task { await SettingsViewModel.shared.saveSettings() }
    }
}
