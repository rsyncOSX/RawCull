//
//  RequestThumbnail.swift
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

actor RequestThumbnail {
    /// Ensures settings are loaded before any work starts
    private var setupTask: Task<Void, Never>?
    private let diskCache: DiskCacheManager

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

        // A. Check RAM (Using Shared Cache)
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

        // New (Actor safe access):
        // We need 'await' here because we are reading the protected '_costPerPixel' property.
        let costPerPixel = await SharedMemoryCache.shared.costPerPixel

        let cgImage = try await SonyThumbnailExtractor.extractSonyThumbnail(
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

    /// Convert NSImage to CGImage on a lower QoS to avoid priority inversions
    private func nsImageToCGImage(_ nsImage: NSImage) async throws -> CGImage {
        // If the NSImage already contains a CGImage, prefer that path to avoid re-encoding
        if let cgRef = nsImage.cgImage(forProposedRect: nil, context: nil, hints: nil) {
            return cgRef
        }

        // Fallback: perform TIFF roundtrip on a utility-priority detached task
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
