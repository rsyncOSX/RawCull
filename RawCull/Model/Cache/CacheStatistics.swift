//
//  CacheStatistics.swift
//  RawCull
//
//  Created by Thomas Evensen on 05/02/2026.
//

import Foundation

struct CacheStatistics: Sendable {
    nonisolated let hits: Int
    nonisolated let misses: Int
    nonisolated let evictions: Int
    nonisolated let hitRate: Double
}
