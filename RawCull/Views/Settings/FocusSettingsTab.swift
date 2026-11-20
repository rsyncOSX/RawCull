import SwiftUI

struct FocusSettingsTab: View {
    @Environment(SharpnessScoringModel.self) private var sharpnessModel

    private var settingsManager: SettingsViewModel {
        SettingsViewModel.shared
    }

    // Periphery 3.8 does not follow projected-value reads from SDK 27's macro-backed @State.
    // periphery:ignore
    @State private var showResetConfirmation = false
    // periphery:ignore
    @State private var showSaveConfirmation = false

    var body: some View {
        @Bindable var vm = sharpnessModel
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
                            value: $vm.focusMaskModel.config.threshold,
                            range: 0.01 ... 0.70,
                            hint: "Lower = more highlighted, Higher = only sharpest edges",
                        )

                        LabeledSlider(
                            label: "Pre-blur",
                            value: $vm.focusMaskModel.config.preBlurRadius,
                            range: 0.3 ... 4.0,
                            hint: "Higher = ignore more background texture",
                        )

                        LabeledSlider(
                            label: "Amplify",
                            value: $vm.focusMaskModel.config.energyMultiplier,
                            range: 1.0 ... 20.0,
                            hint: "Visual-only amplification before the overlay threshold",
                        )

                        LabeledSlider(
                            label: "Erosion",
                            value: $vm.focusMaskModel.config.erosionRadius,
                            range: 0.0 ... 2.0,
                            hint: "Higher = removes more isolated noise pixels",
                        )

                        LabeledSlider(
                            label: "Dilation",
                            value: $vm.focusMaskModel.config.dilationRadius,
                            range: 0.0 ... 3.0,
                            hint: "Higher = expands and connects nearby mask regions",
                        )
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
        sharpnessModel.focusMaskModel.config.preBlurRadius = d.preBlurRadius
        sharpnessModel.focusMaskModel.config.threshold = d.threshold
        sharpnessModel.focusMaskModel.config.energyMultiplier = d.energyMultiplier
        sharpnessModel.focusMaskModel.config.erosionRadius = d.erosionRadius
        sharpnessModel.focusMaskModel.config.dilationRadius = d.dilationRadius
        sharpnessModel.focusMaskModel.config.featherRadius = d.featherRadius
        Task { await saveSettings() }
    }

    private func saveSettings() async {
        let config = sharpnessModel.focusMaskModel.config
        settingsManager.focusMaskPreBlurRadius = config.preBlurRadius
        settingsManager.focusMaskThreshold = config.threshold
        settingsManager.focusMaskEnergyMultiplier = config.energyMultiplier
        settingsManager.focusMaskErosionRadius = config.erosionRadius
        settingsManager.focusMaskDilationRadius = config.dilationRadius
        settingsManager.focusMaskFeatherRadius = config.featherRadius
        await settingsManager.saveSettings()
    }
}
