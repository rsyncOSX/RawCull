//
//  ScanAndCreateThumbnails.swift
//  RawCull
//
//  Created by Thomas Evensen on 24/01/2026.
//

import AppKit
import Foundation
import OSLog

actor ScanAndCreateThumbnails {
    // 1. Isolated State
    // Memory cache removed, using SharedMemoryCache.shared
    private var successCount = 0
    private let diskCache: DiskCacheManager

    // Cache statistics for monitoring
    private var cacheMemory = 0
    private var cacheDisk = 0

    // Timing tracking
    private var processingTimes: [TimeInterval] = []
    private var totalFilesToProcess = 0
    private var estimationStartIndex = 10

    private var preloadTask: Task<Int, Never>?
    private var fileHandlers: FileHandlers?

    private var savedsettings: SavedSettings? // Kept for getCacheCostsAfterSettingsUpdate
    private var setupTask: Task<Void, Never>?

    /// Cached cost per pixel to avoid recomputation
    private var cachedCostPerPixel: Int?
    /// Used in time remaining
    private var lastItemTime: Date?
    private var lastEstimatedSeconds: Int?

    init(
        config _: CacheConfig? = nil,
        diskCache: DiskCacheManager? = nil
    ) {
        self.diskCache = diskCache ?? DiskCacheManager()
        Logger.process.debugMessageOnly("ThumbnailProvider: init() complete (pending setup)")
    }

    func getSettings() async {
        if savedsettings == nil {
            savedsettings = await SettingsViewModel.shared.asyncgetsettings()
        }
    }

    private func ensureReady() async {
        if let task = setupTask {
            return await task.value
        }

        let newTask = Task {
            // 1. Ensure Cache is ready
            await SharedMemoryCache.shared.ensureReady()
            // 2. Ensure we have settings for UI functions
            await self.getSettings()
        }

        self.setupTask = newTask
        await newTask.value
    }

    func setFileHandlers(_ fileHandlers: FileHandlers) {
        self.fileHandlers = fileHandlers
    }

    private func getCostPerPixel() -> Int {
        if let cached = cachedCostPerPixel {
            return cached
        }
        let cost = savedsettings?.thumbnailCostPerPixel ?? 4
        cachedCostPerPixel = cost
        return cost
    }

    private func cancelPreload() {
        preloadTask?.cancel()
        preloadTask = nil
        Logger.process.debugMessageOnly("ThumbnailProvider: Preload Cancelled")
    }

    @discardableResult
    func preloadCatalog(at catalogURL: URL, targetSize: Int) async -> Int {
        await ensureReady()
        cancelPreload()

        let task = Task {
            successCount = 0
            processingTimes = []
            let urls = await DiscoverFiles().discoverFiles(at: catalogURL, recursive: false)
            totalFilesToProcess = urls.count

            await fileHandlers?.maxfilesHandler(urls.count)

            return await withThrowingTaskGroup(of: Void.self) { group in
                let maxConcurrent = ProcessInfo.processInfo.activeProcessorCount * 2

                for (index, url) in urls.enumerated() {
                    if Task.isCancelled {
                        group.cancelAll()
                        break
                    }

                    if index >= maxConcurrent {
                        try? await group.next()
                    }

                    group.addTask {
                        await self.processSingleFile(url, targetSize: targetSize, itemIndex: index)
                    }
                }

                try? await group.waitForAll()
                return successCount
            }
        }

        preloadTask = task
        return await task.value
    }

    private func processSingleFile(_ url: URL, targetSize: Int, itemIndex: Int) async {
        let startTime = Date()

        if Task.isCancelled { return }

        // A. Check RAM (Shared)
        if let wrapper = SharedMemoryCache.shared.object(forKey: url as NSURL), wrapper.beginContentAccess() {
            defer { wrapper.endContentAccess() }
            cacheMemory += 1
            let newCount = incrementAndGetCount()
            await fileHandlers?.fileHandler(newCount)
            await updateEstimatedTime(for: startTime, itemsProcessed: newCount)
            Logger.process.debugThreadOnly("ThumbnailProvider: processSingleFile() - found in RAM Cache")
            return
        }

        if Task.isCancelled { return }

        // B. Check Disk
        if let diskImage = await diskCache.load(for: url) {
            storeInMemoryCache(diskImage, for: url)
            cacheDisk += 1
            let newCount = incrementAndGetCount()
            await fileHandlers?.fileHandler(newCount)
            await updateEstimatedTime(for: startTime, itemsProcessed: newCount)
            Logger.process.debugThreadOnly("ThumbnailProvider: processSingleFile() - found in DISK Cache")
            return
        }

        // C. Extract
        do {
            if Task.isCancelled { return }

            let costPerPixel = await SharedMemoryCache.shared.costPerPixel

            let cgImage = try await ExtractSonyThumbnail().extractSonyThumbnail(
                from: url,
                maxDimension: CGFloat(targetSize),
                qualityCost: costPerPixel
            )

            // Normalize to single representation (matches disk-loaded images)
            let image = try cgImageToNormalizedNSImage(cgImage)

            storeInMemoryCache(image, for: url)

            let newCount = incrementAndGetCount()
            await fileHandlers?.fileHandler(newCount)
            await updateEstimatedTime(for: startTime, itemsProcessed: newCount)

            Logger.process.debugThreadOnly("ThumbnailProvider: processSingleFile() - CREATING thumbnail")

            Task.detached(priority: .background) { [cgImage] in
                await self.diskCache.save(cgImage, for: url)
            }
        } catch {
            Logger.process.warning("Failed: \(url.lastPathComponent)")
        }
    }

    private func updateEstimatedTime(for startTime: Date, itemsProcessed: Int) async {
        let now = Date()

        if let lastTime = lastItemTime {
            let delta = now.timeIntervalSince(lastTime)
            processingTimes.append(delta)
        }
        lastItemTime = now

        if itemsProcessed >= estimationStartIndex, !processingTimes.isEmpty {
            let recentTimes = processingTimes.suffix(min(10, processingTimes.count))
            let avgTimePerItem = recentTimes.reduce(0, +) / Double(recentTimes.count)
            let remainingItems = totalFilesToProcess - itemsProcessed
            let estimatedSeconds = Int(avgTimePerItem * Double(remainingItems))

            // Only update if the new estimate is lower than the current one
            if let current = lastEstimatedSeconds, estimatedSeconds > current {
                return
            }

            lastEstimatedSeconds = estimatedSeconds
            await fileHandlers?.estimatedTimeHandler(estimatedSeconds)
        }
    }

    private func cgImageToNormalizedNSImage(_ cgImage: CGImage) throws -> NSImage {
        // Convert CGImage → JPEG data → NSImage
        // This normalizes it to match disk-loaded images (single representation)
        let bitmapRep = NSBitmapImageRep(cgImage: cgImage)

        guard let data = bitmapRep.representation(using: .jpeg, properties: [.compressionFactor: 0.7]) else {
            throw ThumbnailError.generationFailed
        }

        guard let normalizedImage = NSImage(data: data) else {
            throw ThumbnailError.generationFailed
        }

        return normalizedImage
    }

    private func nsImageToCGImage(_ nsImage: NSImage) throws -> CGImage {
        // Try to extract existing CGImage directly from representations (cheapest)
        for rep in nsImage.representations {
            if let bitmapRep = rep as? NSBitmapImageRep, let cgImage = bitmapRep.cgImage {
                return cgImage
            }
        }

        // Fallback: use TIFF only if no bitmap representation exists
        guard let tiffData = nsImage.tiffRepresentation,
              let bitmapRep = NSBitmapImageRep(data: tiffData),
              let cgImage = bitmapRep.cgImage
        else {
            throw ThumbnailError.generationFailed
        }
        return cgImage
    }

    private func incrementAndGetCount() -> Int {
        successCount += 1
        return successCount
    }

    private func storeInMemoryCache(_ image: NSImage, for url: URL) {
        let costPerPixel = getCostPerPixel()
        let wrapper = DiscardableThumbnail(image: image, costPerPixel: costPerPixel)
        SharedMemoryCache.shared.setObject(wrapper, forKey: url as NSURL, cost: wrapper.cost)
    }

    func thumbnail(for url: URL, targetSize: Int) async -> CGImage? {
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

        // A. Check RAM
        if let wrapper = SharedMemoryCache.shared.object(forKey: nsUrl), wrapper.beginContentAccess() {
            defer { wrapper.endContentAccess() }
            cacheMemory += 1
            Logger.process.debugThreadOnly("resolveImage: found in RAM Cache (hits: \(cacheMemory))")
            let nsImage = wrapper.image
            return try nsImageToCGImage(nsImage)
        }

        // B. Check Disk
        if let diskImage = await diskCache.load(for: url) {
            storeInMemoryCache(diskImage, for: url)
            cacheDisk += 1
            Logger.process.debugThreadOnly("resolveImage: found in Disk Cache (misses: \(cacheDisk))")
            return try nsImageToCGImage(diskImage)
        }

        // C. Extract
        Logger.process.debugThreadOnly("resolveImage: CREATING thumbnail")

        // New (Actor safe access):
        // We need 'await' here because we are reading the protected '_costPerPixel' property.
        let costPerPixel = await SharedMemoryCache.shared.costPerPixel

        let cgImage = try await ExtractSonyThumbnail().extractSonyThumbnail(
            from: url,
            maxDimension: CGFloat(targetSize),
            qualityCost: costPerPixel
        )

        // Normalize to single representation (matches disk-loaded images)
        let image = try cgImageToNormalizedNSImage(cgImage)

        storeInMemoryCache(image, for: url)

        Task.detached(priority: .background) { [cgImage] in
            await self.diskCache.save(cgImage, for: url)
        }

        return cgImage
    }
}
