//
//  ProgressCount.swift
//  RawCull
//
//  Created by Thomas Evensen on 23/01/2026.
//

import SwiftUI

struct ProgressCount: View {
    @Binding var progress: Double
    @Binding var estimatedSeconds: Int // seconds to completion
    let max: Double
    let statusText: String

    private var formattedTime: String {
        if estimatedSeconds < 60 {
            return "\(estimatedSeconds)s"
        } else {
            return "\(estimatedSeconds / 60)m \(estimatedSeconds % 60)s"
        }
    }

    var body: some View {
        HStack(spacing: 12) {
            // Compact circular progress indicator
            ZStack {
                Circle()
                    .stroke(
                        Color.gray.opacity(0.2),
                        lineWidth: 6
                    )

                if max > 0 {
                    Circle()
                        .trim(from: 0, to: min(progress / max, 1.0))
                        .stroke(
                            LinearGradient(
                                colors: [.blue, .cyan],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            style: StrokeStyle(
                                lineWidth: 6,
                                lineCap: .round
                            )
                        )
                        .rotationEffect(.degrees(-90))
                        .animation(.spring(response: 0.6, dampingFraction: 0.8), value: progress)
                }

                Text("\(Int(progress))")
                    .font(.system(size: 14, weight: .semibold, design: .rounded))
                    .contentTransition(.numericText(countsDown: false))
            }
            .frame(width: 60, height: 60)

/*
 
            VStack(alignment: .leading, spacing: 2) {
                Text(statusText)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                Text("Estimated time to completion: \(formattedTime)")
                    .font(.body)
                    .foregroundStyle(.primary)
            }
 */

            Spacer()
        }
        .padding(12)
        .background(Color(nsColor: .controlBackgroundColor).opacity(0.3))
        .cornerRadius(6)
        .animation(.default, value: progress)
    }
}
