import CoreGraphics
import CryptoKit
import Foundation
import ImageIO
import OSLog
import PhotoAIContracts
import UniformTypeIdentifiers

/// PNG + JSON SAM3 mask store. The host must inject the cache directory.
public actor SubjectMaskDiskStore: SubjectMaskStoring, SubjectMaskCacheMetadataProviding {
    private static let cacheKeyVersion = "v1-sam3mask"
    private static let logger = Logger(subsystem: "PhotoAIKit", category: "SubjectMaskDiskStore")

    public nonisolated let cacheDirectory: URL

    public init(cacheDirectory: URL) throws {
        self.cacheDirectory = cacheDirectory
        try FileManager.default.createDirectory(at: cacheDirectory, withIntermediateDirectories: true)
    }

    public func load(for key: SubjectMaskStorageKey) async -> SubjectSegmentationResult? {
        guard !Task.isCancelled else { return nil }
        let candidates = cacheURLCandidates(for: key)
        return await Task { @concurrent in
            var loaded: (SubjectMaskDiskMetadata, CGImage)?
            for urls in candidates {
                if let metadataData = try? Data(contentsOf: urls.metadata),
                   let metadata = try? JSONDecoder().decode(SubjectMaskDiskMetadata.self, from: metadataData),
                   metadata.matches(key),
                   let mask = Self.loadPNG(from: urls.mask) {
                    loaded = (metadata, mask)
                    break
                }
            }
            guard let (metadata, mask) = loaded else { return nil }

            let timing = SubjectSegmentationTiming(totalMilliseconds: 0)
            let inputSize = CGSize(width: metadata.inputWidth, height: metadata.inputHeight)
            let outputSize = CGSize(width: mask.width, height: mask.height)
            let diagnostics = SubjectSegmentationDiagnostics(
                modelIdentity: key.modelIdentity,
                prompt: key.prompt,
                confidence: metadata.confidence,
                timing: timing,
                inputSize: inputSize,
                outputSize: outputSize
            )
            return SubjectSegmentationResult(
                sourceID: key.source.id,
                requestID: UUID(),
                prompt: key.prompt,
                mask: mask,
                confidence: metadata.confidence,
                modelIdentity: key.modelIdentity,
                inputSize: inputSize,
                outputSize: outputSize,
                timing: timing,
                diagnostics: diagnostics
            )
        }.value
    }

    public nonisolated func metadataFileExists(for key: SubjectMaskStorageKey) -> Bool {
        cacheURLCandidates(for: key).contains {
            FileManager.default.fileExists(atPath: $0.metadata.path)
        }
    }

    public func contains(_ key: SubjectMaskStorageKey) async -> Bool {
        guard !Task.isCancelled else { return false }
        let candidates = cacheURLCandidates(for: key)
        return await Task { @concurrent in
            candidates.contains { urls in
                guard let metadataData = try? Data(contentsOf: urls.metadata),
                      let metadata = try? JSONDecoder().decode(SubjectMaskDiskMetadata.self, from: metadataData),
                      metadata.matches(key),
                      Self.loadPNG(from: urls.mask) != nil
                else { return false }
                return true
            }
        }.value
    }

    public func save(
        _ result: SubjectSegmentationResult,
        for key: SubjectMaskStorageKey
    ) async throws {
        guard let pngData = Self.pngData(from: result.mask) else {
            throw SubjectMaskDiskStoreError.pngEncodingFailed
        }
        let urls = cacheURLs(for: key)
        let metadata = SubjectMaskDiskMetadata(
            prompt: result.prompt,
            confidence: result.confidence,
            modelVersion: result.modelIdentity.cacheIdentifier,
            modelFingerprint: result.modelIdentity.artifactIdentifier,
            inputMaxSide: key.inputMaxSide,
            fileSize: key.sourceIdentity.fileSize,
            modificationDate: key.sourceIdentity.modificationDate,
            inputWidth: result.inputSize.width,
            inputHeight: result.inputSize.height,
            outputWidth: CGFloat(result.mask.width),
            outputHeight: CGFloat(result.mask.height)
        )
        let metadataData = try JSONEncoder().encode(metadata)
        try await Task { @concurrent in
            try pngData.write(to: urls.mask, options: .atomic)
            try metadataData.write(to: urls.metadata, options: .atomic)
        }.value
    }

    public func cacheModificationDate(for key: SubjectMaskStorageKey) async -> Date? {
        let metadataURLs = cacheURLCandidates(for: key).map(\.metadata)
        return await Task { @concurrent in
            for metadataURL in metadataURLs {
                if let date = (try? FileManager.default.attributesOfItem(
                    atPath: metadataURL.path
                )[.modificationDate]) as? Date {
                    return date
                }
            }
            return nil
        }.value
    }

    public func cacheMetadata(
        for key: SubjectMaskStorageKey
    ) async -> SubjectMaskCacheMetadata? {
        guard metadataFileExists(for: key) else { return nil }
        return SubjectMaskCacheMetadata(
            modificationDate: await cacheModificationDate(for: key)
        )
    }

    public func diskUsage() async -> Int {
        let directory = cacheDirectory
        return await Task { @concurrent in
            let keys: Set<URLResourceKey> = [.totalFileAllocatedSizeKey]
            guard let urls = try? FileManager.default.contentsOfDirectory(
                at: directory,
                includingPropertiesForKeys: Array(keys),
                options: .skipsHiddenFiles
            ) else { return 0 }
            return urls.reduce(into: 0) { total, url in
                total += (try? url.resourceValues(forKeys: keys).totalFileAllocatedSize) ?? 0
            }
        }.value
    }

    public func prune(olderThanDays days: Int = 90) async {
        let directory = cacheDirectory
        await Task { @concurrent in
            let keys: Set<URLResourceKey> = [.contentModificationDateKey]
            guard let urls = try? FileManager.default.contentsOfDirectory(
                at: directory,
                includingPropertiesForKeys: Array(keys),
                options: .skipsHiddenFiles
            ) else { return }
            guard let cutoff = Calendar.current.date(byAdding: .day, value: -days, to: Date()) else {
                return
            }
            for url in urls {
                do {
                    if let date = try url.resourceValues(forKeys: keys).contentModificationDate,
                       date < cutoff {
                        try FileManager.default.removeItem(at: url)
                    }
                } catch {
                    Self.logger.warning("Could not prune \(url.path, privacy: .private): \(String(describing: error))")
                }
            }
        }.value
    }

    public func removeAll() async {
        let directory = cacheDirectory
        await Task { @concurrent in
            guard let urls = try? FileManager.default.contentsOfDirectory(
                at: directory,
                includingPropertiesForKeys: nil,
                options: .skipsHiddenFiles
            ) else { return }
            for url in urls { try? FileManager.default.removeItem(at: url) }
        }.value
    }

    private nonisolated func cacheURLs(
        for key: SubjectMaskStorageKey
    ) -> (mask: URL, metadata: URL) {
        let rawKey = [
            Self.cacheKeyVersion,
            key.source.url.standardized.path,
            key.prompt.rawValue,
            key.modelIdentity.artifactIdentifier,
            String(key.inputMaxSide),
        ].joined(separator: ":")
        let digest = Insecure.MD5.hash(data: Data(rawKey.utf8))
        let hash = digest.map { String(format: "%02x", $0) }.joined()
        let baseURL = cacheDirectory.appendingPathComponent(hash)
        return (baseURL.appendingPathExtension("png"), baseURL.appendingPathExtension("json"))
    }

    private nonisolated func legacyCacheURLs(
        for key: SubjectMaskStorageKey
    ) -> (mask: URL, metadata: URL) {
        let rawKey = [
            Self.cacheKeyVersion,
            key.source.url.standardized.path,
            key.prompt.rawValue,
            key.modelIdentity.cacheIdentifier,
            String(key.inputMaxSide),
        ].joined(separator: ":")
        let digest = Insecure.MD5.hash(data: Data(rawKey.utf8))
        let hash = digest.map { String(format: "%02x", $0) }.joined()
        let baseURL = cacheDirectory.appendingPathComponent(hash)
        return (baseURL.appendingPathExtension("png"), baseURL.appendingPathExtension("json"))
    }

    private nonisolated func cacheURLCandidates(
        for key: SubjectMaskStorageKey
    ) -> [(mask: URL, metadata: URL)] {
        let current = cacheURLs(for: key)
        let legacy = legacyCacheURLs(for: key)
        return current.metadata == legacy.metadata ? [current] : [current, legacy]
    }

    public nonisolated static func pngData(from image: CGImage) -> Data? {
        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(
            data,
            UTType.png.identifier as CFString,
            1,
            nil
        ) else { return nil }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else { return nil }
        return data as Data
    }

    private nonisolated static func loadPNG(from url: URL) -> CGImage? {
        let options = [kCGImageSourceShouldCache: false] as CFDictionary
        guard let source = CGImageSourceCreateWithURL(url as CFURL, options),
              let image = CGImageSourceCreateImageAtIndex(source, 0, options)
        else { return nil }
        CGImageSourceRemoveCacheAtIndex(source, 0)
        return image
    }
}

public struct SubjectMaskDiskMetadata: Codable, Equatable, Sendable {
    public let prompt: SubjectSegmentationPrompt
    public let confidence: Float
    public let modelVersion: String
    public let modelFingerprint: String?
    public let inputMaxSide: Int
    public let fileSize: Int64?
    public let modificationDate: Date?
    public let inputWidth: CGFloat
    public let inputHeight: CGFloat
    public let outputWidth: CGFloat
    public let outputHeight: CGFloat

    public init(
        prompt: SubjectSegmentationPrompt,
        confidence: Float,
        modelVersion: String,
        modelFingerprint: String? = nil,
        inputMaxSide: Int,
        fileSize: Int64?,
        modificationDate: Date?,
        inputWidth: CGFloat,
        inputHeight: CGFloat,
        outputWidth: CGFloat,
        outputHeight: CGFloat
    ) {
        self.prompt = prompt
        self.confidence = confidence
        self.modelVersion = modelVersion
        self.modelFingerprint = modelFingerprint
        self.inputMaxSide = inputMaxSide
        self.fileSize = fileSize
        self.modificationDate = modificationDate
        self.inputWidth = inputWidth
        self.inputHeight = inputHeight
        self.outputWidth = outputWidth
        self.outputHeight = outputHeight
    }

    public func matches(_ key: SubjectMaskStorageKey) -> Bool {
        prompt == key.prompt
            && (modelFingerprint.map { $0 == key.modelIdentity.artifactIdentifier }
                ?? (key.modelIdentity.assetFingerprint == nil
                    && modelVersion == key.modelIdentity.cacheIdentifier))
            && inputMaxSide == key.inputMaxSide
            && fileSize == key.sourceIdentity.fileSize
            && modificationDate == key.sourceIdentity.modificationDate
    }
}

public enum SubjectMaskDiskStoreError: Error, Sendable {
    case pngEncodingFailed
}
