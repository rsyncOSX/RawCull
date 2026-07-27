import Foundation

public struct ModelBundleDescriptor: Hashable, Sendable {
    public let family: String
    public let fallbackName: String
    public let assetKey: String
    public let requiredRelativePaths: [String]
    public let acceptedAssetExtensions: Set<String>

    public init(
        family: String,
        fallbackName: String,
        assetKey: String = "main",
        requiredRelativePaths: [String] = ["tokenizer/tokenizer.json"],
        acceptedAssetExtensions: Set<String> = ["aimodel", "aimodelc"]
    ) {
        self.family = family
        self.fallbackName = fallbackName
        self.assetKey = assetKey
        self.requiredRelativePaths = requiredRelativePaths
        self.acceptedAssetExtensions = acceptedAssetExtensions
    }
}

public enum ModelBundleStatus: Equatable, Sendable {
    case valid(url: URL, identity: ModelIdentity)
    case missing(url: URL)
    case invalid(url: URL, reason: String)

    public var modelURL: URL? {
        if case let .valid(url, _) = self { url } else { nil }
    }

    public var identity: ModelIdentity? {
        if case let .valid(_, identity) = self { identity } else { nil }
    }
}

/// Validates caller-supplied model bundle URLs. It never searches app-specific paths.
public struct ModelBundleResolver: Sendable {
    public let descriptor: ModelBundleDescriptor

    public init(descriptor: ModelBundleDescriptor) {
        self.descriptor = descriptor
    }

    public func status(at url: URL) -> ModelBundleStatus {
        let fileManager = FileManager.default
        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: url.path, isDirectory: &isDirectory) else {
            return .missing(url: url)
        }
        guard isDirectory.boolValue else {
            return .invalid(url: url, reason: "The model bundle URL is not a directory.")
        }

        let metadataURL = url.appendingPathComponent("metadata.json")
        guard let data = try? Data(contentsOf: metadataURL),
              let metadata = try? JSONDecoder().decode(ModelBundleMetadata.self, from: data)
        else {
            return .invalid(url: url, reason: "metadata.json is missing or invalid.")
        }
        guard let assetName = metadata.assets[descriptor.assetKey],
              !assetName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        else {
            return .invalid(url: url, reason: "metadata.json does not define assets.\(descriptor.assetKey).")
        }
        if !descriptor.acceptedAssetExtensions.isEmpty,
           !descriptor.acceptedAssetExtensions.contains(URL(fileURLWithPath: assetName).pathExtension) {
            return .invalid(url: url, reason: "The selected asset has an unsupported extension: \(assetName).")
        }
        let assetURL = url.appendingPathComponent(assetName)
        guard fileManager.fileExists(atPath: assetURL.path) else {
            return .invalid(url: url, reason: "The selected model asset is missing: \(assetName).")
        }
        for relativePath in descriptor.requiredRelativePaths {
            guard fileManager.fileExists(atPath: url.appendingPathComponent(relativePath).path) else {
                return .invalid(url: url, reason: "A required model resource is missing: \(relativePath).")
            }
        }

        let assetFingerprint: ModelAssetFingerprint
        do {
            assetFingerprint = try ModelAssetFingerprinter.fingerprint(
                at: assetURL,
                manifest: metadata.assetFingerprints?[descriptor.assetKey]
            )
        } catch let ModelAssetFingerprintError.checksumMismatch(expected, actual) {
            return .invalid(
                url: url,
                reason: "The selected model asset checksum does not match metadata.json (expected \(expected), got \(actual))."
            )
        } catch {
            return .invalid(
                url: url,
                reason: "The selected model asset could not be fingerprinted: \(error)."
            )
        }

        return .valid(
            url: url,
            identity: ModelIdentity(
                family: metadata.family ?? descriptor.family,
                name: metadata.name ?? descriptor.fallbackName,
                sourceModel: metadata.sourceModel,
                assetName: assetName,
                metadataVersion: metadata.metadataVersion,
                assetFingerprint: assetFingerprint
            )
        )
    }

    public func firstValidURL(in candidates: [URL]) -> URL? {
        candidates.lazy.compactMap { candidate in
            if case let .valid(url, _) = status(at: candidate) { url } else { nil }
        }.first
    }

    public func identity(at url: URL) -> ModelIdentity? {
        status(at: url).identity
    }
}
