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

    private let diskCache: DiskCacheManager
    private let fullSizeJPGCache: FullSizeJPGDiskCache
    private let tracksEvictions: Bool
    private let _gridCost = OSAllocatedUnfairLock(initialState: 0)
    private let _gridCount = OSAllocatedUnfairLock(initialState: 0)
    /// Manual count/cost tracking for the main `memoryCache`, mirroring the
    /// grid-cache counters above. NSCache does not expose item count or current
    /// total cost via its public API, so we maintain these alongside every
    /// `setObject` / `removeAllObjects` / eviction-delegate call. Surfaced via
    /// `getMemoryCacheCount()` / `getMemoryCacheCurrentCost()` for Settings.
    private let _memCost = OSAllocatedUnfairLock(initialState: 0)
    private let _memCount = OSAllocatedUnfairLock(initialState: 0)

    // MARK: - Memory pressure level

    /// The kernel-reported memory pressure level.
    enum MemoryPressureLevel: Equatable {
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
    private let _currentPressureLevel = OSAllocatedUnfairLock(
        initialState: MemoryPressureLevel.normal,
    )

    nonisolated var currentPressureLevel: MemoryPressureLevel {
        _currentPressureLevel.withLock { $0 }
    }

    private func setCurrentPressureLevel(_ level: MemoryPressureLevel) {
        _currentPressureLevel.withLock { $0 = level }
    }

    // MARK: - Non-Isolated State (Thread-Safe by design)

    /// NSCache is thread-safe, so we bypass the actor's serialization for direct access.
    /// This allows synchronous lookups: SharedMemoryCache.shared.object(...) (no await needed)
    nonisolated(unsafe) let memoryCache = NSCache<NSString, CachedThumbnail>()

    /// Dedicated in-memory-only cache for grid-size (≤500px) thumbnails.
    /// Uses the same representation-aware identity as the persistent cache.
    nonisolated(unsafe) let gridThumbnailCache = NSCache<NSString, CachedThumbnail>()

    /// Bytes per pixel used by `CachedThumbnail` to compute NSCache cost.
    /// Fixed at 4 (RGBA) — NSImage representations are always sRGB RGBA in
    /// this app, so the cost calculation has no reason to vary at runtime.
    /// `nonisolated let` lets call sites read it without `await`.
    nonisolated let costPerPixel: Int = 4

    // MARK: - Isolated State (Protected by Actor)

    private var memoryPressureSource: DispatchSourceMemoryPressure?

    /// Only using the memory pressure warning
    private var fileHandlers: FileHandlers?

    init(
        diskCache: DiskCacheManager? = nil,
        fullSizeJPGCache: FullSizeJPGDiskCache? = nil,
        tracksEvictions: Bool = true,
    ) {
        self.diskCache = diskCache ?? DiskCacheManager()
        self.fullSizeJPGCache = fullSizeJPGCache ?? FullSizeJPGDiskCache()
        self.tracksEvictions = tracksEvictions
        // Logger.process.debugMessageOnly("SharedMemoryCache: init() complete")
    }

    /// Exposed so `ZoomPreviewHandler` can reuse the singleton actor for
    /// `load`/`save` without creating its own instance — keeps a single
    /// owner of the cache directory and lets the Cache settings tab call
    /// into the same actor for size/prune.
    nonisolated var fullSizeJPGDiskCache: FullSizeJPGDiskCache {
        fullSizeJPGCache
    }

    nonisolated var thumbnailDiskCacheDirectory: URL {
        diskCache.cacheDirectory
    }

    nonisolated var fullSizeJPGDiskCacheDirectory: URL {
        fullSizeJPGCache.cacheDirectory
    }

    func setFileHandlers(_ fileHandlers: FileHandlers) {
        self.fileHandlers = fileHandlers
    }

    private var setupTask: Task<Void, Never>?

    /// Ensures settings are loaded and cache is configured before use.
    func ensureReady(config: CacheConfig? = nil) async {
        if let config, setupTask != nil {
            await setupTask?.value
            applyConfig(config)
            return
        }

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
    func calculateConfig(from settings: SavedSettings) -> CacheConfig {
        let limits = CacheRecommendationPolicy.adaptiveLimits(
            physicalMemoryBytes: ProcessInfo.processInfo.physicalMemory,
            usedMemoryBytes: Self.usedSystemMemoryBytes(),
            userPreviewMaxMB: settings.memoryCacheSizeMB,
            userGridMaxMB: settings.gridCacheSizeMB,
            pressureLevel: currentPressureLevel,
        )

        // totalCostLimit is the PRIMARY memory constraint (based on allocated MB)
        // countLimit is set very high (10000) so memory, not item count, limits the cache
        let totalCostLimit = limits.previewMB * CacheRecommendationPolicy.megabyte
        let countLimit = 10000 // Very high so totalCostLimit is the real constraint
        let gridTotalCostLimit = limits.gridMB * CacheRecommendationPolicy.megabyte

        return CacheConfig(
            totalCostLimit: totalCostLimit,
            countLimit: countLimit,
            gridTotalCostLimit: gridTotalCostLimit,
        )
    }

    private nonisolated static func usedSystemMemoryBytes() -> UInt64 {
        let total = ProcessInfo.processInfo.physicalMemory
        var stat = vm_statistics64()
        var count = mach_msg_type_number_t(
            MemoryLayout<vm_statistics64>.size / MemoryLayout<integer_t>.size,
        )

        let result = withUnsafeMutablePointer(to: &stat) {
            $0.withMemoryRebound(to: integer_t.self, capacity: 1) {
                host_statistics64(mach_host_self(), HOST_VM_INFO64, $0, &count)
            }
        }

        guard result == KERN_SUCCESS else { return 0 }

        let pageSize = UInt64(getpagesize())
        let wired = UInt64(stat.wire_count)
        let active = UInt64(stat.active_count)
        let compressed = UInt64(stat.compressor_page_count)
        return min((wired + active + compressed) * pageSize, total)
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
        memoryCache.delegate = tracksEvictions ? CacheDelegate.shared : nil
        gridThumbnailCache.totalCostLimit = config.gridTotalCostLimit
        gridThumbnailCache.countLimit = 3000
        gridThumbnailCache.delegate = tracksEvictions ? CacheDelegate.shared : nil
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
            setCurrentPressureLevel(.normal)
            logMemoryPressure("Normal memory pressure")
            Task {
                await self.refreshConfig()
                await fileHandlers?.memorypressurewarning(false)
            }

        case .warning:
            setCurrentPressureLevel(.warning)
            logMemoryPressure("Warning: Memory pressure detected, reducing cache to 60%")
            let reducedCost = Int(Double(memoryCache.totalCostLimit) * 0.6)
            memoryCache.totalCostLimit = reducedCost
            gridThumbnailCache.totalCostLimit = Int(Double(gridThumbnailCache.totalCostLimit) * 0.6)
            Task {
                await fileHandlers?.memorypressurewarning(true)
            }

        case .critical:
            setCurrentPressureLevel(.critical)
            logMemoryPressure("CRITICAL: Memory pressure critical, clearing cache")
            memoryCache.removeAllObjects()
            memoryCache.totalCostLimit = 50 * 1024 * 1024 // 50MB minimum
            _memCost.withLock { $0 = 0 }
            _memCount.withLock { $0 = 0 }
            gridThumbnailCache.removeAllObjects()
            _gridCost.withLock { $0 = 0 }
            _gridCount.withLock { $0 = 0 }
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

    nonisolated func object(forKey key: ThumbnailCacheKey) -> CachedThumbnail? {
        memoryCache.object(forKey: key.memoryCacheKey)
    }

    nonisolated func setObject(_ obj: CachedThumbnail, forKey key: ThumbnailCacheKey, cost: Int) {
        let memoryKey = key.memoryCacheKey
        if let existing = memoryCache.object(forKey: memoryKey) {
            _memCost.withLock { $0 = max(0, $0 - existing.cost) }
            _memCount.withLock { $0 = max(0, $0 - 1) }
        }
        memoryCache.setObject(obj, forKey: memoryKey, cost: cost)
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

    nonisolated func gridObject(forKey key: ThumbnailCacheKey) -> CachedThumbnail? {
        gridThumbnailCache.object(forKey: key.memoryCacheKey)
    }

    nonisolated func setGridObject(_ obj: CachedThumbnail, forKey key: ThumbnailCacheKey, cost: Int) {
        let memoryKey = key.memoryCacheKey
        if let existing = gridThumbnailCache.object(forKey: memoryKey) {
            _gridCost.withLock { $0 = max(0, $0 - existing.cost) }
            _gridCount.withLock { $0 = max(0, $0 - 1) }
        }
        gridThumbnailCache.setObject(obj, forKey: memoryKey, cost: cost)
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

    func getDiskCacheSize() async -> Int {
        await diskCache.getDiskCacheSize()
    }

    func pruneDiskCache(maxAgeInDays: Int = 30) async {
        await diskCache.pruneCache(maxAgeInDays: maxAgeInDays)
    }

    func getFullSizeJPGCacheSize() async -> Int {
        await fullSizeJPGCache.getDiskCacheSize()
    }

    func pruneFullSizeJPGCache(maxAgeInDays: Int = 30) async {
        await fullSizeJPGCache.pruneCache(maxAgeInDays: maxAgeInDays)
    }

    func clearCaches() async {
        removeAllObjects()
        removeAllGridObjects()

        await diskCache.pruneCache(maxAgeInDays: 0)
        await fullSizeJPGCache.pruneCache(maxAgeInDays: 0)

        _memCost.withLock { $0 = 0 }
        _memCount.withLock { $0 = 0 }
        _gridCost.withLock { $0 = 0 }
        _gridCount.withLock { $0 = 0 }
    }

    #if DEBUG
        func resetForTesting(config: CacheConfig? = nil) async {
            setupTask = nil
            fileHandlers = nil
            if memoryPressureSource != nil {
                memoryPressureSource?.cancel()
                memoryPressureSource = nil
            }
            await clearCaches()
            if let config {
                applyConfig(config)
                setupTask = Task {}
            }
        }
    #endif
}
