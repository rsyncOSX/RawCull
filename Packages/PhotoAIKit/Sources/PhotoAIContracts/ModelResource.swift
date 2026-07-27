import Foundation

/// Package-neutral identity and artifact versions for a model family.
public struct ModelResourceDescriptor: Hashable, Sendable {
    public let kind: String
    public let bundleDescriptor: ModelBundleDescriptor
    public let preprocessingVersion: String
    public let configurationVersion: String

    public init(
        kind: String,
        bundleDescriptor: ModelBundleDescriptor,
        preprocessingVersion: String,
        configurationVersion: String
    ) {
        self.kind = kind
        self.bundleDescriptor = bundleDescriptor
        self.preprocessingVersion = preprocessingVersion
        self.configurationVersion = configurationVersion
    }

    public static let clip = ModelResourceDescriptor(
        kind: "embedding",
        bundleDescriptor: ModelBundleDescriptor(
            family: "clip",
            fallbackName: "CLIP",
            requiredRelativePaths: ["tokenizer/tokenizer.json"]
        ),
        preprocessingVersion: "clip-srgb-bilinear-chw-v1",
        configurationVersion: "coreai-clip-image-v1"
    )

    public static let sam3 = ModelResourceDescriptor(
        kind: "segmenter",
        bundleDescriptor: ModelBundleDescriptor(
            family: "sam3",
            fallbackName: "SAM3",
            requiredRelativePaths: ["tokenizer/tokenizer.json"]
        ),
        preprocessingVersion: "sam3-bounded-image-v1",
        configurationVersion: "coreai-sam3-mask-v1"
    )
}

public struct ModelResource: Equatable, Sendable {
    public let descriptor: ModelResourceDescriptor
    public let bundleURL: URL
    public let assetURL: URL
    public let identity: ModelIdentity

    public init(
        descriptor: ModelResourceDescriptor,
        bundleURL: URL,
        assetURL: URL,
        identity: ModelIdentity
    ) {
        self.descriptor = descriptor
        self.bundleURL = bundleURL
        self.assetURL = assetURL
        self.identity = identity
    }
}

/// Shared package-level capability state. User-facing wording remains in the host.
public enum ModelCapabilityStatus: Equatable, Sendable {
    case available(ModelResource)
    case missing(candidates: [URL])
    case invalid(url: URL, reason: String)

    public var resource: ModelResource? {
        if case let .available(resource) = self { resource } else { nil }
    }

    public var isAvailable: Bool { resource != nil }
}

/// Resolves caller-ordered candidates without owning application path policy.
public struct ModelResourceResolver: Sendable {
    public let descriptor: ModelResourceDescriptor

    public init(descriptor: ModelResourceDescriptor) {
        self.descriptor = descriptor
    }

    public func status(in candidates: [URL]) -> ModelCapabilityStatus {
        let resolver = ModelBundleResolver(descriptor: descriptor.bundleDescriptor)
        for candidate in candidates {
            switch resolver.status(at: candidate) {
            case let .valid(url, identity):
                return .available(ModelResource(
                    descriptor: descriptor,
                    bundleURL: url,
                    assetURL: url.appendingPathComponent(identity.assetName),
                    identity: identity
                ))
            case .missing:
                continue
            case let .invalid(url, reason):
                return .invalid(url: url, reason: reason)
            }
        }
        return .missing(candidates: candidates)
    }
}

public enum ModelProviderFactoryError: Error, Equatable, Sendable {
    case unavailable(ModelCapabilityStatus)
}

/// Shared validation + provider construction mechanics. The backend supplies
/// only its constructor; the host supplies candidate locations.
public struct ModelProviderFactory<Provider: Sendable>: Sendable {
    public let descriptor: ModelResourceDescriptor
    private let makeProvider: @Sendable (URL) throws -> Provider

    public init(
        descriptor: ModelResourceDescriptor,
        makeProvider: @escaping @Sendable (URL) throws -> Provider
    ) {
        self.descriptor = descriptor
        self.makeProvider = makeProvider
    }

    public func capability(in candidates: [URL]) -> ModelCapabilityStatus {
        ModelResourceResolver(descriptor: descriptor).status(in: candidates)
    }

    public func makeProvider(from resource: ModelResource) throws -> Provider {
        try makeProvider(resource.bundleURL)
    }

    public func makeFirstAvailable(in candidates: [URL]) throws -> Provider {
        let status = capability(in: candidates)
        guard let resource = status.resource else {
            throw ModelProviderFactoryError.unavailable(status)
        }
        return try makeProvider(from: resource)
    }
}
