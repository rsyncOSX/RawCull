//
//  ScanAndCreateThumbnails.swift
//  RawCull
//
//  Created by Thomas Evensen on 24/01/2026.
//

import AppKit
import Foundation

// import OSLog

actor ScanAndCreateThumbnails {
    // MARK: - Isolated State

    private var successCount = 0
    private let diskCache: DiskCacheManager

    // Cache statistics for monitoring
    private var cacheMemory = 0
    private var cacheDisk = 0

    // Timing tracking
    private var processingTimes: [TimeInterval] = []
    private var totalFilesToProcess = 0

    /// Minimum number of items processed before ETA estimation begins.
    private static let minimumSamplesBeforeEstimation = 10

    private var preloadTask: Task<Int, Never>?
    private var fileHandlers: FileHandlers?

    private var savedSettings: SavedSettings?
    private var setupTask: Task<Void, Never>?

    /// Cached cost-per-pixel; cleared when settings change via `getCacheCostsAfterSettingsUpdate`.
    private var cachedCostPerPixel: Int?

    /// Timestamp of the last completed item, used for rolling ETA calculation.
    private var lastItemTime: Date?
    private var lastEstimatedSeconds: Int?

    // MARK: - Init

    init(
        config _: CacheConfig? = nil,
        diskCache: DiskCacheManager? = nil,
    ) {
        self.diskCache = diskCache ?? DiskCacheManager()
        // Logger.process.debugMessageOnly("ThumbnailProvider: init() complete (pending setup)")
    }

    // MARK: - Setup

    func getSettings() async {
        if savedSettings == nil {
            savedSettings = await SettingsViewModel.shared.asyncgetsettings()
        }
    }

    private func ensureReady() async {
        if let task = setupTask {
            return await task.value
        }

        let newTask = Task {
            await SharedMemoryCache.shared.ensureReady()
            await self.getSettings()
        }

        setupTask = newTask
        await newTask.value
    }

    func setFileHandlers(_ fileHandlers: FileHandlers) {
        self.fileHandlers = fileHandlers
    }

    // MARK: - Settings / Cost

    private func getCostPerPixel() -> Int {
        if let cached = cachedCostPerPixel {
            return cached
        }
        let cost = savedSettings?.thumbnailCostPerPixel ?? 4
        cachedCostPerPixel = cost
        return cost
    }

    // MARK: - Preload

    func cancelPreload() {
        preloadTask?.cancel()
        preloadTask = nil
        // Logger.process.debugMessageOnly("ThumbnailProvider: Preload Cancelled")
    }

    @discardableResult
    func preloadCatalog(at catalogURL: URL, targetSize: Int) async -> Int {
        await ensureReady()
        cancelPreload()

        let task = Task<Int, Never> {
            successCount = 0
            processingTimes = []
            lastItemTime = nil
            lastEstimatedSeconds = nil

            let urls = await DiscoverFiles().discoverFiles(at: catalogURL, recursive: false)
            totalFilesToProcess = urls.count

            await fileHandlers?.maxfilesHandler(urls.count)

            return await withTaskGroup(of: Void.self) { group in
                let maxConcurrent = ProcessInfo.processInfo.activeProcessorCount * 2

                for (index, url) in urls.enumerated() {
                    if Task.isCancelled {
                        group.cancelAll()
                        break
                    }

                    if index >= maxConcurrent {
                        await group.next()
                    }

                    group.addTask {
                        await self.processSingleFile(url, targetSize: targetSize, itemIndex: index)
                    }
                }

                await group.waitForAll()
                return successCount
            }
        }

        preloadTask = task
        return await task.value
    }

    // MARK: - Single File Processing

    private func processSingleFile(_ url: URL, targetSize: Int, itemIndex _: Int) async {
        let startTime = Date()

        if Task.isCancelled { return }

        // A. Check RAM
        if let wrapper = SharedMemoryCache.shared.object(forKey: url as NSURL), wrapper.beginContentAccess() {
            defer { wrapper.endContentAccess() }
            cacheMemory += 1
            let newCount = incrementAndGetCount()
            notifyFileHandler(newCount)
            updateEstimatedTime(for: startTime, itemsProcessed: newCount)
            // Logger.process.debugThreadOnly("ThumbnailProvider: processSingleFile() - found in RAM Cache")
            return
        }

        if Task.isCancelled { return }

        // B. Check Disk
        if let diskImage = await diskCache.load(for: url) {
            storeInMemoryCache(diskImage, for: url)
            cacheDisk += 1
            let newCount = incrementAndGetCount()
            notifyFileHandler(newCount)
            updateEstimatedTime(for: startTime, itemsProcessed: newCount)
            // Logger.process.debugThreadOnly("ThumbnailProvider: processSingleFile() - found in DISK Cache")
            return
        }

        // C. Extract from source file
        do {
            if Task.isCancelled { return }

            let costPerPixel = await SharedMemoryCache.shared.costPerPixel

            let cgImage = try await SonyThumbnailExtractor.extractSonyThumbnail(
                from: url,
                maxDimension: CGFloat(targetSize),
                qualityCost: costPerPixel,
            )

            if Task.isCancelled { return }

            let image = try cgImageToNormalizedNSImage(cgImage)

            storeInMemoryCache(image, for: url)

            let newCount = incrementAndGetCount()
            notifyFileHandler(newCount)
            updateEstimatedTime(for: startTime, itemsProcessed: newCount)

            // Logger.process.debugThreadOnly("ThumbnailProvider: processSingleFile() - CREATING thumbnail")

            // Encode to Data here, inside the actor, before crossing the task boundary.
            // `Data` is Sendable; `CGImage` is not.
            guard let jpegData = DiskCacheManager.jpegData(from: cgImage) else {
                // Logger.process.warning("ThumbnailProvider: failed to encode JPEG for \(url.lastPathComponent)")
                return
            }

            let dcache = diskCache
            Task.detached(priority: .background) {
                await dcache.save(jpegData, for: url)
            }
        } catch {
            // Logger.process.warning("Failed: \(url.lastPathComponent)")
        }
    }

    // MARK: - UI Notifications (fire-and-forget)

    /// Notifies the UI that one more file is done. Does NOT await the main-actor
    /// callback — thumbnail generation must not stall waiting for UI rendering.
    private func notifyFileHandler(_ count: Int) {
        let handler = fileHandlers?.fileHandler
        Task { @MainActor in handler?(count) }
    }

    // MARK: - ETA

    private func updateEstimatedTime(for _: Date, itemsProcessed: Int) {
        let now = Date()

        if let lastTime = lastItemTime {
            let delta = now.timeIntervalSince(lastTime)
            processingTimes.append(delta)
        }
        lastItemTime = now

        if itemsProcessed >= Self.minimumSamplesBeforeEstimation, !processingTimes.isEmpty {
            let recentTimes = processingTimes.suffix(min(10, processingTimes.count))
            let avgTimePerItem = recentTimes.reduce(0, +) / Double(recentTimes.count)
            let remainingItems = totalFilesToProcess - itemsProcessed
            let estimatedSeconds = Int(avgTimePerItem * Double(remainingItems))

            if let current = lastEstimatedSeconds, estimatedSeconds > current {
                return
            }

            lastEstimatedSeconds = estimatedSeconds
            let handler = fileHandlers?.estimatedTimeHandler
            Task { @MainActor in handler?(estimatedSeconds) }
        }
    }

    // MARK: - Image Conversion

    /// Converts a `CGImage` to an `NSImage` backed by a single JPEG representation.
    private func cgImageToNormalizedNSImage(_ cgImage: CGImage) throws -> NSImage {
        let bitmapRep = NSBitmapImageRep(cgImage: cgImage)

        guard let data = bitmapRep.representation(using: .jpeg, properties: [.compressionFactor: 0.7]) else {
            throw ThumbnailError.generationFailed
        }

        guard let normalizedImage = NSImage(data: data) else {
            throw ThumbnailError.generationFailed
        }

        return normalizedImage
    }

    // MARK: - Cache Helpers

    private func incrementAndGetCount() -> Int {
        successCount += 1
        return successCount
    }

    private func storeInMemoryCache(_ image: NSImage, for url: URL) {
        let nsUrl = url as NSURL
        guard SharedMemoryCache.shared.object(forKey: nsUrl) == nil else { return }
        let costPerPixel = getCostPerPixel()
        let wrapper = DiscardableThumbnail(image: image, costPerPixel: costPerPixel)
        SharedMemoryCache.shared.setObject(wrapper, forKey: nsUrl, cost: wrapper.cost)
    }
}
