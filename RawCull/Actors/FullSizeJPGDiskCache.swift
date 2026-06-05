import CryptoKit
import Foundation
import ImageIO
import OSLog
import UniformTypeIdentifiers

actor FullSizeJPGDiskCache {
    nonisolated enum Variant: String {
        case embeddedJPG
        case developedRAW
    }

    private static let cacheKeyVersion = "v2-jpgfromraw"
    let cacheDirectory: URL

    init(cacheDirectory: URL? = nil) {
        let folder: URL
        if let cacheDirectory {
            folder = cacheDirectory
        } else {
            let paths = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)
            folder = paths[0].appendingPathComponent("no.blogspot.RawCull/FullsizeJPGs")
        }
        self.cacheDirectory = folder
        do {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        } catch {
            Logger.process.warning("FullSizeJPGDiskCache: Failed to create directory \(folder): \(error)")
        }
    }

    private func cacheURL(for sourceURL: URL, variant: Variant) -> URL {
        let standardizedPath = sourceURL.standardized.path
        let variantKey = variant == .embeddedJPG ? "" : ":\(variant.rawValue)"
        let data = Data("\(Self.cacheKeyVersion):\(standardizedPath)\(variantKey)".utf8)
        let digest = Insecure.MD5.hash(data: data)
        let hash = digest.map { String(format: "%02x", $0) }.joined()
        return cacheDirectory.appendingPathComponent(hash).appendingPathExtension("jpg")
    }

    func contains(for sourceURL: URL, variant: Variant = .embeddedJPG) async -> Bool {
        let fileURL = cacheURL(for: sourceURL, variant: variant)

        return await Task.detached(priority: .utility) {
            FileManager.default.fileExists(atPath: fileURL.path)
        }.value
    }

    /// Loads a cached full-size JPEG as a `CGImage`.
    /// Uses `kCGImageSourceShouldCache: false` and `CGImageSourceRemoveCacheAtIndex`
    /// to prevent ImageIO from retaining the decoded ~188 MB pixel buffer in its
    /// process-level cache (matches the pattern in `ZoomPreviewHandler.loadCGImage`).
    func load(for sourceURL: URL, variant: Variant = .embeddedJPG) async -> CGImage? {
        let fileURL = cacheURL(for: sourceURL, variant: variant)

        return await Task.detached(priority: .userInitiated) {
            let sourceOptions = [kCGImageSourceShouldCache: false] as CFDictionary
            guard let imageSource = CGImageSourceCreateWithURL(fileURL as CFURL, sourceOptions) else {
                return nil
            }
            let decodeOptions = [kCGImageSourceShouldCache: false] as CFDictionary
            guard let cgImage = CGImageSourceCreateImageAtIndex(imageSource, 0, decodeOptions) else {
                return nil
            }
            CGImageSourceRemoveCacheAtIndex(imageSource, 0)
            return cgImage
        }.value
    }

    func save(_ jpegData: Data, for sourceURL: URL, variant: Variant = .embeddedJPG) async {
        let fileURL = cacheURL(for: sourceURL, variant: variant)

        await Task.detached(priority: .background) {
            do {
                try jpegData.write(to: fileURL, options: .atomic)
            } catch {
                Logger.process.warning("FullSizeJPGDiskCache: Failed to write image to disk \(fileURL.path): \(error)")
            }
        }.value
    }

    /// Encodes a `CGImage` to JPEG `Data` at quality 0.85 (higher than the 0.7 used
    /// for thumbnails — full-size JPEGs are pixel-peeped at zoom).
    /// Call this inside the actor that owns the `CGImage` before crossing any task or actor boundary.
    nonisolated static func jpegData(from cgImage: CGImage) -> Data? {
        let mutableData = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(
            mutableData,
            UTType.jpeg.identifier as CFString,
            1,
            nil,
        ) else { return nil }

        let options: [CFString: Any] = [kCGImageDestinationLossyCompressionQuality: 0.85]
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
                    Logger.process.warning("FullSizeJPGDiskCache: Failed to get size for \(fileURL.path): \(error)")
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
                    Logger.process.warning("FullSizeJPGDiskCache: Failed to delete \(fileURL.path): \(error)")
                }
            }
        }.value
    }
}
