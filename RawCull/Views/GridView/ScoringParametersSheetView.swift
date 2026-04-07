//
//  ScoringParametersSheetView.swift
//  RawCull
//

import SwiftUI

struct ScoringParametersSheetView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(SettingsViewModel.self) private var settingsViewModel
    @Binding var config: FocusDetectorConfig
    @Binding var thumbnailMaxPixelSize: Int

    var body: some View {
        VStack(spacing: 0) {
            // Title bar
            HStack {
                Label("Scoring Parameters", systemImage: "slider.horizontal.3")
                    .font(.title3.bold())
                Spacer()
                Button("Reset") { config = FocusDetectorConfig() }
                    .buttonStyle(.borderless)
                    .foregroundStyle(.secondary)
                Button("Done") { dismiss() }
                    .keyboardShortcut(.return)
                    .buttonStyle(.borderedProminent)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 14)

            Divider()

            Form {
                Section("Scoring Resolution") {
                    Picker("Thumbnail size", selection: $thumbnailMaxPixelSize) {
                        Text("512 px  (fast)").tag(512)
                        Text("768 px").tag(768)
                        Text("1024 px  (accurate)").tag(1024)
                    }
                    .pickerStyle(.inline)
                    Text("Larger thumbnails give more accurate sharpness scores, especially at high ISO, but scoring takes proportionally longer")
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

                    let settings = Bindable(settingsViewModel)
                    Toggle("Show saliency label on thumbnails", isOn: settings.showSaliencyBadge)
                        .onChange(of: settingsViewModel.showSaliencyBadge) { _, _ in
                            Task { await SettingsViewModel.shared.saveSettings() }
                        }
                    Text("Displays the detected subject category as a cyan badge on each thumbnail. Hidden by default.")
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
    }
}
