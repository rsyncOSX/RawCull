//
//  MemoryDiagnosticsViewModel.swift
//  RawCull
//
//  Created by Thomas Evensen on 28/04/2026.
//
//  View model for the Memory Console window. Samples cache + system memory
//  metrics every 5 seconds while the window is open, and exposes the session
//  log as TSV for clipboard export. Used to tune the empirical projection in
//  `SettingsViewModel.projectedRawCullMemoryBytes()` against real RawCull RSS
//  during a culling session.
//

import AppKit
import Foundation
import Observation
import OSLog

@Observable
@MainActor
final class MemoryDiagnosticsViewModel {
    struct Entry: Identifiable {
        let id = UUID()
        let timestamp: Date
        let physicalMB: Int
        let usedMB: Int
        let freeMB: Int
        let appMB: Int
        let threshold85MB: Int
        let headroomMB: Int
        let pressure: String
        let memItems: Int
        let memCostMB: Int
        let memLimitMB: Int
        let gridItems: Int
        let gridCostMB: Int
        let gridLimitMB: Int
        // let projectedMB: Int
        let scannedFiles: Int
        let cacheHits: Int
        let cacheMisses: Int
        let evictions: Int
        // Layer-relative hit rate: RAM / (RAM + disk). Excludes cold
        // extractions, so it's not a true cache hit rate. Kept for log
        // continuity; new analyses should prefer `trueHitRatePct`.
        let hitRatePct: Double
        let coldExtracts: Int
        let demandTotal: Int
        let boomerangMisses: Int
        let trueHitRatePct: Double
        let coldRatePct: Double
        // Pressure-flicker diagnostics: live cost cap on memoryCache (catches
        // transient warning-driven shrinks) and cumulative event counts (catch
        // events that fully resolved between 5 s ticks).
        let liveLimitMB: Int
        let pressureWarns: Int
        let pressureCrits: Int
    }

    private(set) var entries: [Entry] = []
    private(set) var isLogging: Bool = false

    @ObservationIgnored private var samplingTask: Task<Void, Never>?
    @ObservationIgnored private let memoryModel = MemoryViewModel()

    static let samplingInterval: Duration = .seconds(5)

    deinit {
        samplingTask?.cancel()
    }

    func startLogging(viewModel: RawCullViewModel) {
        guard !isLogging else { return }
        isLogging = true
        entries.removeAll()
        Logger.process.debugMessageOnly("MemoryDiagnosticsViewModel STARTED")

        samplingTask = Task { [weak self, weak viewModel] in
            await self?.captureSample(viewModel: viewModel)
            while !Task.isCancelled {
                try? await Task.sleep(for: Self.samplingInterval)
                if Task.isCancelled { break }
                await self?.captureSample(viewModel: viewModel)
            }
        }
    }

    func stopLogging() {
        samplingTask?.cancel()
        samplingTask = nil
        isLogging = false
        Logger.process.debugMessageOnly("MemoryDiagnosticsViewModel STOPPED")
    }

    private func captureSample(viewModel: RawCullViewModel?) async {
        await memoryModel.updateMemoryStats()

        let physical = ProcessInfo.processInfo.physicalMemory
        let used = memoryModel.usedMemory
        let app = memoryModel.appMemory
        let threshold = memoryModel.memoryPressureThreshold
        let free: UInt64 = used < physical ? physical - used : 0
        let headroom: UInt64 = threshold > used ? threshold - used : 0

        let stats = await SharedMemoryCache.shared.getCacheStatistics()
        let memItems = SharedMemoryCache.shared.getMemoryCacheCount()
        let memCost = SharedMemoryCache.shared.getMemoryCacheCurrentCost()
        let gridItems = SharedMemoryCache.shared.getGridCacheCount()
        let gridCost = SharedMemoryCache.shared.getGridCacheCurrentCost()
        let cold = SharedMemoryCache.shared.getColdExtractCount()
        let demand = SharedMemoryCache.shared.getDemandRequestCount()
        let boomerang = SharedMemoryCache.shared.getBoomerangMissCount()
        let trueHitRate = demand > 0 ? Double(stats.hits) / Double(demand) * 100 : 0
        let coldRate = demand > 0 ? Double(cold) / Double(demand) * 100 : 0
        let liveLimit = SharedMemoryCache.shared.getLiveTotalCostLimit()
        let warns = SharedMemoryCache.shared.getPressureWarningCount()
        let crits = SharedMemoryCache.shared.getPressureCriticalCount()

        let settings = SettingsViewModel.shared
        // let projected = settings.projectedRawCullMemoryBytes()
        let scanned = viewModel?.files.count ?? 0

        let entry = Entry(
            timestamp: Date(),
            physicalMB: bytesToMB(physical),
            usedMB: bytesToMB(used),
            freeMB: bytesToMB(free),
            appMB: bytesToMB(app),
            threshold85MB: bytesToMB(threshold),
            headroomMB: bytesToMB(headroom),
            pressure: SharedMemoryCache.shared.currentPressureLevel.label,
            memItems: memItems,
            memCostMB: memCost / (1024 * 1024),
            memLimitMB: settings.memoryCacheSizeMB,
            gridItems: gridItems,
            gridCostMB: gridCost / (1024 * 1024),
            gridLimitMB: settings.gridCacheSizeMB,
            // projectedMB: bytesToMB(projected),
            scannedFiles: scanned,
            cacheHits: stats.hits,
            cacheMisses: stats.misses,
            evictions: stats.evictions,
            hitRatePct: stats.hitRate,
            coldExtracts: cold,
            demandTotal: demand,
            boomerangMisses: boomerang,
            trueHitRatePct: trueHitRate,
            coldRatePct: coldRate,
            liveLimitMB: liveLimit / (1024 * 1024),
            pressureWarns: warns,
            pressureCrits: crits,
        )
        entries.append(entry)
    }

    private nonisolated func bytesToMB(_ bytes: UInt64) -> Int {
        Int(bytes / (1024 * 1024))
    }

    // MARK: - Clipboard / TSV

    func copyAllToClipboard() {
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(tsvSnapshot(), forType: .string)
    }

    func tsvSnapshot() -> String {
        var lines: [String] = [Self.tsvHeader]
        lines.reserveCapacity(entries.count + 1)
        for e in entries {
            lines.append(e.tsvRow())
        }
        return lines.joined(separator: "\n")
    }

    static let tsvHeader: String = [
        "timestamp",
        "physical_MB",
        "used_MB",
        "free_MB",
        "app_MB",
        "threshold_85_MB",
        "headroom_MB",
        "pressure",
        "mem_items",
        "mem_cost_MB",
        "mem_limit_MB",
        "grid_items",
        "grid_cost_MB",
        "grid_limit_MB",
        "scanned_files",
        "cache_hits",
        "cache_misses",
        "evictions",
        "hit_rate_pct",
        // New columns appended at the end so positions of pre-existing
        // columns stay stable for older log parsers / spreadsheets.
        "cold_extracts",
        "demand_total",
        "boomerang_misses",
        "true_hit_rate_pct",
        "cold_rate_pct",
        "live_limit_MB",
        "pressure_warns",
        "pressure_crits"
    ].joined(separator: "\t")
}

extension MemoryDiagnosticsViewModel.Entry {
    private static let isoFormatter: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()

    func tsvRow() -> String {
        var fields: [String] = []
        fields.reserveCapacity(25)
        fields.append(Self.isoFormatter.string(from: timestamp))
        fields.append(String(physicalMB))
        fields.append(String(usedMB))
        fields.append(String(freeMB))
        fields.append(String(appMB))
        fields.append(String(threshold85MB))
        fields.append(String(headroomMB))
        fields.append(pressure)
        fields.append(String(memItems))
        fields.append(String(memCostMB))
        fields.append(String(memLimitMB))
        fields.append(String(gridItems))
        fields.append(String(gridCostMB))
        fields.append(String(gridLimitMB))
        // fields.append(String(projectedMB))
        fields.append(String(scannedFiles))
        fields.append(String(cacheHits))
        fields.append(String(cacheMisses))
        fields.append(String(evictions))
        fields.append(String(format: "%.2f", hitRatePct))
        fields.append(String(coldExtracts))
        fields.append(String(demandTotal))
        fields.append(String(boomerangMisses))
        fields.append(String(format: "%.2f", trueHitRatePct))
        fields.append(String(format: "%.2f", coldRatePct))
        fields.append(String(liveLimitMB))
        fields.append(String(pressureWarns))
        fields.append(String(pressureCrits))
        return fields.joined(separator: "\t")
    }
}
