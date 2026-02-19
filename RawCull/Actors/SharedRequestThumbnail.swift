//
//  SharedRequestThumbnail.swift
//  RawCull
//
//  Created by Thomas Evensen on 11/02/2026.
//

import AppKit
import Foundation
import OSLog

//
//  ThumbnailError.swift
//  RawCull
//

enum ThumbnailError: Error, LocalizedError {
    case invalidSource
    case generationFailed
    case contextCreationFailed

    var errorDescription: String? {
        switch self {
        case .invalidSource:
            return "Could not create an image source from the provided URL."

        case .generationFailed:
            return "Failed to generate or render the thumbnail image."

        case .contextCreationFailed:
            return "Failed to create a CGContext for thumbnail re-rendering."
        }
    }
}

actor SharedRequestThumbnail {
    nonisolated static let shared = SharedRequestThumbnail()

    // 1. Isolated State
    // Removed private memory cache - now using SharedMemoryCache.shared
    private var successCount = 0
    private let diskCache: DiskCacheManager

    // Cache statistics for monitoring (Actor specific, not shared)
    private var cacheMemory = 0
    private var cacheDisk = 0
    // Note: cacheEvictions is now tracked by CacheDelegate and read from there

    /// Ensures settings are loaded before any work starts
    private var setupTask: Task<Void, Never>?

    init(
        config _: CacheConfig? = nil,
        diskCache: DiskCacheManager? = nil
    ) {
        self.diskCache = diskCache ?? DiskCacheManager()
        Logger.process.debugMessageOnly("RequestThumbnail: init() complete (pending setup)")
    }

    /// 3. The magic helper: Creates the task if it doesn't exist, then awaits it.
    private func ensureReady() async {
        if let task = setupTask {
            return await task.value
        }

        let newTask = Task {
            // Delegating to the shared cache manager
            await SharedMemoryCache.shared.ensureReady()
        }

        self.setupTask = newTask
        await newTask.value
    }

    func requestthumbnail(for url: URL, targetSize: Int) async -> CGImage? {
        await ensureReady()
        do {
            return try await resolveImage(for: url, targetSize: targetSize)
        } catch {
            Logger.process.warning("Failed to resolve thumbnail: \(error)")
            return nil
        }
    }

    private func resolveImage(for url: URL, targetSize: Int) async throws -> CGImage {
        let nsUrl = url as NSURL

        // A. Check RAM (Using Shared Cache)
        if let wrapper = SharedMemoryCache.shared.object(forKey: nsUrl), wrapper.beginContentAccess() {
            defer { wrapper.endContentAccess() }
            cacheMemory += 1
            Logger.process.debugThreadOnly("RequestThumbnail: resolveImage() - found in RAM Cache (hits: \(cacheMemory))")
            let nsImage = wrapper.image
            return try nsImageToCGImage(nsImage)
        }

        // B. Check Disk
        if let diskImage = await diskCache.load(for: url) {
            await storeInMemory(diskImage, for: url)
            cacheDisk += 1
            Logger.process.debugThreadOnly("RequestThumbnail: resolveImage() - found in Disk Cache (misses: \(cacheDisk))")
            return try nsImageToCGImage(diskImage)
        }

        // C. Extract
        Logger.process.debugThreadOnly("RequestThumbnail: resolveImage() - no cache hit, CREATING thumbnail")

        // New (Actor safe access):
        // We need 'await' here because we are reading the protected '_costPerPixel' property.
        let costPerPixel = await SharedMemoryCache.shared.costPerPixel

        let cgImage = try await enumExtractSonyThumbnail.extractSonyThumbnail(
            from: url,
            maxDimension: CGFloat(targetSize),
            qualityCost: costPerPixel
        )

        let image = NSImage(cgImage: cgImage, size: NSSize(width: cgImage.width, height: cgImage.height))

        await storeInMemory(image, for: url)

        // 3. Background save
        Task.detached(priority: .background) { [cgImage] in
            await self.diskCache.save(cgImage, for: url)
        }

        return cgImage
    }

    /// Convert NSImage to CGImage for Sendable transport
    private func nsImageToCGImage(_ nsImage: NSImage) throws -> CGImage {
        guard let tiffData = nsImage.tiffRepresentation,
              let bitmapRep = NSBitmapImageRep(data: tiffData),
              let cgImage = bitmapRep.cgImage
        else {
            throw ThumbnailError.generationFailed
        }
        return cgImage
    }

    private func storeInMemory(_ image: NSImage, for url: URL) async {
        let costPerPixel = await SharedMemoryCache.shared.costPerPixel
        let wrapper = DiscardableThumbnail(image: image, costPerPixel: costPerPixel)
        SharedMemoryCache.shared.setObject(wrapper, forKey: url as NSURL, cost: wrapper.cost)
    }

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
}
