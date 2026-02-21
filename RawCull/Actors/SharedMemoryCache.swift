//
//  SharedMemoryCache.swift
//  RawCull
//
//  Created by Thomas Evensen on 11/02/2026.
//

import AppKit
import Dispatch
import Foundation
import OSLog

/// A thread-safe singleton wrapper around the shared NSCache.
/// We use 'actor' to safely manage state (configuration, settings) across async contexts.
/// We use 'nonisolated(unsafe)' for the NSCache because NSCache is internally thread-safe,
/// allowing us to access it synchronously without actor hops.
actor SharedMemoryCache {
    nonisolated static let shared = SharedMemoryCache()
    
    
    /// For Cache monitor
    // 1. Isolated State
    // Removed private memory cache - now using SharedMemoryCache.shared
    private var successCount = 0
    private let diskCache: DiskCacheManager
    // Cache statistics for monitoring (Actor specific, not shared)
    private var cacheMemory = 0
    private var cacheDisk = 0
    // Note: cacheEvictions is now tracked by CacheDelegate and read from there
    /// For Cache monitor

    // MARK: - Non-Isolated State (Thread-Safe by design)

    /// NSCache is thread-safe, so we bypass the actor's serialization for direct access.
    /// This allows synchronous lookups: SharedMemoryCache.shared.object(...) (no await needed)
    nonisolated(unsafe) let memoryCache = NSCache<NSURL, DiscardableThumbnail>()

    // MARK: - Isolated State (Protected by Actor)

    private var _costPerPixel: Int = 4
    private var isConfigured = false
    private var memoryPressureSource: DispatchSourceMemoryPressure?
    private var currentMemoryPressure: DispatchSource.MemoryPressureEvent = .normal

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
        Logger.process.debugMessageOnly("SharedMemoryCache: init() complete (pending setup)")
    }

    func setFileHandlers(_ fileHandlers: FileHandlers) {
        self.fileHandlers = fileHandlers
    }

    /// Ensures settings are loaded and cache is configured before use.
    func ensureReady(config: CacheConfig? = nil) async {
        // Fast path: check if already configured
        if isConfigured {
            return
        }

        // Start memory pressure monitoring
        startMemoryPressureMonitoring()

        // Logic to determine config
        let finalConfig: CacheConfig
        if let config = config {
            finalConfig = config
        } else {
            // Calculate from saved settings
            // This is an await call, which is safe inside the actor
            let settings = await SettingsViewModel.shared.asyncgetsettings()
            finalConfig = calculateConfig(from: settings)
        }

        // Apply config
        // We can access 'memoryCache' directly here even though it is nonisolated(unsafe),
        // because we are setting up the limits.
        applyConfig(finalConfig)
        isConfigured = true
    }

    /// Helper to calculate configuration from settings.
    /// Nonisolated because it doesn't access actor state.
    func calculateConfig(from settings: SavedSettings) -> CacheConfig {
        let thumbnailCostPerPixel = settings.thumbnailCostPerPixel // 4 default
        let memoryCacheSizeMB = settings.memoryCacheSizeMB // 5000 MB default  - 20,000 MB max

        // totalCostLimit is the PRIMARY memory constraint (based on allocated MB)
        // countLimit is set very high (10000) so memory, not item count, limits the cache
        // This allows ~500+ images at ~18MB each with default 10GB allocation
        let totalCostLimit = memoryCacheSizeMB * 1024 * 1024
        let countLimit = 10000 // Very high so totalCostLimit is the real constraint

        return CacheConfig(
            totalCostLimit: totalCostLimit,
            countLimit: countLimit,
            costPerPixel: thumbnailCostPerPixel
        )
    }

    /// This function is executed as part of init, calculates new Cache Costs from
    /// saved settingd.
    func setCacheCostsFromSavedSettings() async {
        savedSettings = await SettingsViewModel.shared.asyncgetsettings()
        if let settings = savedSettings {
            let thumbnailCostPerPixel = settings.thumbnailCostPerPixel // 4 default (RGBA bytes per pixel)
            let memoryCacheSizeMB = settings.memoryCacheSizeMB // 500MB default

            // totalCostLimit is the PRIMARY memory constraint (based on allocated MB)
            // countLimit is set very high (10000) so memory, not item count, limits the cache
            let totalCostLimit = memoryCacheSizeMB * 1024 * 1024
            let countLimit = 10000 // Very high so totalCostLimit is the real constraint

            let config = CacheConfig(
                totalCostLimit: totalCostLimit,
                countLimit: countLimit,
                costPerPixel: thumbnailCostPerPixel
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
        Logger.process.debugMessageOnly(
            "SharedMemoryCache: setCostPerPixel(\(cost)) called (Local override only)"
        )
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
        memoryCache.delegate = CacheDelegate.shared
        if let costPerPixel = config.costPerPixel {
            _costPerPixel = costPerPixel
        }

        let totalCostMB = config.totalCostLimit / (1024 * 1024)

        Logger.process.debugMessageOnly(
            "CACHE CONFIG APPLIED: " +
                "totalCostLimit=\(config.totalCostLimit) bytes (\(totalCostMB) MB), " +
                "countLimit=\(config.countLimit) items (memory-limited, not item-count limited)"
        )
    }

    // MARK: - Memory Pressure Monitoring

    private func startMemoryPressureMonitoring() {
        // Avoid duplicate sources
        if memoryPressureSource != nil {
            return
        }

        Logger.process.debugMessageOnly(
            "SharedMemoryCache: startMemoryPressureMonitoring()"
        )

        let source = DispatchSource.makeMemoryPressureSource(eventMask: .all, queue: .global(qos: .utility))

        source.setEventHandler { [weak self] in
            Task.detached(priority: .high) { [weak self] in
                await self?.handleMemoryPressureEvent()
            }
        }

        source.setCancelHandler { [weak self] in
            Task.detached(priority: .high) { [weak self] in
                await self?.logMemoryPressure("Memory pressure monitoring cancelled")
            }
        }

        source.resume()
        memoryPressureSource = source
        Logger.process.debugMessageOnly("SharedMemoryCache: Memory pressure monitoring started")
    }

    private func handleMemoryPressureEvent() {
        guard let source = memoryPressureSource else { return }

        let pressureLevel = source.data
        currentMemoryPressure = pressureLevel

        switch pressureLevel {
        case .normal:
            logMemoryPressure("Normal memory pressure")
            Task {
                await fileHandlers?.memorypressurewarning(false)
            }

            // Cache can operate at full capacity

        case .warning:
            logMemoryPressure("Warning: Memory pressure detected, reducing cache to 60%")
            // Reduce cache size to 60% of limit
            let reducedCost = Int(Double(memoryCache.totalCostLimit) * 0.6)
            memoryCache.totalCostLimit = reducedCost
            Task {
                await fileHandlers?.memorypressurewarning(true)
            }

        case .critical:
            logMemoryPressure("CRITICAL: Memory pressure critical, clearing cache")
            // Clear cache immediately
            memoryCache.removeAllObjects()
            // Set minimal limit
            memoryCache.totalCostLimit = 50 * 1024 * 1024 // 50MB minimum
            Task {
                await fileHandlers?.memorypressurewarning(true)
            }

        default:
            logMemoryPressure("Unknown memory pressure event: \(pressureLevel.rawValue)")
        }
    }

    private func logMemoryPressure(_ message: String) {
        Logger.process.debugMessageOnly("SharedMemoryCache: \(message)")
    }

    /// Stops memory pressure monitoring and cleans up the dispatch source.
    func stopMemoryPressureMonitoring() {
        if let source = memoryPressureSource {
            source.cancel()
            memoryPressureSource = nil
            Logger.process.debugMessageOnly("SharedMemoryCache: Memory pressure monitoring stopped")
        }
    }

    /// Returns the current memory pressure level.
    var memoryPressure: DispatchSource.MemoryPressureEvent {
        currentMemoryPressure
    }

    // MARK: - Synchronous Accessors (Non-isolated)

    nonisolated func object(forKey key: NSURL) -> DiscardableThumbnail? {
        memoryCache.object(forKey: key)
    }

    nonisolated func setObject(_ obj: DiscardableThumbnail, forKey key: NSURL, cost: Int) {
        memoryCache.setObject(obj, forKey: key, cost: cost)
    }

    nonisolated func removeAllObjects() {
        memoryCache.removeAllObjects()
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
            hitRate: hitRate
        )
    }

    func getDiskCacheSize() async -> Int {
        await diskCache.getDiskCacheSize()
    }

    func pruneDiskCache(maxAgeInDays: Int = 30) async {
        await diskCache.pruneCache(maxAgeInDays: maxAgeInDays)
    }

    func clearCaches() async {
        let hitRate = cacheMemory + cacheDisk > 0 ? Double(cacheMemory) / Double(cacheMemory + cacheDisk) * 100 : 0
        let hitRateStr = String(format: "%.1f", hitRate)
        Logger.process.info("Cache Statistics - Hits: \(self.cacheMemory), Misses: \(self.cacheDisk), Hit Rate: \(hitRateStr)%")

        // Clear Shared Memory Cache
        SharedMemoryCache.shared.removeAllObjects()

        await diskCache.pruneCache(maxAgeInDays: 0)

        // Reset statistics
        cacheMemory = 0
        cacheDisk = 0
        CacheDelegate.shared.resetEvictionCount()
    }
    
    func updateCacheMemory() async {
        cacheMemory += 1
        Logger.process.debugThreadOnly("RequestThumbnail: resolveImage() - found in RAM Cache (hits: \(cacheMemory))")
    }
    
    func upadateCacheDisk() async {
        cacheDisk += 1
        Logger.process.debugThreadOnly("RequestThumbnail: resolveImage() - found in RAM Cache (hits: \(cacheDisk))")
        
    }
}
