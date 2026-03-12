import SwiftUI

struct FocusMaskControlsView: View {
    @Binding var config: FocusDetectorConfig
    @Binding var overlayOpacity: Double
    @Binding var controlsCollapsed: Bool

    var body: some View {
        if controlsCollapsed {
            Button {
                withAnimation(.easeInOut(duration: 0.2)) {
                    controlsCollapsed = false
                }
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "viewfinder")
                        .font(.caption)
                    Text("Focus Mask Controls")
                        .font(.caption)
                    Image(systemName: "chevron.up")
                        .font(.caption)
                }
                .foregroundStyle(.secondary)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(.quaternary, in: Capsule())
            }
            .buttonStyle(.plain)
            .padding(.horizontal)
        } else {
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text("Focus Mask")
                        .font(.headline)
                    Spacer()
                    Button {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            controlsCollapsed.toggle()
                        }
                    } label: {
                        Label(
                            "Hide",
                            systemImage: "chevron.down",
                        )
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
        }
    }
}
