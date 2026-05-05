import CryptoKit
import Foundation
import ImageIO
import OSLog
import UniformTypeIdentifiers

actor FullSizeJPGDiskCache {
    let cacheDirectory: URL

    init() {
        let paths = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)
        let folder = paths[0].appendingPathComponent("no.blogspot.RawCull/FullsizeJPGs")
        cacheDirectory = folder
        do {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        } catch {
            Logger.process.warning("FullSizeJPGDiskCache: Failed to create directory \(folder): \(error)")
        }
    }

    private func cacheURL(for sourceURL: URL) -> URL {
        let standardizedPath = sourceURL.standardized.path
        let data = Data(standardizedPath.utf8)
        let digest = Insecure.MD5.hash(data: data)
        let hash = digest.map { String(format: "%02x", $0) }.joined()
        return cacheDirectory.appendingPathComponent(hash).appendingPathExtension("jpg")
    }

    /// Loads a cached full-size JPEG as a `CGImage`.
    /// Uses `kCGImageSourceShouldCache: false` and `CGImageSourceRemoveCacheAtIndex`
    /// to prevent ImageIO from retaining the decoded ~188 MB pixel buffer in its
    /// process-level cache (matches the pattern in `ZoomPreviewHandler.loadCGImage`).
    func load(for sourceURL: URL) async -> CGImage? {
        let fileURL = cacheURL(for: sourceURL)

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

    func save(_ jpegData: Data, for sourceURL: URL) async {
        let fileURL = cacheURL(for: sourceURL)

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
}
