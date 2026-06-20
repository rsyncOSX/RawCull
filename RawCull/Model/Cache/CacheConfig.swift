//
//  CacheConfig.swift
//  RawCull
//
//  Created by Thomas Evensen on 07/02/2026.
//

import Foundation

nonisolated enum CacheRecommendationPolicy {
    static let megabyte = 1024 * 1024
    static let sixteenGB = 16 * 1024 * megabyte
    static let thirtyTwoGB = 32 * 1024 * megabyte
    static let sixtyFourGB = 64 * 1024 * megabyte
    static let freeReserveMB = 3 * 1024
    static let adaptiveHeadroomFraction = 0.5
    static let previewExtraFraction = 0.65
    static let gridExtraFraction = 0.35
    static let roundingStepMB = 256

    struct Limits: Equatable {
        let previewMB: Int
        let gridMB: Int
    }

    static func baselineLimits(physicalMemoryBytes: UInt64) -> Limits {
        if physicalMemoryBytes >= UInt64(sixtyFourGB) {
            return Limits(previewMB: 8000, gridMB: 2000)
        }
        if physicalMemoryBytes >= UInt64(thirtyTwoGB) {
            return Limits(previewMB: 4096, gridMB: 1024)
        }
        return Limits(previewMB: 2048, gridMB: 768)
    }

    static func defaultUserMaxLimits(physicalMemoryBytes: UInt64) -> Limits {
        if physicalMemoryBytes >= UInt64(sixtyFourGB) {
            return Limits(previewMB: 8000, gridMB: 2000)
        }
        if physicalMemoryBytes >= UInt64(thirtyTwoGB) {
            return Limits(previewMB: 4096, gridMB: 1024)
        }
        return Limits(previewMB: 4096, gridMB: 1024)
    }

    static func adaptiveLimits(
        physicalMemoryBytes: UInt64,
        usedMemoryBytes: UInt64,
        userPreviewMaxMB: Int,
        userGridMaxMB: Int,
        pressureLevel: SharedMemoryCache.MemoryPressureLevel,
    ) -> Limits {
        let baseline = baselineLimits(physicalMemoryBytes: physicalMemoryBytes)
        let tierCap = tierCapLimits(physicalMemoryBytes: physicalMemoryBytes)

        guard pressureLevel == .normal else {
            let previewMB = max(CacheSettingsLimits.memoryMinMB, roundUpMB(Int(Double(baseline.previewMB) * 0.6)))
            let gridMB = max(CacheSettingsLimits.gridMinMB, roundUpMB(Int(Double(baseline.gridMB) * 0.6)))
            return Limits(
                previewMB: min(previewMB, userPreviewMaxMB),
                gridMB: min(gridMB, userGridMaxMB),
            )
        }

        let physicalMB = Int(physicalMemoryBytes / UInt64(megabyte))
        let usedMB = Int(min(usedMemoryBytes, physicalMemoryBytes) / UInt64(megabyte))
        let freeMB = max(0, physicalMB - usedMB)
        let expandableMB = max(0, freeMB - freeReserveMB)
        let extraBudgetMB = Int(Double(expandableMB) * adaptiveHeadroomFraction)

        let previewMB = roundUpMB(baseline.previewMB + Int(Double(extraBudgetMB) * previewExtraFraction))
        let gridMB = roundUpMB(baseline.gridMB + Int(Double(extraBudgetMB) * gridExtraFraction))

        return Limits(
            previewMB: min(max(previewMB, baseline.previewMB), tierCap.previewMB, userPreviewMaxMB),
            gridMB: min(max(gridMB, baseline.gridMB), tierCap.gridMB, userGridMaxMB),
        )
    }

    private static func tierCapLimits(physicalMemoryBytes: UInt64) -> Limits {
        if physicalMemoryBytes >= UInt64(sixtyFourGB) {
            return Limits(previewMB: 8000, gridMB: 2000)
        }
        if physicalMemoryBytes >= UInt64(thirtyTwoGB) {
            return Limits(previewMB: 8000, gridMB: 2000)
        }
        return Limits(previewMB: 4096, gridMB: 1024)
    }

    private static func roundUpMB(_ value: Int) -> Int {
        guard value > 0 else { return 0 }
        return ((value + roundingStepMB - 1) / roundingStepMB) * roundingStepMB
    }
}

struct CacheConfig {
    nonisolated let totalCostLimit: Int
    nonisolated let countLimit: Int
    /// Cap (in bytes) for the dedicated grid (200px) NSCache.
    nonisolated let gridTotalCostLimit: Int

    nonisolated init(
        totalCostLimit: Int,
        countLimit: Int,
        gridTotalCostLimit: Int = 400 * 1024 * 1024,
    ) {
        self.totalCostLimit = totalCostLimit
        self.countLimit = countLimit
        self.gridTotalCostLimit = gridTotalCostLimit
    }

    nonisolated static let production = CacheConfig(
        totalCostLimit: 500 * 1024 * 1024, // ~500 MB for ~112 1024x1024 images
        countLimit: 1000,
    )

    nonisolated static let testing = CacheConfig(
        totalCostLimit: 100_000, // Very small for testing evictions
        countLimit: 5,
    )
}
