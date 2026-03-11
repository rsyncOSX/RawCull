//
//  FocusDetectorControlsView.swift
//  RawCull
//
//  Created by Thomas Evensen on 11/03/2026.
//

import SwiftUI

struct FocusDetectorControlsView: View {
    @Bindable var model: FocusDetectorMaskModel

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Focus Mask Controls")
                .font(.headline)

            LabeledSlider(
                label: "Threshold",
                value: $model.config.threshold,
                range: 0.05 ... 0.60,
                hint: "Lower = more highlighted, Higher = only sharpest edges"
            )

            LabeledSlider(
                label: "Pre-blur",
                value: $model.config.preBlurRadius,
                range: 0.0 ... 3.0,
                hint: "Higher = ignore more background texture"
            )

            LabeledSlider(
                label: "Sensitivity",
                value: $model.config.energyMultiplier,
                range: 4.0 ... 30.0,
                hint: "Amplification of sharpness signal"
            )
        }
        .padding()
    }
}

private struct LabeledSlider: View {
    let label: String
    @Binding var value: Float
    let range: ClosedRange<Float>
    let hint: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(label)
                    .font(.subheadline)
                Spacer()
                Text(String(format: "%.2f", value))
                    .font(.subheadline.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            Slider(value: $value, in: range)
            Text(hint)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}
