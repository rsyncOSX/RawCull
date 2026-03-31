//
//  FocusPointsProgressView.swift
//  RawCull
//

import SwiftUI

/// Linear 0-100 % progress bar shown while extractNativeFocusPoints is running.
struct FocusPointsProgressView: View {
    let completed: Int
    let total: Int

    private var fraction: Double {
        total > 0 ? Double(completed) / Double(total) : 0
    }

    private var percentage: Int {
        Int(fraction * 100)
    }

    var body: some View {
        VStack(spacing: 8) {
            HStack {
                Text("Extracting focus points…")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Text("\(percentage)%")
                    .font(.caption)
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
                    .contentTransition(.numericText())
            }

            ProgressView(value: fraction)
                .progressViewStyle(.linear)
                .animation(.easeInOut(duration: 0.2), value: fraction)
        }
        .padding()
    }
}
