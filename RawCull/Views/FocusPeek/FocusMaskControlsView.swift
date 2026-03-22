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
            if showFocusMask && !controlsCollapsed {
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text("Focus Mask")
                            .font(.headline)
                        Spacer()
                        Button {
                            withAnimation(.easeInOut(duration: 0.2)) {
                                controlsCollapsed = true
                            }
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
                            config = FocusDetectorConfig()
                            overlayOpacity = 0.85
                        }
                        .buttonStyle(.borderless)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    }

                    LabeledSlider(
                        label: "Threshold",
                        value: $config.threshold,
                        range: 0.10 ... 0.50,
                        hint: "Lower = more highlighted, Higher = only sharpest edges",
                    )

                    LabeledSlider(
                        label: "Pre-blur",
                        value: $config.preBlurRadius,
                        range: 0.5 ... 2.5,
                        hint: "Higher = ignore more background texture",
                    )

                    LabeledSlider(
                        label: "Amplify",
                        value: $config.energyMultiplier,
                        range: 4.0 ... 20.0,
                        hint: "Amplification of sharpness signal",
                    )

                    LabeledSlider(
                        label: "Overlay",
                        value: Binding(
                            get: { Float(overlayOpacity) },
                            set: { overlayOpacity = Double($0) },
                        ),
                        range: 0.3 ... 1.0,
                        hint: "Overlay strength",
                    )
                }
                .padding()
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
                .padding(.horizontal)
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }

            // Capsule row — always visible, mirrors FocusPointControllerView
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
            .background(.ultraThinMaterial, in: Capsule())
            .overlay { Capsule().strokeBorder(.primary.opacity(0.1), lineWidth: 0.5) }
            .padding(10)
            .animation(.spring(duration: 0.3), value: showFocusMask)
        }
    }
}
