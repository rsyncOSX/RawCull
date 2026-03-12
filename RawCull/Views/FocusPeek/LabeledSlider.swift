//
//  LabeledSlider.swift
//  RawCull
//
//  Created by Thomas Evensen on 11/03/2026.
//

import SwiftUI

struct LabeledSlider: View {
    let label: String
    @Binding var value: Float
    let range: ClosedRange<Float>
    let hint: String

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text(label)
                    .font(.caption)
                Spacer()
                Text(value, format: .number.precision(.fractionLength(2)))
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            Slider(value: $value, in: range)
                .controlSize(.small)
            Text(hint)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}
