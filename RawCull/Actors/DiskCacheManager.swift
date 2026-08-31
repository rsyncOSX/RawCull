import AppKit
import CryptoKit
import Foundation
import OSLog
import RawParserKit
import UniformTypeIdentifiers

actor DiskCacheManager {
    let cacheDirectory: URL
    private let schemaDirectory: URL

    init(cacheDirectory: URL? = nil) {
        let folder: URL
        if let cacheDirectory {
            folder = cacheDirectory
        } else {
            let paths = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)
            folder = paths[0].appendingPathComponent("no.blogspot.RawCull/Thumbnails")
        }
        let currentSchemaDirectory = folder.appendingPathComponent(
            ThumbnailCacheKey.schemaVersion,
            isDirectory: true,
        )
        self.cacheDirectory = folder
        self.schemaDirectory = currentSchemaDirectory
        do {
            let fileManager = FileManager.default
            try fileManager.createDirectory(at: currentSchemaDirectory, withIntermediateDirectories: true)

            // Versions before the representation-aware schema stored JPEGs
            // directly in the thumbnail root. Remove only those known legacy
            // thumbnail entries; sibling directories and unrelated state are
            // intentionally outside this migration.
            let legacyEntries = try fileManager.contentsOfDirectory(
                at: folder,
                includingPropertiesForKeys: [.isRegularFileKey],
                options: .skipsHiddenFiles,
            )
            for entry in legacyEntries where entry.pathExtension.lowercased() == "jpg" {
                let values = try entry.resourceValues(forKeys: [.isRegularFileKey])
                if values.isRegularFile == true {
                    try fileManager.removeItem(at: entry)
                }
            }
        } catch {
            Logger.process.warning("DiskCacheManager: Failed to create directory \(folder): \(error)")
        }
    }

    /// Deterministic cache filename derived from the complete source and
    /// representation identity.
    ///
    /// Formula: `schemaDirectory / MD5(key.cacheIdentifier.utf8).hex + ".jpg"`.
    /// MD5 is used as a non-cryptographic filename hash — we only need a
    /// fixed-width, filesystem-safe string with a vanishingly small collision
    /// rate across one user's thumbnail cache. `CryptoKit.Insecure.MD5` makes
    /// the "not-for-security" intent explicit.
    private func cacheURL(for key: ThumbnailCacheKey) -> URL {
        let data = Data(key.cacheIdentifier.utf8)
        let digest = Insecure.MD5.hash(data: data)
        let hash = digest.map { String(format: "%02x", $0) }.joined()
        return schemaDirectory.appendingPathComponent(hash).appendingPathExtension("jpg")
    }

    func cacheFileURL(for key: ThumbnailCacheKey) -> URL {
        cacheURL(for: key)
    }

    func load(for key: ThumbnailCacheKey) async -> NSImage? {
        let fileURL = cacheURL(for: key)

        return await Task.detached(priority: .userInitiated) {
            guard FileManager.default.fileExists(atPath: fileURL.path) else { return nil }
            guard let image = OrientationNormalizedImageLoader.loadCGImage(from: fileURL) else {
                // A partial or corrupt JPEG must be a recoverable miss, never a
                // sticky cache failure. Limit deletion to this schema entry.
                try? FileManager.default.removeItem(at: fileURL)
                return nil
            }
            return NSImage(cgImage: image, size: NSSize(width: image.width, height: image.height))
        }.value
    }

    // MARK: - Save

    /// Accepts pre-encoded JPEG `Data` so callers never need to send a `CGImage`
    /// across an actor/task boundary.  Encode with `DiskCacheManager.jpegData(from:)`
    /// inside the actor that owns the image, then pass the resulting `Data` here.
    func save(_ jpegData: Data, for key: ThumbnailCacheKey) async {
        guard !Task.isCancelled else { return }
        let fileURL = cacheURL(for: key)

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
            nil,
        ) else { return nil }

        let options: [CFString: Any] = [kCGImageDestinationLossyCompressionQuality: 0.7]
        CGImageDestinationAddImage(destination, cgImage, options as CFDictionary)
        guard CGImageDestinationFinalize(destination) else { return nil }
        return mutableData as Data
    }

    // MARK: - Cache utilities

    func getDiskCacheSize() async -> Int {
        let directory = schemaDirectory

        return await Task.detached(priority: .utility) {
            let fileManager = FileManager.default
            let resourceKeys: [URLResourceKey] = [.totalFileAllocatedSizeKey]

            guard let urls = try? fileManager.contentsOfDirectory(
                at: directory,
                includingPropertiesForKeys: resourceKeys,
                options: .skipsHiddenFiles,
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
        let directory = schemaDirectory

        await Task.detached(priority: .utility) {
            let fileManager = FileManager.default
            let resourceKeys: [URLResourceKey] = [.contentModificationDateKey, .totalFileAllocatedSizeKey]

            guard let urls = try? fileManager.contentsOfDirectory(
                at: directory,
                includingPropertiesForKeys: resourceKeys,
                options: .skipsHiddenFiles,
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
