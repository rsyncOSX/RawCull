//
//  RequestThumbnail.swift
//  RawCull
//
//  Created by Thomas Evensen on 11/02/2026.
//

import AppKit
import Foundation
import OSLog

actor RequestThumbnail {
    static let shared = RequestThumbnail()

    private struct InFlightRequest {
        let generation: UUID
        let task: Task<Void, Never>
        var waiters: [UUID: CheckedContinuation<CGImage?, Never>]
    }

    private var setupTask: Task<Void, Never>?
    private var inFlightRequests: [ThumbnailCacheKey: InFlightRequest] = [:]
    private let diskCache: DiskCacheManager
    private let diagnostics: ContentionDiagnostics
    private let memoryCache: SharedMemoryCache
    private let rawLoader: any RawImageLoading

    init(
        diskCache: DiskCacheManager? = nil,
        diagnostics: ContentionDiagnostics = .shared,
        memoryCache: SharedMemoryCache = .shared,
        rawLoader: any RawImageLoading = RawParserKitImageLoader.shared,
    ) {
        self.diskCache = diskCache ?? DiskCacheManager()
        self.diagnostics = diagnostics
        self.memoryCache = memoryCache
        self.rawLoader = rawLoader
    }

    private func ensureReady() async {
        if let task = setupTask {
            return await task.value
        }

        let newTask = Task {
            await memoryCache.ensureReady()
        }

        setupTask = newTask
        await newTask.value
    }

    func requestThumbnail(
        for url: URL,
        targetSize: Int,
        purpose: ThumbnailCacheKey.Purpose,
    ) async -> CGImage? {
        await ensureReady()

        // Count callers rather than producers: exact-key callers may share one
        // producer below, but every UI request remains demand traffic.
        memoryCache.incrementDemandRequest()

        guard let cacheKey = ThumbnailCacheKey.resolve(
            for: url,
            purpose: purpose,
            requestedPixelSize: targetSize,
        ) else {
            return await performRequest(
                for: url,
                targetSize: targetSize,
                cacheKey: nil,
            )
        }

        return await coalescedRequest(
            for: url,
            targetSize: targetSize,
            cacheKey: cacheKey,
        )
    }

    private func performRequest(
        for url: URL,
        targetSize: Int,
        cacheKey: ThumbnailCacheKey?,
    ) async -> CGImage? {
        do {
            return try await resolveImage(
                for: url,
                targetSize: targetSize,
                cacheKey: cacheKey,
            )
        } catch is CancellationError {
            return nil
        } catch {
            Logger.process.warning("Failed to resolve thumbnail: \(error)")
            return nil
        }
    }

    private func coalescedRequest(
        for url: URL,
        targetSize: Int,
        cacheKey: ThumbnailCacheKey,
    ) async -> CGImage? {
        let waiterID = UUID()
        let result = await withTaskCancellationHandler {
            await withCheckedContinuation { continuation in
                enqueue(
                    waiterID: waiterID,
                    continuation: continuation,
                    url: url,
                    targetSize: targetSize,
                    cacheKey: cacheKey,
                )
            }
        } onCancel: {
            Task {
                await self.cancelWaiter(waiterID, for: cacheKey)
            }
        }
        return Task.isCancelled ? nil : result
    }

    private func enqueue(
        waiterID: UUID,
        continuation: CheckedContinuation<CGImage?, Never>,
        url: URL,
        targetSize: Int,
        cacheKey: ThumbnailCacheKey,
    ) {
        guard !Task.isCancelled else {
            diagnostics.recordThumbnailCancellation()
            continuation.resume(returning: nil)
            return
        }

        if var request = inFlightRequests[cacheKey] {
            diagnostics.recordDuplicateThumbnailKey()
            request.waiters[waiterID] = continuation
            inFlightRequests[cacheKey] = request
            return
        }

        let generation = UUID()
        let task = Task { [weak self] in
            guard let self else { return }
            let image = await self.performRequest(
                for: url,
                targetSize: targetSize,
                cacheKey: cacheKey,
            )
            await self.finishRequest(
                for: cacheKey,
                generation: generation,
                image: image,
            )
        }
        inFlightRequests[cacheKey] = InFlightRequest(
            generation: generation,
            task: task,
            waiters: [waiterID: continuation],
        )
    }

    private func cancelWaiter(
        _ waiterID: UUID,
        for cacheKey: ThumbnailCacheKey,
    ) {
        guard var request = inFlightRequests[cacheKey],
              let continuation = request.waiters.removeValue(forKey: waiterID)
        else { return }

        diagnostics.recordThumbnailCancellation()
        continuation.resume(returning: nil)
        if request.waiters.isEmpty {
            inFlightRequests.removeValue(forKey: cacheKey)
            request.task.cancel()
        } else {
            inFlightRequests[cacheKey] = request
        }
    }

    private func finishRequest(
        for cacheKey: ThumbnailCacheKey,
        generation: UUID,
        image: CGImage?,
    ) {
        guard let request = inFlightRequests[cacheKey],
              request.generation == generation
        else { return }

        inFlightRequests.removeValue(forKey: cacheKey)
        for continuation in request.waiters.values {
            continuation.resume(returning: image)
        }
    }

    private func resolveImage(
        for url: URL,
        targetSize: Int,
        cacheKey: ThumbnailCacheKey?,
    ) async throws -> CGImage {
        let sourceURL = url.standardizedFileURL as NSURL

        // A. Check RAM
        if let cacheKey, let wrapper = memoryCache.object(forKey: cacheKey) {
            // Logger.process.debugThreadOnly("RequestThumbnail: resolveImage() - found in RAM Cache)")
            await memoryCache.updateCacheMemory()
            let nsImage = wrapper.image
            return try await nsImageToCGImage(nsImage)
        }

        // B. Check Disk
        if let cacheKey, let diskImage = await diskCache.load(for: cacheKey) {
            // Boomerang detection: a disk hit on a key the main RAM cache
            // recently evicted is the "scan polluted RAM, user paid disk cost
            // to get it back" pattern we're trying to quantify.
            if memoryCache.wasRecentlyEvicted(url: sourceURL) {
                memoryCache.incrementBoomerangMiss()
            }
            storeInMemory(diskImage, for: cacheKey)
            // Logger.process.debugThreadOnly("RequestThumbnail: resolveImage() - found in Disk Cache)")
            await memoryCache.updateCacheDisk()
            return try await nsImageToCGImage(diskImage)
        }

        // C. Extract
        // Logger.process.debugThreadOnly("RequestThumbnail: resolveImage() - no cache hit, CREATING thumbnail")

        try Task.checkCancellation()
        diagnostics.beginThumbnailWork(coldDecode: true)
        defer { diagnostics.endThumbnailWork() }

        guard let cgImage = await rawLoader.thumbnailCGImage(
            for: url,
            maxPixelSize: targetSize,
        ) else {
            throw RawImageLoadingError.invalidSource
        }
        try Task.checkCancellation()

        let image = NSImage(cgImage: cgImage, size: NSSize(width: cgImage.width, height: cgImage.height))
        // Cold extraction: not in RAM, not on disk, decoded from ARW source.
        // The third bucket of demand traffic — without it, the layer-relative
        // hit rate (`hit_rate_pct`) is meaningless during a fresh scan because
        // its denominator excludes this path entirely.
        memoryCache.incrementColdExtract()

        if let cacheKey {
            storeInMemory(image, for: cacheKey)
        }

        // Encode to Data here, inside the actor, before crossing the task boundary.
        // `Data` is Sendable; `CGImage` is not.
        if let cacheKey, let jpegData = DiskCacheManager.jpegData(from: cgImage) {
            // Capture only `diskCache` (actor-isolated let) and the two value types.
            // No implicit `self` capture, no non-Sendable types crossing the boundary.
            let dcache = diskCache
            Task.detached(priority: .background) {
                await dcache.save(jpegData, for: cacheKey)
            }
        } else if cacheKey != nil {
            Logger.process.warning("RequestThumbnail: failed to encode JPEG for \(url.lastPathComponent)")
        }

        return cgImage
    }

    /// Convert NSImage to CGImage.
    /// Prefers extracting an existing CGImage directly; falls back to a TIFF round-trip
    /// on a utility-priority detached task to avoid blocking the actor.
    private func nsImageToCGImage(_ nsImage: NSImage) async throws -> CGImage {
        if let cgRef = nsImage.cgImage(forProposedRect: nil, context: nil, hints: nil) {
            return cgRef
        }

        return try await Task.detached(priority: .utility) { () throws -> CGImage in
            guard let tiffData = nsImage.tiffRepresentation,
                  let bitmapRep = NSBitmapImageRep(data: tiffData),
                  let cgImage = bitmapRep.cgImage
            else {
                throw RawImageLoadingError.generationFailed
            }
            return cgImage
        }.value
    }

    private func storeInMemory(_ image: NSImage, for key: ThumbnailCacheKey) {
        guard memoryCache.object(forKey: key) == nil else { return }
        let wrapper = CachedThumbnail(image: image, key: key)
        memoryCache.setObject(wrapper, forKey: key, cost: wrapper.cost)
    }

    #if DEBUG
        func inFlightSnapshotForTesting() -> (requests: Int, waiters: Int) {
            (
                requests: inFlightRequests.count,
                waiters: inFlightRequests.values.reduce(0) {
                    $0 + $1.waiters.count
                },
            )
        }
    #endif
}
