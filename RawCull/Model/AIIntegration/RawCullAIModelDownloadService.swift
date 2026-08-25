import BackgroundAssets
import Foundation
import System

nonisolated enum RawCullAIModelDownloadSource: Equatable, Sendable {
    case selfHosted(manifestURL: URL)
    case appleHosted

    static let productionManifestURL = URL(
        string: "https://github.com/rsyncOSX/RawCull-AI-Models/releases/download/v2/manifest.json",
    )!
    static let testManifestURL = URL(
        string: "https://example.invalid/rawcull/models/manifest.json",
    )!

    /// Background Assets cannot validate the relocated application bundle used
    /// by Xcode's unit-test runner. Keep live networking disabled in that host;
    /// tests inject download services when they exercise transfer behavior.
    static var liveManifestURL: URL {
        if ProcessInfo.processInfo.environment[
            "XCTestConfigurationFilePath",
        ] != nil {
            return testManifestURL
        }
        return productionManifestURL
    }

    var isConfigured: Bool {
        switch self {
        case let .selfHosted(manifestURL):
            manifestURL.scheme?.lowercased() == "https"
                && manifestURL.host?.lowercased().hasSuffix(".invalid") == false

        case .appleHosted:
            true
        }
    }
}

nonisolated enum RawCullBackgroundAssetsRuntime {
    static let macOS27Beta5Build = "26A5406e"

    static var isUsable: Bool {
        isUsable(
            operatingSystemVersionString: ProcessInfo.processInfo
                .operatingSystemVersionString,
        )
    }

    static func isUsable(
        operatingSystemVersionString: String,
    ) -> Bool {
        !operatingSystemVersionString.contains(macOS27Beta5Build)
    }

    static let unavailableMessage =
        "AI model downloads are temporarily unavailable on macOS 27 beta 5 "
            + "(build \(macOS27Beta5Build)) because of a Background Assets "
            + "validation regression."
}

nonisolated enum RawCullAIModelDownloadState: Equatable, Sendable {
    case checking
    case unavailable(reason: LocalizedStringResource)
    case licenceRequired
    case notConfigured
    case ready
    case downloading(progress: Double)
    case validating
    case installed(location: URL)
    case removing
    case failed(message: String)

    var installedLocation: URL? {
        guard case let .installed(location) = self else { return nil }
        return location
    }
}

nonisolated struct RawCullAIModelDownloadsSnapshot: Equatable, Sendable {
    let states: [RawCullAIModelDownloadID: RawCullAIModelDownloadState]
    let managedModelLocations: [RawCullAIModelDownloadID: URL]
    let acceptedLicenceModelIDs: Set<RawCullAIModelDownloadID>
}

nonisolated enum RawCullAIModelDownloadError: Error, LocalizedError, Sendable {
    case serviceNotConfigured
    case backgroundAssetsUnavailable(String)
    case releaseBlocked(String)
    case assetPackNotFound(String)
    case downloadedModelNotFound(String)
    case licenceAcceptanceRequired(String)
    case missingVerifiedLicenceText(String)

    var errorDescription: String? {
        switch self {
        case .serviceNotConfigured:
            "The AI model download service has not been configured."

        case let .backgroundAssetsUnavailable(message):
            message

        case let .releaseBlocked(modelName):
            "\(modelName) is not approved for redistribution yet."

        case let .assetPackNotFound(assetPackID):
            "The model asset pack \(assetPackID) is not present in the download manifest."

        case let .downloadedModelNotFound(path):
            "The downloaded asset pack does not contain the expected model at \(path)."

        case let .licenceAcceptanceRequired(modelName):
            "Accept the verified licence for \(modelName) before downloading it."

        case let .missingVerifiedLicenceText(modelName):
            "A verified complete licence document has not been packaged for \(modelName)."
        }
    }
}

nonisolated protocol RawCullAIModelDownloadServicing: Sendable {
    func state(
        for descriptor: RawCullAIModelDownloadDescriptor,
    ) async -> RawCullAIModelDownloadState

    func download(
        _ descriptor: RawCullAIModelDownloadDescriptor,
        progress: @escaping @MainActor @Sendable (Double) -> Void,
    ) async throws -> URL

    func remove(
        _ descriptor: RawCullAIModelDownloadDescriptor,
    ) async throws
}

/// Host-agnostic Managed Background Assets implementation.
///
/// `AssetPackManager` is the application-facing API for both self-hosted and
/// Apple-hosted packs. The downloader extension and Info.plist configuration
/// select the host without changing this service.
actor RawCullManagedBackgroundAssetsModelDownloadService:
    RawCullAIModelDownloadServicing {
    /// Compile-time switch for testing Background Assets on affected OS builds.
    /// Set to `false` and rebuild to bypass the macOS 27 beta 5 guard.
    private let isBackgroundAssetsRuntimeGuardEnabled = false
    private let source: RawCullAIModelDownloadSource
    private let backgroundAssetsRuntimeIsUsable: Bool

    init(
        source: RawCullAIModelDownloadSource,
        backgroundAssetsRuntimeIsUsable: Bool = RawCullBackgroundAssetsRuntime
            .isUsable,
    ) {
        self.source = source
        self.backgroundAssetsRuntimeIsUsable = backgroundAssetsRuntimeIsUsable
    }

    func state(
        for descriptor: RawCullAIModelDownloadDescriptor,
    ) async -> RawCullAIModelDownloadState {
        guard source.isConfigured else {
            return .notConfigured
        }
        guard !isBackgroundAssetsRuntimeGuardEnabled
            || backgroundAssetsRuntimeIsUsable
        else {
            return .failed(
                message: RawCullBackgroundAssetsRuntime.unavailableMessage,
            )
        }

        if AssetPackManager.shared.assetPackIsAvailableLocally(
            withID: descriptor.assetPackID,
        ) {
            do {
                return try .installed(location: modelURL(for: descriptor))
            } catch {
                return .failed(message: String(describing: error))
            }
        }

        do {
            let manifest = try await AssetPackManager.shared.manifest
            guard manifest.assetPack(withID: descriptor.assetPackID) != nil else {
                return .failed(
                    message: RawCullAIModelDownloadError.assetPackNotFound(
                        descriptor.assetPackID,
                    ).localizedDescription,
                )
            }
            return .ready
        } catch {
            return .failed(message: String(describing: error))
        }
    }

    func download(
        _ descriptor: RawCullAIModelDownloadDescriptor,
        progress: @escaping @MainActor @Sendable (Double) -> Void,
    ) async throws -> URL {
        guard source.isConfigured else {
            throw RawCullAIModelDownloadError.serviceNotConfigured
        }
        guard !isBackgroundAssetsRuntimeGuardEnabled
            || backgroundAssetsRuntimeIsUsable
        else {
            throw RawCullAIModelDownloadError.backgroundAssetsUnavailable(
                RawCullBackgroundAssetsRuntime.unavailableMessage,
            )
        }
        try Task.checkCancellation()

        let manifest = try await AssetPackManager.shared.manifest
        guard let assetPack = manifest.assetPack(withID: descriptor.assetPackID) else {
            throw RawCullAIModelDownloadError.assetPackNotFound(
                descriptor.assetPackID,
            )
        }

        let updates = AssetPackManager.shared.statusUpdates(
            forAssetPackWithID: descriptor.assetPackID,
        )
        let progressTask = Task { @concurrent in
            for await update in updates {
                guard !Task.isCancelled else { return }
                if case let .downloading(_, downloadProgress) = update {
                    await progress(downloadProgress.fractionCompleted)
                }
            }
        }
        defer { progressTask.cancel() }

        try await AssetPackManager.shared.ensureLocalAvailability(
            of: assetPack,
            requireLatestVersion: true,
        )
        try Task.checkCancellation()
        await progress(1)
        return try modelURL(for: descriptor)
    }

    func remove(
        _ descriptor: RawCullAIModelDownloadDescriptor,
    ) async throws {
        guard !isBackgroundAssetsRuntimeGuardEnabled
            || backgroundAssetsRuntimeIsUsable
        else {
            throw RawCullAIModelDownloadError.backgroundAssetsUnavailable(
                RawCullBackgroundAssetsRuntime.unavailableMessage,
            )
        }
        try Task.checkCancellation()
        try await AssetPackManager.shared.remove(
            assetPackWithID: descriptor.assetPackID,
        )
    }

    private nonisolated func modelURL(
        for descriptor: RawCullAIModelDownloadDescriptor,
    ) throws -> URL {
        let url = try AssetPackManager.shared.url(
            for: FilePath(descriptor.assetPackModelPath),
        )
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(
            atPath: url.path,
            isDirectory: &isDirectory,
        ), isDirectory.boolValue else {
            throw RawCullAIModelDownloadError.downloadedModelNotFound(
                descriptor.assetPackModelPath,
            )
        }
        return url
    }
}

actor RawCullAIModelDownloadCoordinator {
    private let catalog: RawCullAIModelDownloadCatalog
    private let service: any RawCullAIModelDownloadServicing
    private let acceptanceStore: any RawCullAIModelLicenceAcceptanceStoring

    init(
        catalog: RawCullAIModelDownloadCatalog = .production,
        service: any RawCullAIModelDownloadServicing,
        acceptanceStore: any RawCullAIModelLicenceAcceptanceStoring,
    ) {
        self.catalog = catalog
        self.service = service
        self.acceptanceStore = acceptanceStore
    }

    static func live(
        paths: RawCullAIPaths,
    ) -> RawCullAIModelDownloadCoordinator {
        RawCullAIModelDownloadCoordinator(
            service: RawCullManagedBackgroundAssetsModelDownloadService(
                source: .selfHosted(
                    manifestURL: RawCullAIModelDownloadSource
                        .liveManifestURL,
                ),
            ),
            acceptanceStore: RawCullAIModelLicenceAcceptanceFileStore(
                fileURL: paths.modelLicenceAcceptancesURL,
            ),
        )
    }

    func snapshot() async -> RawCullAIModelDownloadsSnapshot {
        var states: [
            RawCullAIModelDownloadID: RawCullAIModelDownloadState
        ] = [:]
        var locations: [RawCullAIModelDownloadID: URL] = [:]
        var acceptedIDs: Set<RawCullAIModelDownloadID> = []

        for descriptor in catalog.models {
            if case let .blocked(reason) = descriptor.releaseReadiness {
                states[descriptor.id] = .unavailable(reason: reason)
                continue
            }

            let serviceState = await service.state(for: descriptor)
            if let location = serviceState.installedLocation {
                states[descriptor.id] = serviceState
                locations[descriptor.id] = location
                continue
            }

            if descriptor.licence.requiresExplicitAcceptance {
                do {
                    if try await acceptanceStore.acceptance(
                        for: descriptor,
                    ) != nil {
                        acceptedIDs.insert(descriptor.id)
                        states[descriptor.id] = serviceState
                    } else {
                        states[descriptor.id] = .licenceRequired
                    }
                } catch {
                    states[descriptor.id] = .failed(
                        message: String(describing: error),
                    )
                }
            } else {
                states[descriptor.id] = serviceState
            }
        }

        return RawCullAIModelDownloadsSnapshot(
            states: states,
            managedModelLocations: locations,
            acceptedLicenceModelIDs: acceptedIDs,
        )
    }

    func acceptLicence(
        for id: RawCullAIModelDownloadID,
        rawCullVersion: String,
    ) async throws {
        let descriptor = try requiredDescriptor(for: id)
        guard descriptor.releaseReadiness.isReady else {
            throw RawCullAIModelDownloadError.releaseBlocked(
                descriptor.displayName,
            )
        }
        guard descriptor.licence.textSHA256 != nil else {
            throw RawCullAIModelDownloadError.missingVerifiedLicenceText(
                descriptor.displayName,
            )
        }
        try await acceptanceStore.recordAcceptance(
            for: descriptor,
            rawCullVersion: rawCullVersion,
        )
    }

    func download(
        _ id: RawCullAIModelDownloadID,
        progress: @escaping @MainActor @Sendable (Double) -> Void,
    ) async throws -> URL {
        let descriptor = try requiredDescriptor(for: id)
        guard descriptor.releaseReadiness.isReady else {
            throw RawCullAIModelDownloadError.releaseBlocked(
                descriptor.displayName,
            )
        }
        if descriptor.licence.requiresExplicitAcceptance {
            guard try await acceptanceStore.acceptance(
                for: descriptor,
            ) != nil else {
                throw RawCullAIModelDownloadError.licenceAcceptanceRequired(
                    descriptor.displayName,
                )
            }
        }
        return try await service.download(descriptor, progress: progress)
    }

    func remove(
        _ id: RawCullAIModelDownloadID,
    ) async throws {
        let descriptor = try requiredDescriptor(for: id)
        try await service.remove(descriptor)
    }

    private func requiredDescriptor(
        for id: RawCullAIModelDownloadID,
    ) throws -> RawCullAIModelDownloadDescriptor {
        guard let descriptor = catalog.descriptor(for: id) else {
            throw RawCullAIModelDownloadError.assetPackNotFound(id.rawValue)
        }
        return descriptor
    }
}
