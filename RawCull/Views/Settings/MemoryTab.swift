//
//  MemoryTab.swift
//  RawCull
//
//  Created by Thomas Evensen on 12/02/2026.
//

import SwiftUI

struct MemoryTab: View {
    @State private var memoryModel = MemoryViewModel()

    var body: some View {
        VStack(spacing: 20) {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    // Total Memory
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Label("Total Unified Memory", systemImage: "memorychip.fill")
                                .font(.system(size: 12, weight: .semibold))
                            Spacer()
                            Text(memoryModel.formatBytes(memoryModel.totalMemory))
                                .font(.system(size: 12, weight: .semibold, design: .rounded))
                        }
                        .foregroundStyle(.primary)
                    }

                    Divider()

                    // Used Memory Display
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Label("Total Used Memory", systemImage: "chart.bar.fill")
                                .font(.system(size: 12, weight: .semibold))
                            Spacer()
                            Text(memoryModel.formatBytes(memoryModel.usedMemory))
                                .font(.system(size: 12, weight: .semibold, design: .rounded))
                        }
                        .foregroundStyle(.primary)

                        // Progress bar for used memory
                        GeometryReader { geometry in
                            ZStack(alignment: .leading) {
                                // Background
                                RoundedRectangle(cornerRadius: 6)
                                    .fill(Color(.controlBackgroundColor))

                                // Memory pressure threshold line
                                VStack {
                                    Spacer()
                                    ZStack(alignment: .leading) {
                                        RoundedRectangle(cornerRadius: 6)
                                            .fill(Color.blue.opacity(0.3))
                                        RoundedRectangle(cornerRadius: 6)
                                            .fill(Color.blue)
                                            .frame(width: geometry.size.width * memoryModel.usedMemoryPercentage / 100)
                                        // Threshold marker
                                        Rectangle()
                                            .fill(Color.red)
                                            .frame(width: 2)
                                            .offset(x: geometry.size.width * memoryModel.memoryPressurePercentage / 100)
                                    }
                                }
                            }
                        }
                        .frame(height: 24)

                        HStack(spacing: 20) {
                            HStack(spacing: 4) {
                                Circle()
                                    .fill(Color.blue)
                                    .frame(width: 8, height: 8)
                                Text("Used: \(String(format: "%.1f", memoryModel.usedMemoryPercentage))%")
                                    .font(.system(size: 10, weight: .regular))
                            }

                            HStack(spacing: 4) {
                                Rectangle()
                                    .fill(Color.red)
                                    .frame(width: 8, height: 8)
                                Text("Pressure: \(String(format: "%.1f", memoryModel.memoryPressurePercentage))%")
                                    .font(.system(size: 10, weight: .regular))
                            }

                            Spacer()
                        }
                        .foregroundStyle(.secondary)
                    }

                    Divider()

                    // App Memory
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Label("App Memory Usage", systemImage: "app.gift.fill")
                                .font(.system(size: 12, weight: .semibold))
                            Spacer()
                            Text(memoryModel.formatBytes(memoryModel.appMemory))
                                .font(.system(size: 12, weight: .semibold, design: .rounded))
                        }
                        .foregroundStyle(.primary)

                        HStack {
                            Text("Of total used memory:")
                                .font(.system(size: 10, weight: .regular))
                            Spacer()
                            Text(String(format: "%.1f%%", memoryModel.appMemoryPercentage))
                                .font(.system(size: 10, weight: .semibold, design: .rounded))
                        }
                        .foregroundStyle(.secondary)

                        // App memory progress bar
                        GeometryReader { geometry in
                            RoundedRectangle(cornerRadius: 6)
                                .fill(Color(.controlBackgroundColor))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 6)
                                        .fill(Color.green)
                                        .frame(
                                            width: geometry.size.width *
                                                memoryModel.appMemoryPercentage / 100,
                                            alignment: .leading
                                        ),
                                    alignment: .leading
                                )
                        }
                        .frame(height: 20)
                    }

                    Divider()

                    // Info section
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Memory Information")
                            .font(.system(size: 12, weight: .semibold))
                        Text("• Total Unified Memory: Total physical memory available\n" +
                            "• Total Used Memory: All processes combined\n" +
                            "• App Memory: RawCull process only\n" +
                            "• Pressure: macOS threshold where memory warnings occur")
                            .font(.system(size: 10, weight: .regular))
                            .foregroundStyle(.secondary)
                            .lineSpacing(2)
                    }
                    .padding(12)
                    .background(Color(.controlBackgroundColor))
                    .cornerRadius(8)
                }
                .padding(16)
            }
        }
        .task {
            let timerStream = AsyncStream<Void> { continuation in
                Task {
                    while !Task.isCancelled {
                        continuation.yield()
                        try? await Task.sleep(nanoseconds: 1_000_000_000)
                    }
                    continuation.finish()
                }
            }

            // Consume the stream
            for await _ in timerStream {
                memoryModel.updateMemoryStats()
            }
        }
    }
}
