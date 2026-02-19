//
//  CacheStatisticsView.swift
//  RawCull
//
//  Created by Thomas Evensen on 05/02/2026.
//

import SwiftUI

struct CacheStatisticsView: View {
    @State private var statistics: CacheStatistics?
    let requestthumbnail: SharedRequestThumbnail

    var body: some View {
        VStack(spacing: 8) {
            HStack {
                Text("Cache Statistics")
                    .font(.system(size: 13, weight: .semibold))

                Button(action: refreshStatistics) {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 11, weight: .semibold))
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
            }

            if let stats = statistics {
                // Hit Rate - Compact circular indicator
                ZStack {
                    Circle()
                        .stroke(Color.gray.opacity(0.2), lineWidth: 2)
                    Circle()
                        .trim(from: 0, to: min(stats.hitRate / 100, 1.0))
                        .stroke(
                            LinearGradient(
                                colors: [.green, .cyan],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            style: StrokeStyle(lineWidth: 2, lineCap: .round)
                        )
                        .rotationEffect(.degrees(-90))

                    VStack(spacing: 0) {
                        Text(String(format: "%.0f", stats.hitRate))
                            .font(.system(size: 12, weight: .bold, design: .rounded))
                        Text("%")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(.secondary)
                    }
                }
                .frame(width: 36, height: 36)

                HStack(spacing: 10) {
                    // Hits and Misses - Compact horizontal
                    StatisticItemView(
                        imagelabel: "memorychip",
                        value: stats.hits,
                        color: .green
                    )
                    StatisticItemView(
                        imagelabel: "internaldrive",
                        value: stats.misses,
                        color: .orange
                    )
                    StatisticItemView(
                        imagelabel: "trash",
                        value: stats.evictions,
                        color: .red
                    )

                    Spacer()
                }
                .padding(8)
                .background(Color(.controlBackgroundColor))
                .cornerRadius(6)
            } else {
                HStack(spacing: 6) {
                    ProgressView()
                        .fixedSize()
                    Text("Loading...")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(8)
            }
        }
        .task {
            let timerStream = AsyncStream<Void> { continuation in
                Task {
                    while !Task.isCancelled {
                        continuation.yield()
                        try? await Task.sleep(nanoseconds: 5_000_000_000)
                    }
                    continuation.finish()
                }
            }

            // Consume the stream
            for await _ in timerStream {
                refreshStatistics()
            }
        }
        .padding(10)
        .background(Color(.controlBackgroundColor).opacity(0.5))
        .cornerRadius(8)
    }

    private func refreshStatistics() {
        Task {
            let stats = await requestthumbnail.getCacheStatistics()
            await MainActor.run {
                self.statistics = stats
            }
        }
    }
}

// MARK: - Statistic Item

struct StatisticItemView: View {
    let imagelabel: String
    let value: Int
    let color: Color

    var body: some View {
        VStack(spacing: 4) {
            Image(systemName: imagelabel)
                .font(.system(size: 12, weight: .semibold))

            Text("\(value)")
                .font(.system(size: 14, weight: .bold, design: .rounded))
        }
        .frame(maxWidth: .infinity)
        .padding(6)
        .background(color.opacity(0.1))
        .cornerRadius(6)
    }
}
