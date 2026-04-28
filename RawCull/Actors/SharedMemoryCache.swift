//
//  SharedMemoryCache.swift
//  RawCull
//
//  Created by Thomas Evensen on 11/02/2026.
//

import AppKit
import Dispatch
import Foundation
import os

// import OSLog

/// A thread-safe singleton wrapper around the shared NSCache.
/// We use 'actor' to safely manage state (configuration, settings) across async contexts.
/// We use 'nonisolated(unsafe)' for the NSCache because NSCache is internally thread-safe,
/// allowing us to access it synchronously without actor hops.
actor SharedMemoryCache {
    nonisolated static let shared = SharedMemoryCache()

    /// For Cache monitor
    /// 1. Isolated State
    /// Removed private memory cache - now using SharedMemoryCache.shared
    private let diskCache: DiskCacheManager
    // Cache statistics for monitoring (Actor specific, not shared)
    private var cacheMemory = 0
    private var cacheDisk = 0
    /// Note: cacheEvictions is now tracked by CacheDelegate and read from there
    private let _gridCost = OSAllocatedUnfairLock(initialState: 0)
    private let _gridCount = OSAllocatedUnfairLock(initialState: 0)
    /// Manual count/cost tracking for the main `memoryCache`, mirroring the
    /// grid-cache counters above. NSCache does not expose item count or current
    /// total cost via its public API, so we maintain these alongside every
    /// `setObject` / `removeAllObjects` / eviction-delegate call. Surfaced via
    /// `getMemoryCacheCount()` / `getMemoryCacheCurrentCost()` for the Memory
    /// Diagnostics console (and any future cache-monitor UI).
    private let _memCost = OSAllocatedUnfairLock(initialState: 0)
    private let _memCount = OSAllocatedUnfairLock(initialState: 0)

    // MARK: - Boomerang-miss diagnostics
    //
    // Three demand-traffic counters and a bounded FIFO of recently-evicted
    // URLs from `memoryCache`, used by the Memory Diagnostics view to compute
    // a true RAM hit rate (denominator = all demand requests, including cold
    // extractions) and detect scan-vs-UI cache pollution.
    //
    //   _cacheCold:        successful branch C extractions in RequestThumbnail
    //                      (not in RAM, not on disk → extracted from ARW source)
    //   _demandRequests:   total calls into RequestThumbnail.resolveImage
    //   _boomerangMisses:  branch B disk hits whose URL was just evicted from
    //                      RAM (a re-request the cache was supposed to serve)
    //
    // The ring is capacity-bounded (~2000 keys, ≈2× current peak _memCount) so
    // the boomerang signal reflects recent evictions only. Cleared on
    // `clearCaches()` and on `.critical` memory pressure to avoid spurious
    // hits after a wholesale flush.
    private let _cacheCold = OSAllocatedUnfairLock(initialState: 0)
    private let _demandRequests = OSAllocatedUnfairLock(initialState: 0)
    private let _boomerangMisses = OSAllocatedUnfairLock(initialState: 0)
    private let _evictedRing = OSAllocatedUnfairLock(initialState: EvictedRing())

    // MARK: - Pressure event counters
    //
    // Cumulative counts of memory-pressure transitions handled by
    // `handleMemoryPressureEvent`. The 5-second diagnostics sampler can miss
    // a `.warning → .normal` flicker — these counters can't, so a delta
    // between TSV samples reveals events even when `pressure` reads "Normal"
    // at both endpoints. `getLiveTotalCostLimit()` reads the NSCache's live
    // cost cap so transient shrinks (the warning case multiplies the cap by
    // 0.6 and waits for a `.normal` to restore it) become visible too.
    private let _pressureWarnings = OSAllocatedUnfairLock(initialState: 0)
    private let _pressureCriticals = OSAllocatedUnfairLock(initialState: 0)
    private let _pressureNormals = OSAllocatedUnfairLock(initialState: 0)

    // For Cache monitor

    // MARK: - Memory pressure level

    /// The kernel-reported memory pressure level.
    /// nonisolated(unsafe) so MemoryViewModel can read it synchronously on the main actor
    /// without an await. Only ever written from the DispatchSource event handler.
    enum MemoryPressureLevel {
        case normal, warning, critical

        var label: String {
            switch self {
            case .normal: "Normal"
            case .warning: "Warning"
            case .critical: "Critical"
            }
        }

        var systemImage: String {
            switch self {
            case .normal: "checkmark.circle.fill"
            case .warning: "exclamationmark.triangle.fill"
            case .critical: "xmark.octagon.fill"
            }
        }
    }

    private(set) nonisolated(unsafe) var currentPressureLevel: MemoryPressureLevel = .normal

    // MARK: - Non-Isolated State (Thread-Safe by design)

    /// NSCache is thread-safe, so we bypass the actor's serialization for direct access.
    /// This allows synchronous lookups: SharedMemoryCache.shared.object(...) (no await needed)
    nonisolated(unsafe) let memoryCache = NSCache<NSURL, CachedThumbnail>()

    /// Dedicated in-memory-only cache for grid-size (≤500px) thumbnails.
    /// Keyed by the same NSURL as memoryCache; never persisted to disk.
    nonisolated(unsafe) let gridThumbnailCache = NSCache<NSURL, CachedThumbnail>()

    // MARK: - Isolated State (Protected by Actor)

    private var _costPerPixel: Int = 4
    private var memoryPressureSource: DispatchSourceMemoryPressure?

    // MARK: - Get settings

    private var savedSettings: SavedSettings? // Kept for getCacheCostsAfterSettingsUpdate

    /// Only using the memory pressure warning
    private var fileHandlers: FileHandlers?

    /// Public access to the current cost per pixel setting.
    /// Since this is isolated state, reading it requires 'await'.
    var costPerPixel: Int {
        _costPerPixel
    }

    init(diskCache: DiskCacheManager? = nil) {
        self.diskCache = diskCache ?? DiskCacheManager()
        // Logger.process.debugMessageOnly("SharedMemoryCache: init() complete")
    }

    func setFileHandlers(_ fileHandlers: FileHandlers) {
        self.fileHandlers = fileHandlers
    }

    private var setupTask: Task<Void, Never>?

    /// Ensures settings are loaded and cache is configured before use.
    func ensureReady(config: CacheConfig? = nil) async {
        // If setup is already in progress (or done), just await it
        if let task = setupTask {
            return await task.value
        }

        // Capture config for the closure
        let capturedConfig = config

        let newTask = Task {
            // Start memory pressure monitoring
            self.startMemoryPressureMonitoring()

            // Logic to determine config
            let finalConfig: CacheConfig
            if let cfg = capturedConfig {
                finalConfig = cfg
            } else {
                let settings = await SettingsViewModel.shared.asyncgetsettings()
                finalConfig = self.calculateConfig(from: settings)
            }

            // Apply config
            self.applyConfig(finalConfig)
        }

        // Store immediately to prevent duplicate initialization
        setupTask = newTask

        await newTask.value
    }

    /// Helper to calculate configuration from settings.
    /// Nonisolated because it doesn't access actor state.
    ///
    /// Math:
    ///   `totalCostLimit     = memoryCacheSizeMB · 1024 · 1024`  (MiB → bytes)
    ///   `gridTotalCostLimit = gridCacheSizeMB   · 1024 · 1024`  (MiB → bytes)
    /// `countLimit` is deliberately set to a very high value (10 000) so the
    /// byte-budget is the binding constraint — NSCache applies `min(count, cost)`
    /// and we want cost to do the evicting, not item count.
    /// (The duplicate formula in `setCacheCostsFromSavedSettings` is intentional
    /// — that path predates `calculateConfig`; both use the same expression.)
    func calculateConfig(from settings: SavedSettings) -> CacheConfig {
        let thumbnailCostPerPixel = settings.thumbnailCostPerPixel // 4 default
        let memoryCacheSizeMB = settings.memoryCacheSizeMB // 5000 MB default  - 20,000 MB max

        // totalCostLimit is the PRIMARY memory constraint (based on allocated MB)
        // countLimit is set very high (10000) so memory, not item count, limits the cache
        // This allows ~500+ images at ~18MB each with default 10GB allocation
        let totalCostLimit = memoryCacheSizeMB * 1024 * 1024
        let countLimit = 10000 // Very high so totalCostLimit is the real constraint
        let gridTotalCostLimit = settings.gridCacheSizeMB * 1024 * 1024

        return CacheConfig(
            totalCostLimit: totalCostLimit,
            countLimit: countLimit,
            gridTotalCostLimit: gridTotalCostLimit,
            costPerPixel: thumbnailCostPerPixel,
        )
    }

    /// This function is executed as part of init, calculates new Cache Costs from
    /// saved settings.
    func setCacheCostsFromSavedSettings() async {
        savedSettings = await SettingsViewModel.shared.asyncgetsettings()
        if let settings = savedSettings {
            let thumbnailCostPerPixel = settings.thumbnailCostPerPixel // 4 default (RGBA bytes per pixel)
            let memoryCacheSizeMB = settings.memoryCacheSizeMB // 500MB default

            // totalCostLimit is the PRIMARY memory constraint (based on allocated MB)
            // countLimit is set very high (10000) so memory, not item count, limits the cache
            let totalCostLimit = memoryCacheSizeMB * 1024 * 1024
            let countLimit = 10000 // Very high so totalCostLimit is the real constraint
            let gridTotalCostLimit = settings.gridCacheSizeMB * 1024 * 1024

            let config = CacheConfig(
                totalCostLimit: totalCostLimit,
                countLimit: countLimit,
                gridTotalCostLimit: gridTotalCostLimit,
                costPerPixel: thumbnailCostPerPixel,
            )
            applyConfig(config)
        }
    }

    func getCacheCostsAfterSettingsUpdate() async -> CacheConfig? {
        guard let settings = savedSettings else { return nil }
        return calculateConfig(from: settings)
    }

    func setCostPerPixel(_ cost: Int) {
        _costPerPixel = cost
        // Logger.process.debugMessageOnly("SharedMemoryCache: setCostPerPixel(\(cost)) called (Local override only)",)
    }

    /// In SharedMemoryCache
    func refreshConfig() async {
        let settings = await SettingsViewModel.shared.asyncgetsettings()
        let config = calculateConfig(from: settings)
        applyConfig(config)
    }

    private func applyConfig(_ config: CacheConfig) {
        memoryCache.totalCostLimit = config.totalCostLimit
        memoryCache.countLimit = config.countLimit
        // `evictsObjectsWithDiscardedContent` only applies to NSDiscardableContent
        // values; CachedThumbnail no longer adopts that protocol, so the setting
        // would be a no-op. Eviction is driven by totalCostLimit / countLimit and
        // the explicit `handleMemoryPressureEvent` handler.
        memoryCache.delegate = CacheDelegate.shared
        if let costPerPixel = config.costPerPixel {
            _costPerPixel = costPerPixel
        }
        gridThumbnailCache.totalCostLimit = config.gridTotalCostLimit
        gridThumbnailCache.countLimit = 3000
        gridThumbnailCache.delegate = CacheDelegate.shared
        // let totalCostMB = config.totalCostLimit / (1024 * 1024)

        /*
                Logger.process.debugMessageOnly(
                    "CACHE CONFIG APPLIED: " +
                        "totalCostLimit=\(config.totalCostLimit) bytes (\(totalCostMB) MB), " +
                        "countLimit=\(config.countLimit) items (memory-limited, not item-count limited)",
                )
         */
    }

    // MARK: - Memory Pressure Monitoring

    private func startMemoryPressureMonitoring() {
        // Avoid duplicate sources
        if memoryPressureSource != nil {
            return
        }

        // Logger.process.debugMessageOnly( "SharedMemoryCache: startMemoryPressureMonitoring()",)

        let source = DispatchSource.makeMemoryPressureSource(eventMask: .all, queue: .global(qos: .utility))

        source.setEventHandler { [weak self] in
            guard let self else { return }
            Task {
                await self.handleMemoryPressureEvent()
            }
        }

        source.setCancelHandler { [weak self] in
            guard let self else { return }
            Task {
                await self.logMemoryPressure("Memory pressure monitoring cancelled")
            }
        }

        source.resume()
        memoryPressureSource = source
        // Logger.process.debugMessageOnly("SharedMemoryCache: Memory pressure monitoring started")
    }

    /// Responds to kernel-reported memory-pressure transitions:
    ///   • `.normal`    → reload the full `CacheConfig` from settings (restore caps).
    ///   • `.warning`   → shrink both caches in place: `newCap = currentCap · 0.6`.
    ///                    Existing entries are retained until NSCache evicts under
    ///                    the lower cap, avoiding a full cache flush.
    ///   • `.critical`  → `removeAllObjects()` on both caches and floor the main
    ///                    cache at 50 MiB (50 · 1024 · 1024 bytes) until recovery.
    private func handleMemoryPressureEvent() {
        guard let source = memoryPressureSource else { return }

        let pressureLevel = source.data

        switch pressureLevel {
        case .normal:
            currentPressureLevel = .normal
            _pressureNormals.withLock { $0 += 1 }
            logMemoryPressure("Normal memory pressure")
            Task {
                await self.refreshConfig()
                await fileHandlers?.memorypressurewarning(false)
            }

        case .warning:
            currentPressureLevel = .warning
            _pressureWarnings.withLock { $0 += 1 }
            logMemoryPressure("Warning: Memory pressure detected, reducing cache to 60%")
            let reducedCost = Int(Double(memoryCache.totalCostLimit) * 0.6)
            memoryCache.totalCostLimit = reducedCost
            gridThumbnailCache.totalCostLimit = Int(Double(gridThumbnailCache.totalCostLimit) * 0.6)
            Task {
                await fileHandlers?.memorypressurewarning(true)
            }

        case .critical:
            currentPressureLevel = .critical
            _pressureCriticals.withLock { $0 += 1 }
            logMemoryPressure("CRITICAL: Memory pressure critical, clearing cache")
            memoryCache.removeAllObjects()
            memoryCache.totalCostLimit = 50 * 1024 * 1024 // 50MB minimum
            _memCost.withLock { $0 = 0 }
            _memCount.withLock { $0 = 0 }
            gridThumbnailCache.removeAllObjects()
            _gridCost.withLock { $0 = 0 }
            _gridCount.withLock { $0 = 0 }
            // Wholesale flush invalidates per-URL eviction tracking; otherwise
            // every subsequent disk-fallback would falsely register as a
            // boomerang. Demand counters intentionally NOT reset.
            _evictedRing.withLock { $0.clear() }
            Task {
                await fileHandlers?.memorypressurewarning(true)
            }

        default:
            logMemoryPressure("Unknown memory pressure event: \(pressureLevel.rawValue)")
        }
    }

    private func logMemoryPressure(_: String) {
        // Logger.process.debugMessageOnly("SharedMemoryCache: \(message)")
    }

    // MARK: - Synchronous Accessors (Non-isolated)

    nonisolated func object(forKey key: NSURL) -> CachedThumbnail? {
        memoryCache.object(forKey: key)
    }

    nonisolated func setObject(_ obj: CachedThumbnail, forKey key: NSURL, cost: Int) {
        memoryCache.setObject(obj, forKey: key, cost: cost)
        _memCost.withLock { $0 += cost }
        _memCount.withLock { $0 += 1 }
    }

    nonisolated func removeAllObjects() {
        memoryCache.removeAllObjects()
        _memCost.withLock { $0 = 0 }
        _memCount.withLock { $0 = 0 }
    }

    nonisolated func getMemoryCacheCurrentCost() -> Int {
        _memCost.withLock { $0 }
    }

    nonisolated func getMemoryCacheCount() -> Int {
        _memCount.withLock { $0 }
    }

    nonisolated func memEntryEvicted(cost: Int) {
        _memCost.withLock { $0 = max(0, $0 - cost) }
        _memCount.withLock { $0 = max(0, $0 - 1) }
    }

    nonisolated func gridObject(forKey key: NSURL) -> CachedThumbnail? {
        gridThumbnailCache.object(forKey: key)
    }

    nonisolated func setGridObject(_ obj: CachedThumbnail, forKey key: NSURL, cost: Int) {
        gridThumbnailCache.setObject(obj, forKey: key, cost: cost)
        _gridCost.withLock { $0 += cost }
        _gridCount.withLock { $0 += 1 }
    }

    nonisolated func removeAllGridObjects() {
        gridThumbnailCache.removeAllObjects()
        _gridCost.withLock { $0 = 0 }
        _gridCount.withLock { $0 = 0 }
    }

    nonisolated func getGridCacheCurrentCost() -> Int {
        _gridCost.withLock { $0 }
    }

    nonisolated func getGridCacheCount() -> Int {
        _gridCount.withLock { $0 }
    }

    nonisolated func gridEntryEvicted(cost: Int) {
        _gridCost.withLock { $0 = max(0, $0 - cost) }
        _gridCount.withLock { $0 = max(0, $0 - 1) }
    }

    // MARK: - Boomerang-miss helpers

    nonisolated func noteEviction(url: NSURL) {
        _evictedRing.withLock { $0.note(url) }
    }

    nonisolated func wasRecentlyEvicted(url: NSURL) -> Bool {
        _evictedRing.withLock { $0.contains(url) }
    }

    nonisolated func incrementColdExtract() {
        _cacheCold.withLock { $0 += 1 }
    }

    nonisolated func incrementDemandRequest() {
        _demandRequests.withLock { $0 += 1 }
    }

    nonisolated func incrementBoomerangMiss() {
        _boomerangMisses.withLock { $0 += 1 }
    }

    nonisolated func getColdExtractCount() -> Int {
        _cacheCold.withLock { $0 }
    }

    nonisolated func getDemandRequestCount() -> Int {
        _demandRequests.withLock { $0 }
    }

    nonisolated func getBoomerangMissCount() -> Int {
        _boomerangMisses.withLock { $0 }
    }

    // MARK: - Pressure event getters

    nonisolated func getPressureWarningCount() -> Int {
        _pressureWarnings.withLock { $0 }
    }

    nonisolated func getPressureCriticalCount() -> Int {
        _pressureCriticals.withLock { $0 }
    }

    nonisolated func getPressureNormalCount() -> Int {
        _pressureNormals.withLock { $0 }
    }

    /// Live total-cost cap on `memoryCache`. Reads NSCache directly (the
    /// property is thread-safe), so it reflects in-flight pressure-handler
    /// shrinks before `.normal` has fired to restore the configured value.
    nonisolated func getLiveTotalCostLimit() -> Int {
        memoryCache.totalCostLimit
    }

    /// For Cache monitor
    /// Get current cache statistics for monitoring
    func getCacheStatistics() async -> CacheStatistics {
        await ensureReady()
        let total = cacheMemory + cacheDisk
        let hitRate = total > 0 ? Double(cacheMemory) / Double(total) * 100 : 0
        let evictions = CacheDelegate.shared.getEvictionCount()
        return CacheStatistics(
            hits: cacheMemory,
            misses: cacheDisk,
            evictions: evictions,
            hitRate: hitRate,
        )
    }

    func getDiskCacheSize() async -> Int {
        await diskCache.getDiskCacheSize()
    }

    func pruneDiskCache(maxAgeInDays: Int = 30) async {
        await diskCache.pruneCache(maxAgeInDays: maxAgeInDays)
    }

    func clearCaches() async {
        // let hitRate = cacheMemory + cacheDisk > 0 ? Double(cacheMemory) / Double(cacheMemory + cacheDisk) * 100 : 0
        // let hitRateStr = String(format: "%.1f", hitRate)
        // Logger.process.info("Cache Statistics - Hits: \(self.cacheMemory), Misses: \(self.cacheDisk), Hit Rate: \(hitRateStr)%")

        SharedMemoryCache.shared.removeAllObjects()
        SharedMemoryCache.shared.removeAllGridObjects()

        await diskCache.pruneCache(maxAgeInDays: 0)

        // Reset statistics
        cacheMemory = 0
        cacheDisk = 0
        _memCost.withLock { $0 = 0 }
        _memCount.withLock { $0 = 0 }
        _gridCost.withLock { $0 = 0 }
        _gridCount.withLock { $0 = 0 }
        _cacheCold.withLock { $0 = 0 }
        _demandRequests.withLock { $0 = 0 }
        _boomerangMisses.withLock { $0 = 0 }
        _evictedRing.withLock { $0.clear() }
        _pressureWarnings.withLock { $0 = 0 }
        _pressureCriticals.withLock { $0 = 0 }
        _pressureNormals.withLock { $0 = 0 }
        CacheDelegate.shared.resetEvictionCount()
    }

    func updateCacheMemory() async {
        cacheMemory += 1
        // Logger.process.debugThreadOnly("SharedMemoryCache: updateCacheMemory() - found in RAM Cache (hits: \(cacheMemory))")
    }

    func updateCacheDisk() async {
        cacheDisk += 1
        // Logger.process.debugThreadOnly("SharedMemoryCache: updateCacheDisk() - found in Disk Cache (hits: \(cacheDisk))")
    }
}

/// Bounded FIFO of recently-evicted NSURLs from the main `memoryCache`.
/// Backing storage is a fixed-size array used as a ring (O(1) insert) plus a
/// `Set` mirror for O(1) membership tests. Always accessed under
/// `SharedMemoryCache._evictedRing`'s unfair lock — the struct itself
/// performs no synchronization.
///
/// All members are `nonisolated` because the project sets
/// `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`; this struct is constructed
/// and mutated from the actor's own isolation domain (and from
/// `CacheDelegate`'s nonisolated callback), neither of which is MainActor.
fileprivate struct EvictedRing: Sendable {
    nonisolated static let capacity = 2000

    private var buffer: [NSURL?]
    private var set: Set<NSURL>
    private var cursor: Int

    nonisolated init() {
        buffer = Array(repeating: nil, count: Self.capacity)
        set = Set(minimumCapacity: Self.capacity)
        cursor = 0
    }

    nonisolated mutating func note(_ url: NSURL) {
        if let old = buffer[cursor] {
            set.remove(old)
        }
        buffer[cursor] = url
        set.insert(url)
        cursor = (cursor + 1) % Self.capacity
    }

    nonisolated func contains(_ url: NSURL) -> Bool {
        set.contains(url)
    }

    nonisolated mutating func clear() {
        for i in 0..<buffer.count { buffer[i] = nil }
        set.removeAll(keepingCapacity: true)
        cursor = 0
    }
}
