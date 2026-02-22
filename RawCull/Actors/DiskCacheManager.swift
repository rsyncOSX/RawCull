import AppKit
import CryptoKit
import Foundation
import OSLog
import UniformTypeIdentifiers

actor DiskCacheManager {
    let cacheDirectory: URL

    init() {
        let paths = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)
        let folder = paths[0].appendingPathComponent("no.blogspot.RawCull/Thumbnails")
        cacheDirectory = folder
        do {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        } catch {
            // Optional: Log error to console
            Logger.process.warning("DiskCacheManager: Failed to create directory \(folder): \(error)")
        }
    }

    private func cacheURL(for sourceURL: URL) -> URL {
        let standardizedPath = sourceURL.standardized.path
        let data = Data(standardizedPath.utf8)
        let digest = Insecure.MD5.hash(data: data)
        let hash = digest.map { String(format: "%02x", $0) }.joined()
        return cacheDirectory.appendingPathComponent(hash).appendingPathExtension("jpg")
    }

    func load(for sourceURL: URL) async -> NSImage? {
        // Calculate URL while on the actor
        let fileURL = cacheURL(for: sourceURL)

        // 1. Read Data off the actor to prevent blocking
        let data = await Task.detached(priority: .userInitiated) {
            try? Data(contentsOf: fileURL)
        }.value

        guard let data else { return nil }

        // 2. Create NSImage inside the actor (safe)
        return NSImage(data: data)
    }

    func save(_ cgImage: CGImage, for sourceURL: URL) async {
        // 1. Calculate the hash path while on the actor.
        // Avoids sending 'self' (the actor) into the detached task.
        let fileURL = cacheURL(for: sourceURL)

        // 2. Perform compression and IO off the actor
        await Task.detached(priority: .background) {
            // cgImage is sent here. Since CGImage is a type-less wrapper and Sendable,
            // this is generally safe, though the compiler might warn about strict concurrency.
            do {
                try Self.writeImageToDisk(cgImage, to: fileURL)
            } catch {
                Logger.process.warning("DiskCacheManager: Failed to write image to disk \(fileURL.path): \(error)")
            }
        }.value
    }

    /// Helper isolated to the detached task context
    private nonisolated static func writeImageToDisk(_ cgImage: CGImage, to fileURL: URL) throws {
        guard let destination = CGImageDestinationCreateWithURL(
            fileURL as CFURL,
            UTType.jpeg.identifier as CFString,
            1,
            nil
        ) else {
            throw ThumbnailError.generationFailed
        }

        let options: [CFString: Any] = [
            kCGImageDestinationLossyCompressionQuality: 0.7
        ]

        CGImageDestinationAddImage(destination, cgImage, options as CFDictionary)

        if !CGImageDestinationFinalize(destination) {
            throw ThumbnailError.generationFailed
        }
    }

    func getDiskCacheSize() async -> Int {
        let directory = cacheDirectory

        return await Task.detached(priority: .utility) {
            let fileManager = FileManager.default
            let resourceKeys: [URLResourceKey] = [.totalFileAllocatedSizeKey]

            guard let urls = try? fileManager.contentsOfDirectory(
                at: directory,
                includingPropertiesForKeys: resourceKeys,
                options: .skipsHiddenFiles
            ) else { return 0 }

            var totalSize = 0
            for fileURL in urls {
                do {
                    let values = try fileURL.resourceValues(forKeys: Set(resourceKeys))
                    if let size = values.totalFileAllocatedSize {
                        totalSize += size
                    }
                } catch {
                    Logger.process.warning("DiskCacheManager: Failed to get size for \(fileURL.path): \(error)")
                }
            }
            return totalSize
        }.value
    }

    func pruneCache(maxAgeInDays: Int = 30) async {
        // Capture cacheDirectory to avoid capturing 'self'
        let directory = cacheDirectory

        await Task.detached(priority: .utility) {
            let fileManager = FileManager.default
            let resourceKeys: [URLResourceKey] = [.contentModificationDateKey, .totalFileAllocatedSizeKey]

            guard let urls = try? fileManager.contentsOfDirectory(
                at: directory,
                includingPropertiesForKeys: resourceKeys,
                options: .skipsHiddenFiles
            ) else { return }

            guard let expirationDate = Calendar.current.date(byAdding: .day, value: -maxAgeInDays, to: Date()) else { return }

            for fileURL in urls {
                do {
                    let values = try fileURL.resourceValues(forKeys: Set(resourceKeys))
                    if let date = values.contentModificationDate, date < expirationDate {
                        try fileManager.removeItem(at: fileURL)
                    }
                } catch {
                    // Optional: Log error to console
                    Logger.process.warning("DiskCacheManager: Failed to delete \(fileURL.path): \(error)")
                }
            }
        }.value
    }
}
