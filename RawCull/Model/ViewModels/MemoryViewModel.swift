//
//  MemoryViewModel.swift
//  RawCull
//
//  Created by Thomas Evensen on 12/02/2026.
//

import Foundation
import Observation
import OSLog

@Observable
final class MemoryViewModel {
    var totalMemory: UInt64 = 0
    var usedMemory: UInt64 = 0
    var appMemory: UInt64 = 0
    var memoryPressureThreshold: UInt64 = 0

    // macOS-reported memory pressure level
    var systemPressureLevel: MemoryPressureLevel = .normal

    private let pressureThresholdFactor: Double
    // nonisolated let — deinit can cancel without hopping to the main actor
    private nonisolated let pressureSource: DispatchSourceMemoryPressure

    enum MemoryPressureLevel {
        case normal, warning, critical

        var label: String {
            switch self {
            case .normal:   return "Normal"
            case .warning:  return "Warning"
            case .critical: return "Critical"
            }
        }

        var systemImage: String {
            switch self {
            case .normal:   return "checkmark.circle.fill"
            case .warning:  return "exclamationmark.triangle.fill"
            case .critical: return "xmark.octagon.fill"
            }
        }
    }

    init(
        updateInterval _: TimeInterval = 1.5,
        pressureThresholdFactor: Double = 0.80
    ) {
        self.pressureThresholdFactor = pressureThresholdFactor

        // Build the source before self is fully initialised so it can be
        // assigned to the nonisolated let in one phase.
        let source = DispatchSource.makeMemoryPressureSource(
            eventMask: [.normal, .warning, .critical],
            queue: .main
        )
        self.pressureSource = source

        source.setEventHandler { [weak self] in
            guard let self else { return }
            let event = source.data
            if event.contains(.critical) {
                self.systemPressureLevel = .critical
            } else if event.contains(.warning) {
                self.systemPressureLevel = .warning
            } else {
                self.systemPressureLevel = .normal
            }
            Logger.process.debugMessageOnly(
                "MemoryViewModel: system pressure → \(self.systemPressureLevel.label)"
            )
        }

        source.resume()
    }

    deinit {
        // DispatchSource.cancel() is safe to call from any context,
        // so no main-actor hop is needed here.
        pressureSource.cancel()
        Logger.process.debugMessageOnly("MemoryViewModel: deinitialized")
    }

    // MARK: - Computed percentages

    var memoryPressurePercentage: Double {
        guard totalMemory > 0 else { return 0 }
        return Double(memoryPressureThreshold) / Double(totalMemory) * 100
    }

    var usedMemoryPercentage: Double {
        guard totalMemory > 0 else { return 0 }
        return Double(usedMemory) / Double(totalMemory) * 100
    }

    var appMemoryPercentage: Double {
        guard usedMemory > 0 else { return 0 }
        return Double(appMemory) / Double(usedMemory) * 100
    }

    // MARK: - Update

    func updateMemoryStats() {
        totalMemory = ProcessInfo.processInfo.physicalMemory
        usedMemory = getUsedSystemMemory()
        appMemory = getAppMemory()
        memoryPressureThreshold = calculateMemoryPressureThreshold()

        let message = "MemoryViewModel: updateMemoryStats() Total: \(formatBytes(totalMemory)), " +
            "Used: \(formatBytes(usedMemory)), App: \(formatBytes(appMemory))"
        Logger.process.debugMessageOnly(message)
    }

    // MARK: - Private helpers

    private func getUsedSystemMemory() -> UInt64 {
        let total = ProcessInfo.processInfo.physicalMemory

        var stat = vm_statistics64()
        var count = mach_msg_type_number_t(
            MemoryLayout<vm_statistics64>.size / MemoryLayout<integer_t>.size
        )

        let result = withUnsafeMutablePointer(to: &stat) {
            $0.withMemoryRebound(to: integer_t.self, capacity: 1) {
                host_statistics64(mach_host_self(), HOST_VM_INFO64, $0, &count)
            }
        }

        guard result == KERN_SUCCESS else { return 0 }

        let pageSize   = UInt64(getpagesize())
        let wired      = UInt64(stat.wire_count)
        let active     = UInt64(stat.active_count)
        let compressed = UInt64(stat.compressor_page_count)

        return min((wired + active + compressed) * pageSize, total)
    }

    private func getAppMemory() -> UInt64 {
        var info  = task_vm_info_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<task_vm_info>.size / 4)

        let result = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: 1) {
                task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &count)
            }
        }

        guard result == KERN_SUCCESS else { return 0 }
        return info.phys_footprint
    }

    private func calculateMemoryPressureThreshold() -> UInt64 {
        UInt64(Double(totalMemory) * pressureThresholdFactor)
    }

    // MARK: - Formatting

    func formatBytes(_ bytes: UInt64) -> String {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useGB, .useMB]
        formatter.countStyle = .memory
        return formatter.string(fromByteCount: Int64(bytes))
    }
}
