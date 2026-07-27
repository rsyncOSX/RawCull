import CryptoKit
import Foundation

/// A stable fingerprint for one model asset.
///
/// Exporters should place a cryptographic fingerprint in `metadata.json`. When a
/// bundle has no manifest fingerprint, the resolver falls back to file metadata
/// so replacing an asset in place still invalidates cached artifacts.
public struct ModelAssetFingerprint: Codable, Hashable, Sendable {
    public enum Algorithm: String, Codable, Hashable, Sendable {
        case sha256
        case directoryTreeSHA256V1 = "directory-tree-sha256-v1"
        case fileMetadataV1 = "file-metadata-v1"
    }

    public let algorithm: Algorithm
    public let value: String
    public let isCryptographicallyVerified: Bool

    public init(
        algorithm: Algorithm,
        value: String,
        isCryptographicallyVerified: Bool
    ) {
        self.algorithm = algorithm
        self.value = value
        self.isCryptographicallyVerified = isCryptographicallyVerified
    }

    public var cacheIdentifier: String {
        "\(algorithm.rawValue):\(value.lowercased())"
    }
}

/// Manifest representation used by `metadata.json` under
/// `asset_fingerprints.<asset-key>`.
public struct ModelAssetFingerprintManifest: Codable, Equatable, Sendable {
    public let algorithm: ModelAssetFingerprint.Algorithm
    public let value: String

    public init(algorithm: ModelAssetFingerprint.Algorithm, value: String) {
        self.algorithm = algorithm
        self.value = value
    }
}

public enum ModelAssetFingerprintError: Error, Equatable, Sendable {
    case assetMissing(URL)
    case unsupportedAssetType(URL)
    case checksumMismatch(expected: String, actual: String)
    case unreadableAsset(URL, String)
}

/// Computes and verifies package-neutral model fingerprints.
public enum ModelAssetFingerprinter {
    public static func fingerprint(
        at assetURL: URL,
        manifest: ModelAssetFingerprintManifest? = nil
    ) throws -> ModelAssetFingerprint {
        let resolvedAssetURL = assetURL.resolvingSymlinksInPath()
        let values = try resolvedAssetURL.resourceValues(forKeys: [
            .isRegularFileKey,
            .isDirectoryKey,
        ])
        guard values.isRegularFile == true || values.isDirectory == true else {
            if !FileManager.default.fileExists(atPath: assetURL.path) {
                throw ModelAssetFingerprintError.assetMissing(assetURL)
            }
            throw ModelAssetFingerprintError.unsupportedAssetType(assetURL)
        }

        if let manifest {
            let actual = try cryptographicValue(
                at: assetURL,
                resolvedAssetURL: resolvedAssetURL,
                algorithm: manifest.algorithm
            )
            guard actual.caseInsensitiveCompare(manifest.value) == .orderedSame else {
                throw ModelAssetFingerprintError.checksumMismatch(
                    expected: manifest.value,
                    actual: actual
                )
            }
            return ModelAssetFingerprint(
                algorithm: manifest.algorithm,
                value: actual,
                isCryptographicallyVerified: true
            )
        }

        return try metadataFallback(at: resolvedAssetURL)
    }

    public static func cryptographicFingerprint(
        at assetURL: URL
    ) throws -> ModelAssetFingerprint {
        let resolvedAssetURL = assetURL.resolvingSymlinksInPath()
        let values = try resolvedAssetURL.resourceValues(forKeys: [
            .isRegularFileKey,
            .isDirectoryKey,
        ])
        let algorithm: ModelAssetFingerprint.Algorithm
        if values.isRegularFile == true {
            algorithm = .sha256
        } else if values.isDirectory == true {
            algorithm = .directoryTreeSHA256V1
        } else {
            throw ModelAssetFingerprintError.unsupportedAssetType(assetURL)
        }
        return ModelAssetFingerprint(
            algorithm: algorithm,
            value: try cryptographicValue(
                at: assetURL,
                resolvedAssetURL: resolvedAssetURL,
                algorithm: algorithm
            ),
            isCryptographicallyVerified: true
        )
    }

    private static func cryptographicValue(
        at assetURL: URL,
        resolvedAssetURL: URL,
        algorithm: ModelAssetFingerprint.Algorithm
    ) throws -> String {
        switch algorithm {
        case .sha256:
            return try sha256(ofFile: resolvedAssetURL)
        case .directoryTreeSHA256V1:
            return try sha256(ofDirectoryTree: resolvedAssetURL)
        case .fileMetadataV1:
            throw ModelAssetFingerprintError.unsupportedAssetType(assetURL)
        }
    }

    private static func metadataFallback(at assetURL: URL) throws -> ModelAssetFingerprint {
        let fileManager = FileManager.default
        let values = try assetURL.resourceValues(forKeys: [
            .isRegularFileKey,
            .isDirectoryKey,
        ])
        var byteCount: Int64 = 0
        var newestModification = Date.distantPast

        if values.isRegularFile == true {
            let attributes = try fileManager.attributesOfItem(atPath: assetURL.path)
            byteCount = (attributes[.size] as? NSNumber)?.int64Value ?? 0
            newestModification = attributes[.modificationDate] as? Date ?? .distantPast
        } else if values.isDirectory == true {
            for fileURL in try regularFiles(in: assetURL) {
                let attributes = try fileManager.attributesOfItem(atPath: fileURL.path)
                byteCount += (attributes[.size] as? NSNumber)?.int64Value ?? 0
                newestModification = max(
                    newestModification,
                    attributes[.modificationDate] as? Date ?? .distantPast
                )
            }
        } else {
            throw ModelAssetFingerprintError.unsupportedAssetType(assetURL)
        }

        let timestamp = newestModification == .distantPast
            ? "unknown"
            : String(newestModification.timeIntervalSince1970)
        return ModelAssetFingerprint(
            algorithm: .fileMetadataV1,
            value: "\(byteCount):\(timestamp)",
            isCryptographicallyVerified: false
        )
    }

    private static func sha256(ofFile url: URL) throws -> String {
        var hasher = SHA256()
        try update(&hasher, withContentsOf: url)
        return hex(hasher.finalize())
    }

    /// Directory hashing format shared with the package export tools:
    /// sorted relative path, NUL, decimal byte count, NUL, then file bytes.
    private static func sha256(ofDirectoryTree directoryURL: URL) throws -> String {
        var hasher = SHA256()
        for fileURL in try regularFiles(in: directoryURL) {
            let relativePath = String(fileURL.path.dropFirst(directoryURL.path.count + 1))
            let attributes = try FileManager.default.attributesOfItem(atPath: fileURL.path)
            let byteCount = (attributes[.size] as? NSNumber)?.int64Value ?? 0
            hasher.update(data: Data(relativePath.utf8))
            hasher.update(data: Data([0]))
            hasher.update(data: Data(String(byteCount).utf8))
            hasher.update(data: Data([0]))
            try update(&hasher, withContentsOf: fileURL)
        }
        return hex(hasher.finalize())
    }

    private static func regularFiles(in directoryURL: URL) throws -> [URL] {
        let keys: [URLResourceKey] = [.isRegularFileKey]
        guard let enumerator = FileManager.default.enumerator(
            at: directoryURL,
            includingPropertiesForKeys: keys,
            options: []
        ) else {
            throw ModelAssetFingerprintError.unreadableAsset(
                directoryURL,
                "Cannot enumerate the directory."
            )
        }
        var files: [URL] = []
        for case let fileURL as URL in enumerator {
            if try fileURL.resourceValues(forKeys: Set(keys)).isRegularFile == true {
                files.append(fileURL)
            }
        }
        return files.sorted { $0.path < $1.path }
    }

    private static func update(
        _ hasher: inout SHA256,
        withContentsOf url: URL
    ) throws {
        do {
            let handle = try FileHandle(forReadingFrom: url)
            defer { try? handle.close() }
            while let data = try handle.read(upToCount: 1_048_576), !data.isEmpty {
                hasher.update(data: data)
            }
        } catch {
            throw ModelAssetFingerprintError.unreadableAsset(
                url,
                String(describing: error)
            )
        }
    }

    private static func hex(_ digest: SHA256.Digest) -> String {
        digest.map { String(format: "%02x", $0) }.joined()
    }
}
