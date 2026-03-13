//
//  SettingsSliderRow.swift
//  RawCull
//
//  Created by Thomas Evensen on 13/03/2026.
//

import SwiftUI

struct SettingsSliderRow: View {
    let title: String
    let systemImage: String
    let valueText: String
    let description: String
    @Binding var value: Double
    let range: ClosedRange<Double>
    let step: Double

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Label(title, systemImage: systemImage)
                    .font(.system(size: 12, weight: .medium))
                Spacer()
                Text(valueText)
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
            }
            Slider(value: $value, in: range, step: step)
            Text(description)
                .font(.system(size: 11, weight: .regular))
                .foregroundStyle(.secondary)
        }
    }
}
