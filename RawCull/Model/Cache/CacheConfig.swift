//
//  CacheConfig.swift
//  RawCull
//
//  Created by Thomas Evensen on 07/02/2026.
//

import Foundation

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
