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

    private let pressureThresholdFactor: Double

    init(
        updateInterval _: TimeInterval = 1.5,
        pressureThresholdFactor: Double = 0.80
    ) {
        self.pressureThresholdFactor = pressureThresholdFactor
    }

    deinit {
        // Perform synchronous cleanup; avoid spawning tasks that capture self
        // stopMonitoring()
        Logger.process.debugMessageOnly("MemoryViewModel: deinitialized")
    }

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

    func updateMemoryStats() {
        totalMemory = ProcessInfo.processInfo.physicalMemory
        usedMemory = getUsedSystemMemory()
        appMemory = getAppMemory()
        memoryPressureThreshold = calculateMemoryPressureThreshold()

        let message = "MemoryViewModel: updateMemoryStats() Total: \(formatBytes(totalMemory)), " +
            "Used: \(formatBytes(usedMemory)), App: \(formatBytes(appMemory))"
        Logger.process.debugMessageOnly(message)
    }

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

        let pageSize = UInt64(getpagesize())

        // Accurate calculation: wired + active + compressed memory
        // - wired: kernel memory, cannot be paged out
        // - active: recently used, likely still needed
        // - compressed: pages that have been compressed
        let wired = UInt64(stat.wire_count)
        let active = UInt64(stat.active_count)
        let compressed = UInt64(stat.compressor_page_count)

        let usedMemory = (wired + active + compressed) * pageSize

        // Cap at total to prevent over-reporting
        return min(usedMemory, total)
    }

    private func getAppMemory() -> UInt64 {
        var info = task_vm_info_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<task_vm_info>.size / 4)

        let result = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: 1) {
                task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &count)
            }
        }

        guard result == KERN_SUCCESS else { return 0 }

        // phys_footprint is the most accurate measure of app memory
        // It matches what Xcode's Memory Debugger shows
        return info.phys_footprint
    }

    private func calculateMemoryPressureThreshold() -> UInt64 {
        UInt64(Double(totalMemory) * pressureThresholdFactor)
    }

    func formatBytes(_ bytes: UInt64) -> String {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useGB, .useMB]
        formatter.countStyle = .memory
        return formatter.string(fromByteCount: Int64(bytes))
    }
}
