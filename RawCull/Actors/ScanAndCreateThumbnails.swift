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
        if Task.isCancelled { return }

        // A. Check RAM
        if let wrapper = SharedMemoryCache.shared.object(forKey: url as NSURL), wrapper.beginContentAccess() {
            defer { wrapper.endContentAccess() }
            storeInGridCache(wrapper.image, for: url)
            await SharedMemoryCache.shared.updateCacheMemory()
            let newCount = incrementAndGetCount()
            notifyFileHandler(newCount)
            updateEstimatedTime(itemsProcessed: newCount)
            return
        }

        if Task.isCancelled { return }

        // B. Check Disk
        if let diskImage = await diskCache.load(for: url) {
            storeInMemoryCache(diskImage, for: url)
            storeInGridCache(diskImage, for: url)
            await SharedMemoryCache.shared.updateCacheDisk()
            let newCount = incrementAndGetCount()
            notifyFileHandler(newCount)
            updateEstimatedTime(itemsProcessed: newCount)
            return
        }

        // C. Extract from source file
        do {
            if Task.isCancelled { return }
            notifyExtractionNeeded()

            let costPerPixel = await SharedMemoryCache.shared.costPerPixel

            let cgImage = try await SonyThumbnailExtractor.extractSonyThumbnail(
                from: url,
                maxDimension: CGFloat(targetSize),
                qualityCost: costPerPixel,
            )

            if Task.isCancelled { return }

            let image = NSImage(cgImage: cgImage, size: NSSize(width: cgImage.width, height: cgImage.height))

            storeInMemoryCache(image, for: url)
            storeInGridCache(image, for: url)

            let newCount = incrementAndGetCount()
            notifyFileHandler(newCount)
            updateEstimatedTime(itemsProcessed: newCount)

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

    private func notifyExtractionNeeded() {
        let handler = fileHandlers?.onExtractionNeeded
        Task { @MainActor in handler?() }
    }

    // MARK: - ETA

    private func updateEstimatedTime(itemsProcessed: Int) {
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
            let handler = fileHandlers?.estimatedTimeHandler
            Task { @MainActor in handler?(estimatedSeconds) }
        }
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

    private func storeInGridCache(_ image: NSImage, for url: URL) {
        let nsUrl = url as NSURL
        guard SharedMemoryCache.shared.gridObject(forKey: nsUrl) == nil else { return }
        let gridSize: CGFloat = 200
        guard let scaled = downscale(image, to: gridSize) else { return }
        let costPerPixel = getCostPerPixel()
        let wrapper = DiscardableThumbnail(image: scaled, costPerPixel: costPerPixel)
        SharedMemoryCache.shared.setGridObject(wrapper, forKey: nsUrl, cost: wrapper.cost)
    }

    private func downscale(_ image: NSImage, to maxDimension: CGFloat) -> NSImage? {
        let size = image.size
        guard size.width > 0, size.height > 0 else { return nil }
        let scale = min(maxDimension / size.width, maxDimension / size.height, 1.0)
        let newSize = CGSize(width: (size.width * scale).rounded(), height: (size.height * scale).rounded())
        let result = NSImage(size: newSize)
        result.lockFocus()
        image.draw(
            in: NSRect(origin: .zero, size: newSize),
            from: NSRect(origin: .zero, size: size),
            operation: .copy,
            fraction: 1.0,
        )
        result.unlockFocus()
        return result
    }
}
