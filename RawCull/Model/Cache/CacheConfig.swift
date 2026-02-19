//
//  CacheConfig.swift
//  RawCull
//
//  Created by Thomas Evensen on 07/02/2026.
//

import Foundation

struct CacheConfig: Sendable {
    nonisolated let totalCostLimit: Int
    nonisolated let countLimit: Int
    /// Need this in return to settingsview
    nonisolated var costPerPixel: Int?

    nonisolated static let production = CacheConfig(
        totalCostLimit: 500 * 1024 * 1024, // ~500 MB for ~112 1024x1024 images
        countLimit: 1000
    )

    nonisolated static let testing = CacheConfig(
        totalCostLimit: 100_000, // Very small for testing evictions
        countLimit: 5
    )
}
