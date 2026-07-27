import Foundation

/// Stable identity for a model bundle supplied by a host application.
public struct ModelIdentity: Codable, Hashable, Sendable {
    public let family: String
    public let name: String
    public let sourceModel: String?
    public let assetName: String
    public let metadataVersion: String?
    public let assetFingerprint: ModelAssetFingerprint?
    private let cacheIdentifierOverride: String?

    public init(
        family: String,
        name: String,
        sourceModel: String? = nil,
        assetName: String,
        metadataVersion: String? = nil,
        cacheIdentifier: String? = nil
    ) {
        self.init(
            family: family,
            name: name,
            sourceModel: sourceModel,
            assetName: assetName,
            metadataVersion: metadataVersion,
            assetFingerprint: nil,
            cacheIdentifier: cacheIdentifier
        )
    }

    public init(
        family: String,
        name: String,
        sourceModel: String? = nil,
        assetName: String,
        metadataVersion: String? = nil,
        assetFingerprint: ModelAssetFingerprint?,
        cacheIdentifier: String? = nil
    ) {
        self.family = family
        self.name = name
        self.sourceModel = sourceModel
        self.assetName = assetName
        self.metadataVersion = metadataVersion
        self.assetFingerprint = assetFingerprint
        self.cacheIdentifierOverride = cacheIdentifier
    }

    public var cacheIdentifier: String {
        if let cacheIdentifierOverride {
            return cacheIdentifierOverride
        }
        if family.lowercased() == "sam3" {
            return "coreai-sam3-local:\(name):\(assetName)"
        }
        return [family, name, sourceModel ?? "", assetName, metadataVersion ?? ""]
            .joined(separator: ":")
    }

    /// Fingerprinted identity for new persisted artifacts and caches. The
    /// existing `cacheIdentifier` remains source- and behavior-compatible for
    /// hosts that have not migrated yet.
    public var artifactIdentifier: String {
        guard let assetFingerprint else { return cacheIdentifier }
        return "\(cacheIdentifier):\(assetFingerprint.cacheIdentifier)"
    }
}

public struct ModelBundleMetadata: Codable, Equatable, Sendable {
    public let name: String?
    public let family: String?
    public let sourceModel: String?
    public let metadataVersion: String?
    public let assets: [String: String]
    public let assetFingerprints: [String: ModelAssetFingerprintManifest]?
    public let preprocessingVersion: String?
    public let configurationVersion: String?

    public init(
        name: String? = nil,
        family: String? = nil,
        sourceModel: String? = nil,
        metadataVersion: String? = nil,
        assets: [String: String]
    ) {
        self.init(
            name: name,
            family: family,
            sourceModel: sourceModel,
            metadataVersion: metadataVersion,
            assets: assets,
            assetFingerprints: nil,
            preprocessingVersion: nil,
            configurationVersion: nil
        )
    }

    public init(
        name: String? = nil,
        family: String? = nil,
        sourceModel: String? = nil,
        metadataVersion: String? = nil,
        assets: [String: String],
        assetFingerprints: [String: ModelAssetFingerprintManifest]?,
        preprocessingVersion: String? = nil,
        configurationVersion: String? = nil
    ) {
        self.name = name
        self.family = family
        self.sourceModel = sourceModel
        self.metadataVersion = metadataVersion
        self.assets = assets
        self.assetFingerprints = assetFingerprints
        self.preprocessingVersion = preprocessingVersion
        self.configurationVersion = configurationVersion
    }

    private enum CodingKeys: String, CodingKey {
        case name
        case family
        case sourceModel = "source_model"
        case metadataVersion = "metadata_version"
        case assets
        case assetFingerprints = "asset_fingerprints"
        case preprocessingVersion = "preprocessing_version"
        case configurationVersion = "configuration_version"
    }
}
