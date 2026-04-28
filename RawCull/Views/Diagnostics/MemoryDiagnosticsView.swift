//
//  MemoryDiagnosticsView.swift
//  RawCull
//
//  Created by Thomas Evensen on 28/04/2026.
//
//  Memory Console window. Opened from Diagnostics → Memory Console.
//  Logging is strictly window-bound: it starts on .onAppear and stops on
//  .onDisappear, so it has zero runtime cost when the window is closed.
//

import SwiftUI

struct MemoryDiagnosticsView: View {
    @State private var diagnostics = MemoryDiagnosticsViewModel()
    @Environment(RawCullViewModel.self) private var viewModel

    private static let timestampFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss.SSS"
        return f
    }()

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            logScroll
        }
        .frame(minWidth: 640, minHeight: 360)
        .onAppear { diagnostics.startLogging(viewModel: viewModel) }
        .onDisappear { diagnostics.stopLogging() }
    }

    private var header: some View {
        HStack(spacing: 12) {
            Image(systemName: diagnostics.isLogging
                ? "record.circle.fill"
                : "record.circle")
                .foregroundStyle(diagnostics.isLogging ? .red : .secondary)
            Text(diagnostics.isLogging
                ? "Logging every 5 s · \(diagnostics.entries.count) samples"
                : "Stopped")
                .font(.system(size: 12, weight: .medium))
            Spacer()
            Button("Copy All") {
                diagnostics.copyAllToClipboard()
            }
            .disabled(diagnostics.entries.isEmpty)
            .keyboardShortcut("c", modifiers: [.command, .shift])
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    private var logScroll: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 2) {
                    Text(MemoryDiagnosticsViewModel.tsvHeader)
                        .font(.system(.caption, design: .monospaced).weight(.semibold))
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                        .padding(.bottom, 4)

                    ForEach(diagnostics.entries) { entry in
                        Text(formatRow(entry))
                            .font(.system(.caption, design: .monospaced))
                            .textSelection(.enabled)
                            .id(entry.id)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .onChange(of: diagnostics.entries.count) { _, _ in
                if let last = diagnostics.entries.last {
                    withAnimation(.linear(duration: 0.1)) {
                        proxy.scrollTo(last.id, anchor: .bottom)
                    }
                }
            }
        }
    }

    private func formatRow(_ e: MemoryDiagnosticsViewModel.Entry) -> String {
        let ts = Self.timestampFormatter.string(from: e.timestamp)
        let hitRate = String(format: "%.1f", e.hitRatePct)
        let trueHit = String(format: "%.1f", e.trueHitRatePct)
        let coldRate = String(format: "%.1f", e.coldRatePct)
        let fields: [String] = [
            ts,
            "app=\(e.appMB)MB",
            "used=\(e.usedMB)MB",
            "free=\(e.freeMB)MB",
            "head=\(e.headroomMB)MB",
            "mem=\(e.memCostMB)/\(e.memLimitMB)MB(\(e.memItems))",
            "grid=\(e.gridCostMB)/\(e.gridLimitMB)MB(\(e.gridItems))",
            // "proj=\(e.projectedMB)MB",
            "files=\(e.scannedFiles)",
            "press=\(e.pressure)",
            "hits=\(e.cacheHits)",
            "miss=\(e.cacheMisses)",
            "evict=\(e.evictions)",
            "hit%=\(hitRate)",
            "demand=\(e.demandTotal)",
            "cold=\(e.coldExtracts)",
            "boom=\(e.boomerangMisses)",
            "true%=\(trueHit)",
            "cold%=\(coldRate)",
            "live=\(e.liveLimitMB)MB",
            "warn=\(e.pressureWarns)",
            "crit=\(e.pressureCrits)",
        ]
        return fields.joined(separator: "  ")
    }
}
