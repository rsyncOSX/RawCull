import SwiftUI

struct FocusSettingsTab: View {
    @Environment(RawCullViewModel.self) private var viewModel

    private var settingsManager: SettingsViewModel {
        SettingsViewModel.shared
    }

    @State private var showResetConfirmation = false
    @State private var showSaveConfirmation = false

    var body: some View {
        @Bindable var vm = viewModel
        VStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 16) {
                // Focus Mask Section
                SettingsCard {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Focus Mask")
                            .font(.system(size: 14, weight: .semibold))
                        Divider()

                        LabeledSlider(
                            label: "Threshold",
                            value: $vm.sharpnessModel.focusMaskModel.config.threshold,
                            range: 0.01 ... 0.70,
                            hint: "Lower = more highlighted, Higher = only sharpest edges",
                        )

                        LabeledSlider(
                            label: "Pre-blur",
                            value: $vm.sharpnessModel.focusMaskModel.config.preBlurRadius,
                            range: 0.3 ... 4.0,
                            hint: "Higher = ignore more background texture",
                        )

                        LabeledSlider(
                            label: "Amplify",
                            value: $vm.sharpnessModel.focusMaskModel.config.energyMultiplier,
                            range: 1.0 ... 20.0,
                            hint: "Amplification of sharpness signal before threshold",
                        )

                        LabeledSlider(
                            label: "Erosion",
                            value: $vm.sharpnessModel.focusMaskModel.config.erosionRadius,
                            range: 0.0 ... 2.0,
                            hint: "Higher = removes more isolated noise pixels",
                        )

                        LabeledSlider(
                            label: "Dilation",
                            value: $vm.sharpnessModel.focusMaskModel.config.dilationRadius,
                            range: 0.0 ... 3.0,
                            hint: "Higher = expands and connects nearby mask regions",
                        )
                    }
                }

                // Focus Points Section
                SettingsCard {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Focus Points")
                            .font(.system(size: 14, weight: .semibold))
                        Divider()

                        VStack(alignment: .leading, spacing: 2) {
                            HStack {
                                Text("Marker Size")
                                    .font(.caption)
                                Spacer()
                                Text(vm.focusPointMarkerSize, format: .number.precision(.fractionLength(0)))
                                    .font(.caption.monospacedDigit())
                                    .foregroundStyle(.secondary)
                            }
                            Slider(value: $vm.focusPointMarkerSize, in: 32 ... 100, step: 4)
                                .controlSize(.small)
                            Text("Size of focus point markers in the overlay")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }

            Spacer()

            HStack {
                SettingsResetSaveButtons(
                    showResetConfirmation: $showResetConfirmation,
                    showSaveConfirmation: $showSaveConfirmation,
                    resetMessage: "Reset focus mask and focus point settings to defaults?",
                    saveMessage: "Save focus settings to disk?",
                    onReset: { resetToDefaults() },
                    onSave: { Task { await saveSettings() } },
                )
            }
        }
    }

    private func resetToDefaults() {
        let d = FocusDetectorConfig()
        viewModel.sharpnessModel.focusMaskModel.config.preBlurRadius = d.preBlurRadius
        viewModel.sharpnessModel.focusMaskModel.config.threshold = d.threshold
        viewModel.sharpnessModel.focusMaskModel.config.energyMultiplier = d.energyMultiplier
        viewModel.sharpnessModel.focusMaskModel.config.erosionRadius = d.erosionRadius
        viewModel.sharpnessModel.focusMaskModel.config.dilationRadius = d.dilationRadius
        viewModel.sharpnessModel.focusMaskModel.config.featherRadius = d.featherRadius
        viewModel.focusPointMarkerSize = 40
        Task { await saveSettings() }
    }

    private func saveSettings() async {
        let config = viewModel.sharpnessModel.focusMaskModel.config
        settingsManager.focusMaskPreBlurRadius = config.preBlurRadius
        settingsManager.focusMaskThreshold = config.threshold
        settingsManager.focusMaskEnergyMultiplier = config.energyMultiplier
        settingsManager.focusMaskErosionRadius = config.erosionRadius
        settingsManager.focusMaskDilationRadius = config.dilationRadius
        settingsManager.focusMaskFeatherRadius = config.featherRadius
        await settingsManager.saveSettings()
    }
}
