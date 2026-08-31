//
//  ProgressCount.swift
//  RawCull
//
//  Created by Thomas Evensen on 23/01/2026.
//

import SwiftUI

struct ProgressCount: View {
    let completed: Int
    let total: Int
    let estimatedSeconds: Int // seconds to completion
    @State private var displayedEstimatedSeconds = 0
    let statusText: String

    private var formattedTime: String {
        if displayedEstimatedSeconds < 60 {
            "\(displayedEstimatedSeconds)s"
        } else {
            "\(displayedEstimatedSeconds / 60)m \(displayedEstimatedSeconds % 60)s"
        }
    }

    var body: some View {
        HStack(spacing: 12) {
            // Compact circular progress indicator
            ZStack {
                Circle()
                    .stroke(
                        Color.gray.opacity(0.2),
                        lineWidth: 6,
                    )

                if total > 0 {
                    Circle()
                        .trim(from: 0, to: min(Double(completed) / Double(total), 1.0))
                        .stroke(
                            LinearGradient(
                                colors: [.blue, .cyan],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing,
                            ),
                            style: StrokeStyle(
                                lineWidth: 6,
                                lineCap: .round,
                            ),
                        )
                        .rotationEffect(.degrees(-90))
                        .animation(.spring(response: 0.6, dampingFraction: 0.8), value: completed)
                }

                Text("\(completed)")
                    .font(.system(size: 14, weight: .semibold, design: .rounded))
                    .contentTransition(.numericText(countsDown: false))
            }
            .frame(width: 60, height: 60)

            VStack(alignment: .leading, spacing: 2) {
                Text(statusText)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                Text("Estimated time left: \(formattedTime)")
                    .font(.body)
                    .foregroundStyle(.primary)
            }

            Spacer()
        }
        .padding(12)
        .background(Color(nsColor: .controlBackgroundColor).opacity(0.3))
        .cornerRadius(6)
        .animation(.default, value: completed)
        .onAppear {
            updateDisplayedEstimatedSeconds(estimatedSeconds)
        }
        .onChange(of: estimatedSeconds) { _, newValue in
            updateDisplayedEstimatedSeconds(newValue)
        }
    }

    private func updateDisplayedEstimatedSeconds(_ newValue: Int) {
        let clampedValue = Swift.max(0, newValue)

        if clampedValue == 0 || displayedEstimatedSeconds == 0 || clampedValue <= displayedEstimatedSeconds {
            displayedEstimatedSeconds = clampedValue
        }
    }
}
