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
    private var setupTask: Task<Void, Never>?
    private let diskCache: DiskCacheManager

    init(
        config _: CacheConfig? = nil,
        diskCache: DiskCacheManager? = nil
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

        // A. Check RAM
        if let wrapper = SharedMemoryCache.shared.object(forKey: nsUrl), wrapper.beginContentAccess() {
            defer { wrapper.endContentAccess() }
            await SharedMemoryCache.shared.updateCacheMemory()
            let nsImage = wrapper.image
            return try await nsImageToCGImage(nsImage)
        }

        // B. Check Disk
        if let diskImage = await diskCache.load(for: url) {
            await storeInMemory(diskImage, for: url)
            await SharedMemoryCache.shared.updateCacheDisk()
            return try await nsImageToCGImage(diskImage)
        }

        // C. Extract
        Logger.process.debugThreadOnly("RequestThumbnail: resolveImage() - no cache hit, CREATING thumbnail")

        let costPerPixel = await SharedMemoryCache.shared.costPerPixel

        let cgImage = try await SonyThumbnailExtractor.extractSonyThumbnail(
            from: url,
            maxDimension: CGFloat(targetSize),
            qualityCost: costPerPixel
        )

        let image = NSImage(cgImage: cgImage, size: NSSize(width: cgImage.width, height: cgImage.height))

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
        let costPerPixel = await SharedMemoryCache.shared.costPerPixel
        let wrapper = DiscardableThumbnail(image: image, costPerPixel: costPerPixel)
        SharedMemoryCache.shared.setObject(wrapper, forKey: url as NSURL, cost: wrapper.cost)
    }
}
