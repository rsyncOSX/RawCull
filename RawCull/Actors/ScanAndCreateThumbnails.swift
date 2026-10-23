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
    // MARK: - Isolated State

    private var successCount = 0
    private var completedCount = 0
    private let diskCache: DiskCacheManager
    private let saveToDisk: @Sendable (Data, ThumbnailCacheKey) async -> Void

    // Timing tracking
    private var processingTimes: [TimeInterval] = []
    private var totalFilesToProcess = 0

    /// Minimum number of items processed before ETA estimation begins.
    private static let minimumSamplesBeforeEstimation = 10

    private var preloadTask: Task<Int, Never>?
    private var fileHandlers: FileHandlers?

    private var savedSettings: SavedSettings?
    private var setupTask: Task<Void, Never>?
    private let rawLoader: any RawImageLoading

    /// Timestamp of the last completed item, used for rolling ETA calculation.
    private var lastItemTime: Date?

    // MARK: - Init

    init(
        config _: CacheConfig? = nil,
        diskCache: DiskCacheManager? = nil,
        rawLoader: any RawImageLoading = RawParserKitImageLoader.shared,
        saveToDisk: (@Sendable (Data, ThumbnailCacheKey) async -> Void)? = nil,
    ) {
        Logger.process.debugMessageOnly("ScanAndCreateThumbnails.init()")
        let resolvedDiskCache = diskCache ?? DiskCacheManager()
        self.diskCache = resolvedDiskCache
        self.saveToDisk = saveToDisk ?? { data, key in
            await resolvedDiskCache.save(data, for: key)
        }
        self.rawLoader = rawLoader
        // Logger.process.debugMessageOnly("ThumbnailProvider: init() complete (pending setup)")
    }

    // MARK: - Setup

    func getSettings() async {
        Logger.process.debugMessageOnly("ScanAndCreateThumbnails.getSettings()")
        if savedSettings == nil {
            savedSettings = await SettingsViewModel.shared.asyncgetsettings()
        }
    }

    private func ensureReady() async {
        Logger.process.debugMessageOnly("ScanAndCreateThumbnails.ensureReady()")
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
        Logger.process.debugMessageOnly("ScanAndCreateThumbnails.setFileHandlers()")
        self.fileHandlers = fileHandlers
    }

    // MARK: - Preload

    func cancelPreload() {
        preloadTask?.cancel()
        preloadTask = nil
        Logger.process.debugMessageOnly("ScanAndCreateThumbnails.cancelPreload()")
    }

    @discardableResult
    func preloadCatalog(at catalogURL: URL, targetSize: Int) async -> Int {
        let access = await RawCullCatalogAccess.shared.retainAccess(for: [catalogURL])
        Logger.process.debugMessageOnly("ScanAndCreateThumbnails.preloadCatalog()")
        await ensureReady()
        cancelPreload()

        let urls = await DiscoverFiles().discoverFiles(at: catalogURL, recursive: false)
        let gateID = await ThumbnailPreloadGate.shared.begin(catalogURL: catalogURL)

        let task = Task<Int, Never> {
            defer { withExtendedLifetime(access) {} }
            successCount = 0
            completedCount = 0
            processingTimes = []
            lastItemTime = nil
            totalFilesToProcess = urls.count

            await fileHandlers?.maxfilesHandler(urls.count)

            return await withTaskGroup(of: Void.self) { group in
                let maxConcurrent = RawImageLoadingConcurrency.thumbnailPreloadLimit

                for (index, url) in urls.enumerated() {
                    if Task.isCancelled {
                        group.cancelAll()
                        break
                    }

                    if index >= maxConcurrent {
                        await group.next()
                    }

                    guard !Task.isCancelled else {
                        group.cancelAll()
                        break
                    }

                    group.addTask {
                        let pendingSave = await self.processSingleFile(
                            url,
                            targetSize: targetSize,
                        )
                        // Publish decode availability before disk latency. Keep the
                        // save in this worker so encoded data and pending writes
                        // share the decode concurrency bound.
                        await ThumbnailPreloadGate.shared.finished(sourceURL: url, sessionID: gateID)
                        if let pendingSave, !Task.isCancelled {
                            await self.saveToDisk(pendingSave.data, pendingSave.key)
                        }
                    }
                }

                await group.waitForAll()
                return successCount
            }
        }

        preloadTask = task
        let result = await withTaskCancellationHandler {
            await task.value
        } onCancel: {
            task.cancel()
        }
        await ThumbnailPreloadGate.shared.end(gateID)
        if preloadTask == task {
            preloadTask = nil
        }
        return result
    }

    // MARK: - Single File Processing

    private func processSingleFile(
        _ url: URL,
        targetSize: Int,
    ) async -> (data: Data, key: ThumbnailCacheKey)? {
        // Logger.process.debugMessageOnly("ScanAndCreateThumbnails.processSingleFile()")
        if Task.isCancelled {
            return nil
        }

        let previewKey = ThumbnailCacheKey.resolve(
            for: url,
            purpose: .preview,
            requestedPixelSize: targetSize,
        )
        let gridKey = previewKey?.representation(purpose: .grid, requestedPixelSize: 200)

        // A. Check RAM
        if let previewKey, let wrapper = SharedMemoryCache.shared.object(forKey: previewKey) {
            _ = storeInGridCache(wrapper.image, for: gridKey)
            // Do not re-admit to memoryCache: object(forKey:) already touched
            // LRU, and scan-order admission would compete with UI-driven LRU
            // ordering (the scan/UI cache-pollution pattern).
            recordCompletion(succeeded: true)
            return nil
        }

        if Task.isCancelled {
            return nil
        }

        // B. Check Disk
        if let previewKey, let diskImage = await diskCache.load(for: previewKey) {
            // Mirror to the grid cache only. Leaving memoryCache admission to
            // RequestThumbnail (its branch B promotes on user-driven hits)
            // keeps LRU ordering aligned with UI traffic and prevents
            // scan-driven evictions from boomeranging UI-active items.
            _ = storeInGridCache(diskImage, for: gridKey)
            recordCompletion(succeeded: true)
            return nil
        }

        // C. Extract from source file
        if Task.isCancelled {
            return nil
        }
        notifyExtractionNeeded()

        let decodedImage = await rawLoader.thumbnailImage(
            for: url,
            maxPixelSize: targetSize,
        )
        if Task.isCancelled {
            return nil
        }

        guard let image = decodedImage,
              let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil)
        else {
            recordCompletion(succeeded: false)
            return nil
        }

        // Invariant (uniform across branches A/B/C): scan never admits to
        // memoryCache. RequestThumbnail is the only admitter, so LRU
        // ordering tracks UI traffic. On an over-cap catalog (e.g. 635
        // files at the 20 GB cap), scan-side admission would self-evict
        // ~180 items and the user would pay a near-100% boomerang rate
        // on first browse. The disk JPEG saved below lets RequestThumbnail
        // branch B serve subsequent UI requests without cold extraction.
        let sourceStillMatches = previewKey == ThumbnailCacheKey.resolve(
            for: url,
            purpose: .preview,
            requestedPixelSize: targetSize,
        )
        if sourceStillMatches {
            _ = storeInGridCache(image, for: gridKey)
        }
        recordCompletion(succeeded: true)

        // Logger.process.debugThreadOnly("ThumbnailProvider: processSingleFile() - CREATING thumbnail")

        // Encode to Data here, inside the actor, before crossing the task boundary.
        // `Data` is Sendable; `CGImage` is not.
        guard !Task.isCancelled,
              sourceStillMatches,
              let previewKey,
              let jpegData = DiskCacheManager.jpegData(from: cgImage)
        else {
            // Logger.process.warning("ThumbnailProvider: failed to encode JPEG for \(url.lastPathComponent)")
            return nil
        }

        return (jpegData, previewKey)
    }

    // MARK: - UI Notifications (fire-and-forget)

    /// Notifies the UI that one more file is done. Does NOT await the main-actor
    /// callback — thumbnail generation must not stall waiting for UI rendering.
    private func notifyFileHandler(_ count: Int) {
        let handler = fileHandlers?.fileHandler
        Task { @MainActor in handler?(count) }
    }

    private func notifyExtractionNeeded() {
        // Logger.process.debugMessageOnly("ScanAndCreateThumbnails.notifyExtractionNeeded()")
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
            let avgSecondsPerCompletion = recentTimes.reduce(0, +) / Double(recentTimes.count)
            let remainingItems = totalFilesToProcess - itemsProcessed
            let estimatedSeconds = Int(avgSecondsPerCompletion * Double(remainingItems))
            let handler = fileHandlers?.estimatedTimeHandler
            Task { @MainActor in handler?(estimatedSeconds) }
        }
    }

    // MARK: - Cache Helpers

    private func recordCompletion(succeeded: Bool) {
        // Logger.process.debugMessageOnly("ScanAndCreateThumbnails.recordCompletion()")
        completedCount += 1
        if succeeded {
            successCount += 1
        }
        notifyFileHandler(completedCount)
        updateEstimatedTime(itemsProcessed: completedCount)
    }

    private func storeInGridCache(_ image: NSImage, for key: ThumbnailCacheKey?) -> Bool {
        guard let key else { return false }
        guard SharedMemoryCache.shared.gridObject(forKey: key) == nil else { return true }
        let gridSize: CGFloat = 200
        guard let scaled = downscale(image, to: gridSize) else { return false }
        let wrapper = CachedThumbnail(image: scaled)
        SharedMemoryCache.shared.setGridObject(wrapper, forKey: key, cost: wrapper.cost)
        return true
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
