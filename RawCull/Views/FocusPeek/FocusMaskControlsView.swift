import SwiftUI

struct FocusMaskControlsView: View {
    @Binding var showFocusMask: Bool
    @Binding var config: FocusDetectorConfig
    @Binding var overlayOpacity: Double
    @Binding var controlsCollapsed: Bool
    var focusMaskAvailable: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Expanded slider panel — shown above the capsule row
            if showFocusMask, !controlsCollapsed {
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text("Focus Mask")
                            .font(.headline)
                        Spacer()
                        Button {
                            withAnimation(.easeInOut(duration: 0.2)) {
                                controlsCollapsed = true
                            }
                            saveFocusMaskSettings()
                        } label: {
                            Label("Hide", systemImage: "chevron.down")
                                .font(.caption)
                                .labelStyle(.titleAndIcon)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(.quaternary, in: RoundedRectangle(cornerRadius: 6))
                        }
                        .buttonStyle(.plain)

                        Button("Reset") {
                            let d = FocusDetectorConfig()
                            config.preBlurRadius = d.preBlurRadius
                            config.threshold = d.threshold
                            config.energyMultiplier = d.energyMultiplier
                            config.erosionRadius = d.erosionRadius
                            config.dilationRadius = d.dilationRadius
                            config.featherRadius = d.featherRadius
                            config.showRawLaplacian = d.showRawLaplacian
                            overlayOpacity = 0.95
                            saveFocusMaskSettings()
                        }
                        .buttonStyle(.borderless)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    }

                    LabeledSlider(
                        label: "Threshold",
                        value: $config.threshold,
                        range: 0.01 ... 0.70,
                        hint: "Lower = more highlighted, Higher = only sharpest edges",
                    )

                    LabeledSlider(
                        label: "Pre-blur",
                        value: $config.preBlurRadius,
                        range: 0.3 ... 4.0,
                        hint: "Higher = ignore more background texture",
                    )

                    LabeledSlider(
                        label: "Amplify",
                        value: $config.energyMultiplier,
                        range: 1.0 ... 20.0,
                        hint: "Amplification of sharpness signal before threshold",
                    )

                    LabeledSlider(
                        label: "Erosion",
                        value: $config.erosionRadius,
                        range: 0.0 ... 2.0,
                        hint: "Higher = removes more isolated noise pixels",
                    )

                    LabeledSlider(
                        label: "Dilation",
                        value: $config.dilationRadius,
                        range: 0.0 ... 3.0,
                        hint: "Higher = expands and connects nearby mask regions",
                    )
                }
                .padding()
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
                .padding(.horizontal)
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }

            // Capsule row — hidden while the slider panel is open
            if !showFocusMask || controlsCollapsed {
                HStack(spacing: 12) {
                    if showFocusMask {
                        Button {
                            withAnimation(.easeInOut(duration: 0.2)) {
                                controlsCollapsed.toggle()
                            }
                        } label: {
                            HStack(spacing: 8) {
                                Image(systemName: "viewfinder")
                                    .font(.caption)
                                Text("Focus Mask Controls")
                                    .font(.caption)
                                Image(systemName: controlsCollapsed ? "chevron.up" : "chevron.down")
                                    .font(.caption)
                            }
                            .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                        .transition(.move(edge: .trailing).combined(with: .opacity))
                    }

                    Button {
                        withAnimation(.easeInOut(duration: 0.2)) { showFocusMask.toggle() }
                    } label: {
                        Image(systemName: showFocusMask ? "viewfinder.circle.fill" : "viewfinder.circle")
                            .font(.title3)
                            .foregroundStyle(showFocusMask ? .blue : .primary)
                            .symbolEffect(.bounce, value: showFocusMask)
                    }
                    .buttonStyle(.plain)
                    .disabled(!focusMaskAvailable)
                    .help(showFocusMask ? "Hide focus mask" : "Show focus mask")
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 9)
                .background(.regularMaterial, in: Capsule())
                .overlay { Capsule().strokeBorder(.primary.opacity(0.1), lineWidth: 0.5) }
                .padding(10)
                .animation(.spring(duration: 0.3), value: showFocusMask)
                .transition(.opacity)
            }
        }
    }

    private func saveFocusMaskSettings() {
        let s = SettingsViewModel.shared
        s.focusMaskPreBlurRadius = config.preBlurRadius
        s.focusMaskThreshold = config.threshold
        s.focusMaskEnergyMultiplier = config.energyMultiplier
        s.focusMaskErosionRadius = config.erosionRadius
        s.focusMaskDilationRadius = config.dilationRadius
        s.focusMaskFeatherRadius = config.featherRadius
        Task { await s.saveSettings() }
    }
}
