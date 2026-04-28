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

    private var setupTask: Task<Void, Never>?
    private let diskCache: DiskCacheManager

    init(
        diskCache: DiskCacheManager? = nil,
    ) {
        self.diskCache = diskCache ?? DiskCacheManager()
    }

    private func ensureReady() async {
        if let task = setupTask {
            return await task.value
        }

        let newTask = Task {
            await SharedMemoryCache.shared.ensureReady()
        }

        setupTask = newTask
        await newTask.value
    }

    func requestThumbnail(for url: URL, targetSize: Int) async -> CGImage? {
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
        // Demand counter: total UI-driven thumbnail requests. Forms the
        // denominator for `true_hit_rate_pct` in Memory Diagnostics — unlike
        // the existing layer-relative `hit_rate_pct`, this includes branch C
        // (cold extractions) so the metric reflects real user-perceived hits.
        SharedMemoryCache.shared.incrementDemandRequest()

        // A. Check RAM
        if let wrapper = SharedMemoryCache.shared.object(forKey: nsUrl) {
            Logger.process.debugThreadOnly("SharedMemoryCache: updateCacheMemory() - found in RAM Cache)")
            await SharedMemoryCache.shared.updateCacheMemory()
            let nsImage = wrapper.image
            return try await nsImageToCGImage(nsImage)
        }

        // B. Check Disk
        if let diskImage = await diskCache.load(for: url) {
            // Boomerang detection: a disk hit on a key the main RAM cache
            // recently evicted is the "scan polluted RAM, user paid disk cost
            // to get it back" pattern we're trying to quantify.
            if SharedMemoryCache.shared.wasRecentlyEvicted(url: nsUrl) {
                SharedMemoryCache.shared.incrementBoomerangMiss()
            }
            await storeInMemory(diskImage, for: url)
            Logger.process.debugThreadOnly("SharedMemoryCache: updateCacheDisk() - found in Disk Cache)")
            await SharedMemoryCache.shared.updateCacheDisk()
            return try await nsImageToCGImage(diskImage)
        }

        // C. Extract
        // Logger.process.debugThreadOnly("RequestThumbnail: resolveImage() - no cache hit, CREATING thumbnail")

        let costPerPixel = await SharedMemoryCache.shared.costPerPixel

        guard let format = RawFormatRegistry.format(for: url) else {
            throw ThumbnailError.invalidSource
        }
        let cgImage = try await format.extractThumbnail(
            from: url,
            maxDimension: CGFloat(targetSize),
            qualityCost: costPerPixel,
        )

        let image = NSImage(cgImage: cgImage, size: NSSize(width: cgImage.width, height: cgImage.height))
        // Cold extraction: not in RAM, not on disk, decoded from ARW source.
        // The third bucket of demand traffic — without it, the layer-relative
        // hit rate (`hit_rate_pct`) is meaningless during a fresh scan because
        // its denominator excludes this path entirely.
        SharedMemoryCache.shared.incrementColdExtract()

        await storeInMemory(image, for: url)

        // Encode to Data here, inside the actor, before crossing the task boundary.
        // `Data` is Sendable; `CGImage` is not.
        if let jpegData = DiskCacheManager.jpegData(from: cgImage) {
            // Capture only `diskCache` (actor-isolated let) and the two value types.
            // No implicit `self` capture, no non-Sendable types crossing the boundary.
            let dcache = diskCache
            Task.detached(priority: .background) {
                await dcache.save(jpegData, for: url)
            }
        } else {
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
                throw ThumbnailError.generationFailed
            }
            return cgImage
        }.value
    }

    private func storeInMemory(_ image: NSImage, for url: URL) async {
        let nsUrl = url as NSURL
        guard SharedMemoryCache.shared.object(forKey: nsUrl) == nil else { return }
        let costPerPixel = await SharedMemoryCache.shared.costPerPixel
        let wrapper = CachedThumbnail(image: image, costPerPixel: costPerPixel, url: nsUrl)
        SharedMemoryCache.shared.setObject(wrapper, forKey: nsUrl, cost: wrapper.cost)
    }
}
