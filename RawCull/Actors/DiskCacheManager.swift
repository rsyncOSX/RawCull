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
        let fileURL = cacheURL(for: sourceURL)

        let data = await Task.detached(priority: .userInitiated) {
            try? Data(contentsOf: fileURL)
        }.value

        guard let data else { return nil }
        return NSImage(data: data)
    }

    // MARK: - Save

    /// Accepts pre-encoded JPEG `Data` so callers never need to send a `CGImage`
    /// across an actor/task boundary.  Encode with `DiskCacheManager.jpegData(from:)`
    /// inside the actor that owns the image, then pass the resulting `Data` here.
    func save(_ jpegData: Data, for sourceURL: URL) async {
        let fileURL = cacheURL(for: sourceURL)

        // `Data` is Sendable — safe to hand off to a detached task.
        await Task.detached(priority: .background) {
            do {
                try jpegData.write(to: fileURL, options: .atomic)
            } catch {
                Logger.process.warning("DiskCacheManager: Failed to write image to disk \(fileURL.path): \(error)")
            }
        }.value
    }

    // MARK: - Encoding helper

    /// Encodes a `CGImage` to JPEG `Data` at quality 0.7.
    /// Call this **inside the actor that owns the `CGImage`** before crossing any
    /// task or actor boundary.  Returns `nil` on encoding failure.
    nonisolated static func jpegData(from cgImage: CGImage) -> Data? {
        let mutableData = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(
            mutableData,
            UTType.jpeg.identifier as CFString,
            1,
            nil
        ) else { return nil }

        let options: [CFString: Any] = [kCGImageDestinationLossyCompressionQuality: 0.7]
        CGImageDestinationAddImage(destination, cgImage, options as CFDictionary)
        guard CGImageDestinationFinalize(destination) else { return nil }
        return mutableData as Data
    }

    // MARK: - Cache utilities

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
                    Logger.process.warning("DiskCacheManager: Failed to delete \(fileURL.path): \(error)")
                }
            }
        }.value
    }
}
