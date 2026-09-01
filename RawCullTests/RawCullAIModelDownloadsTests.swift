import CryptoKit
import Foundation
@testable import RawCull
import Testing

@Suite("AI model downloads", .tags(.smoke))
struct RawCullAIModelDownloadsTests {
    @Test
    func `Production catalog includes only configured models`() throws {
        let catalog = RawCullAIModelDownloadCatalog.production
        let preparedCatalog = RawCullAIModelDownloadCatalog.prepared

        #expect(catalog.models.map(\.id) == [
            .clipDataComp,
            .clipOpenAI,
        ])
        #expect(preparedCatalog.models.map(\.id) == [
            .clipDataComp,
            .clipOpenAI,
            .efficientSAM,
            .sam3,
        ])
        #expect(RawCullAIModelInclusion.segmentationModels == [.efficientSAM])
        #expect(
            catalog.descriptor(for: .clipDataComp)?.releaseReadiness.isReady
                == true,
        )
        #expect(
            catalog.descriptor(for: .clipDataComp)?.expectedArchiveSHA256
                == "cf433dcd199b44635a4ff0260bd8e79177e4907a4cfcb2f72043066b8cbe4ef7",
        )
        #expect(
            catalog.descriptor(for: .clipDataComp)?.downloadByteCount
                == 282_966_632,
        )
        #expect(
            catalog.descriptor(for: .clipOpenAI)?.releaseReadiness.isReady
                == true,
        )
        #expect(
            catalog.descriptor(for: .clipOpenAI)?.upstreamRevision
                == "3d74acf9a28c67741b2f4f2ea7635f0aaf6f0268",
        )
        #expect(
            catalog.descriptor(for: .clipOpenAI)?.expectedArchiveSHA256
                == "e9181157c2d4012db2e6478949488f9906696a4ed78ecaa10235d9762621136c",
        )
        #expect(
            catalog.descriptor(for: .clipOpenAI)?.downloadByteCount
                == 282_866_068,
        )
        #expect(
            RawCullAIModelDownloadSource.selfHosted(
                manifestURL: RawCullAIModelDownloadSource
                    .productionManifestURL,
            ).isConfigured,
        )

        let efficientSAM = try #require(
            preparedCatalog.descriptor(for: .efficientSAM),
        )
        #expect(efficientSAM.upstreamRevision == "d525f622e6f640acf5a0fc37c7ca1f243da5bde0")
        #expect(efficientSAM.assetPackModelPath == "Models/EfficientSAM")
        #expect(efficientSAM.expectedArchiveSHA256 == nil)
        #expect(efficientSAM.downloadByteCount == nil)
        #expect(!efficientSAM.releaseReadiness.isReady)
        #expect(
            efficientSAM.licence.textSHA256
                == "c71d239df91726fc519c6eb72d318ec65820627232b2f796219e87dcf35d0ab4",
        )

        let sam3 = try #require(preparedCatalog.descriptor(for: .sam3))
        #expect(sam3.upstreamRevision == "3c879f39826c281e95690f02c7821c4de09afae7")
        #expect(sam3.assetPackModelPath == "Models/SAM3")
        #expect(!sam3.releaseReadiness.isReady)

        for descriptor in preparedCatalog.models {
            guard let resourceName =
                descriptor.licence.bundledTextResourceName
            else {
                #expect(
                    descriptor.id == .sam3,
                )
                continue
            }
            let url = try #require(licenceResourceURL(
                named: resourceName,
            ))
            let data = try Data(contentsOf: url)
            #expect(sha256(data) == descriptor.licence.textSHA256)
        }
    }

    @Test
    func `Coordinator blocks download before invoking its service`() async throws {
        let descriptor = testDescriptor(
            readiness: .blocked(reason: "Audit blocker"),
        )
        let service = ModelDownloadServiceSpy(
            state: .ready,
            downloadURL: temporaryRoot()
                .appendingPathComponent("DownloadedModel"),
        )
        let store = RawCullAIModelLicenceAcceptanceFileStore(
            fileURL: temporaryRoot()
                .appendingPathComponent("acceptances.json"),
            licenceBundle: licenceBundle(),
        )
        let coordinator = RawCullAIModelDownloadCoordinator(
            catalog: RawCullAIModelDownloadCatalog(models: [descriptor]),
            service: service,
            acceptanceStore: store,
        )

        let snapshot = await coordinator.snapshot()
        #expect(
            snapshot.states[descriptor.id]
                == .unavailable(reason: "Audit blocker"),
        )

        do {
            _ = try await coordinator.download(descriptor.id) { _ in }
            Issue.record("A distribution-blocked model was downloaded.")
        } catch let error as RawCullAIModelDownloadError {
            guard case .releaseBlocked = error else {
                Issue.record("Unexpected error: \(error)")
                return
            }
        }

        #expect(await service.downloadCount() == 0)
    }

    @Test
    func `Unconfigured managed service avoids Background Assets access`() async {
        let service = RawCullManagedBackgroundAssetsModelDownloadService(
            source: .selfHosted(
                manifestURL: RawCullAIModelDownloadSource.testManifestURL,
            ),
        )

        let state = await service.state(
            for: testDescriptor(readiness: .ready),
        )

        #expect(state == .notConfigured)
    }

    @Test
    func `affected macOS 27 Background Assets regressions are detected`() {
        #expect(
            !RawCullBackgroundAssetsRuntime.isUsable(
                operatingSystemVersionString:
                "Version 27.0 (Build 26A5406e)",
            ),
        )
        #expect(
            !RawCullBackgroundAssetsRuntime.isUsable(
                operatingSystemVersionString:
                "Version 27.0 (Build 26A5421a)",
            ),
        )
        #expect(
            RawCullBackgroundAssetsRuntime.isUsable(
                operatingSystemVersionString:
                "Version 27.0 (Build 26A5421b)",
            ),
        )
        #expect(
            RawCullBackgroundAssetsRuntime.isUsable(
                operatingSystemVersionString:
                "Version 27.0 (Build 26A5421a)",
                isDevelopmentSigned: false,
            ),
        )
    }

    @Test
    func `Affected runtime avoids Background Assets access`() async {
        let service = RawCullManagedBackgroundAssetsModelDownloadService(
            source: .selfHosted(
                manifestURL: RawCullAIModelDownloadSource.productionManifestURL,
            ),
            backgroundAssetsRuntimeIsUsable: false,
        )

        let state = await service.state(
            for: testDescriptor(readiness: .ready),
        )

        #expect(
            state == .failed(
                message: RawCullBackgroundAssetsRuntime.unavailableMessage,
            ),
        )
    }

    @Test
    func `Published CLIP models expose the Background Assets runtime failure`() async {
        let failure = RawCullAIModelDownloadState.failed(
            message: RawCullBackgroundAssetsRuntime.unavailableMessage,
        )
        let service = ModelDownloadServiceSpy(
            state: failure,
            downloadURL: temporaryRoot()
                .appendingPathComponent("DownloadedModel"),
        )
        let store = RawCullAIModelLicenceAcceptanceFileStore(
            fileURL: temporaryRoot()
                .appendingPathComponent("acceptances.json"),
            licenceBundle: licenceBundle(),
        )
        let coordinator = RawCullAIModelDownloadCoordinator(
            catalog: .production,
            service: service,
            acceptanceStore: store,
        )

        let snapshot = await coordinator.snapshot()

        #expect(snapshot.states[.clipDataComp] == failure)
        #expect(snapshot.states[.clipOpenAI] == failure)
    }

    @MainActor
    @Test
    func `Model management presents localized download failures`() async throws {
        let root = temporaryRoot()
        defer { try? FileManager.default.removeItem(at: root) }

        let descriptor = testDescriptor(readiness: .ready)
        let service = ModelDownloadServiceSpy(
            state: .ready,
            downloadURL: root.appendingPathComponent("Models/Test"),
            downloadFailureMessage: "Readable failure.",
        )
        let coordinator = RawCullAIModelDownloadCoordinator(
            catalog: RawCullAIModelDownloadCatalog(models: [descriptor]),
            service: service,
            acceptanceStore: RawCullAIModelLicenceAcceptanceFileStore(
                fileURL: root.appendingPathComponent("acceptances.json"),
                licenceBundle: licenceBundle(),
            ),
        )
        try await coordinator.acceptLicence(
            for: descriptor.id,
            rawCullVersion: "test",
        )
        let model = RawCullAIModelManagementModel(
            catalog: RawCullAIModelDownloadCatalog(models: [descriptor]),
            coordinator: coordinator,
            rawCullVersion: "test",
        )

        await model.refresh()
        model.startModelDownload(descriptor.id)
        await waitUntilPresentation(
            model,
            hasState: .failed(message: "Readable failure."),
        )
    }

    @MainActor
    @Test
    func `Verified acceptance gates and unlocks a ready download`() async throws {
        let root = temporaryRoot()
        defer { try? FileManager.default.removeItem(at: root) }

        let descriptor = testDescriptor(readiness: .ready)
        let downloadedURL = root.appendingPathComponent(
            "Models/Test",
            isDirectory: true,
        )
        let service = ModelDownloadServiceSpy(
            state: .ready,
            downloadURL: downloadedURL,
        )
        let store = RawCullAIModelLicenceAcceptanceFileStore(
            fileURL: root.appendingPathComponent("acceptances.json"),
            licenceBundle: licenceBundle(),
        )
        let coordinator = RawCullAIModelDownloadCoordinator(
            catalog: RawCullAIModelDownloadCatalog(models: [descriptor]),
            service: service,
            acceptanceStore: store,
        )

        let initial = await coordinator.snapshot()
        #expect(initial.states[descriptor.id] == .licenceRequired)

        do {
            _ = try await coordinator.download(descriptor.id) { _ in }
            Issue.record("Download started without licence acceptance.")
        } catch let error as RawCullAIModelDownloadError {
            guard case .licenceAcceptanceRequired = error else {
                Issue.record("Unexpected error: \(error)")
                return
            }
        }

        try await coordinator.acceptLicence(
            for: descriptor.id,
            rawCullVersion: "test",
        )
        let accepted = await coordinator.snapshot()
        #expect(accepted.states[descriptor.id] == .ready)
        #expect(
            accepted.acceptedLicenceModelIDs.contains(descriptor.id),
        )

        let progress = ModelDownloadProgressProbe()
        let location = try await coordinator.download(
            descriptor.id,
            progress: { value in
                progress.record(value)
            },
        )
        #expect(location == downloadedURL)
        #expect(progress.values == [0.25, 1])

        try await coordinator.remove(descriptor.id)
        #expect(await service.removalCount() == 1)
    }

    @MainActor
    @Test
    func `Model management presents progress installation and removal`() async {
        let root = temporaryRoot()
        defer { try? FileManager.default.removeItem(at: root) }

        let descriptor = testDescriptor(readiness: .ready)
        let downloadedURL = root.appendingPathComponent(
            "Models/Test",
            isDirectory: true,
        )
        let service = ModelManagementDownloadService(
            downloadURL: downloadedURL,
        )
        let coordinator = RawCullAIModelDownloadCoordinator(
            catalog: RawCullAIModelDownloadCatalog(models: [descriptor]),
            service: service,
            acceptanceStore: RawCullAIModelLicenceAcceptanceFileStore(
                fileURL: root.appendingPathComponent("acceptances.json"),
                licenceBundle: licenceBundle(),
            ),
        )
        let model = RawCullAIModelManagementModel(
            catalog: RawCullAIModelDownloadCatalog(models: [descriptor]),
            coordinator: coordinator,
            rawCullVersion: "test",
        )
        let locationsConsumer = ManagedModelLocationsConsumerSpy()
        model.bindLocationsConsumer(locationsConsumer)

        #expect(model.presentations.map(\.state) == [.checking])
        await model.refresh()
        #expect(model.presentations.map(\.state) == [.licenceRequired])

        await model.acceptModelLicence(for: descriptor.id)
        #expect(model.presentations.map(\.state) == [.ready])
        #expect(model.presentations.first?.licenceAccepted == true)

        model.startModelDownload(descriptor.id)
        await service.waitUntilProgressIsSuspended()
        #expect(model.presentations.map(\.state) == [.downloading(progress: 0.4)])

        await service.resumeDownload()
        await waitUntilPresentation(
            model,
            hasState: .installed(location: downloadedURL),
        )
        #expect(locationsConsumer.snapshots.contains([
            descriptor.id: downloadedURL,
        ]))

        await model.removeManagedModel(descriptor.id)
        #expect(model.presentations.map(\.state) == [.ready])
        #expect(locationsConsumer.snapshots.last == [:])
        #expect(await service.removalCount() == 1)
    }

    @MainActor
    @Test
    func `Cancelling model management download restores coordinator state`() async {
        let root = temporaryRoot()
        defer { try? FileManager.default.removeItem(at: root) }

        let descriptor = testDescriptor(readiness: .ready)
        let service = CancellableModelManagementDownloadService(
            downloadURL: root.appendingPathComponent("Models/Test"),
        )
        let coordinator = RawCullAIModelDownloadCoordinator(
            catalog: RawCullAIModelDownloadCatalog(models: [descriptor]),
            service: service,
            acceptanceStore: RawCullAIModelLicenceAcceptanceFileStore(
                fileURL: root.appendingPathComponent("acceptances.json"),
                licenceBundle: licenceBundle(),
            ),
        )
        let model = RawCullAIModelManagementModel(
            catalog: RawCullAIModelDownloadCatalog(models: [descriptor]),
            coordinator: coordinator,
            rawCullVersion: "test",
        )
        let locationsConsumer = ManagedModelLocationsConsumerSpy()
        model.bindLocationsConsumer(locationsConsumer)

        await model.refresh()
        await model.acceptModelLicence(for: descriptor.id)
        model.startModelDownload(descriptor.id)
        await service.waitUntilStarted()

        model.cancelModelDownload(descriptor.id)
        await waitUntilPresentation(model, hasState: .ready)

        let publishedOnlyEmptyLocations = locationsConsumer.snapshots.allSatisfy {
            $0.isEmpty
        }
        #expect(publishedOnlyEmptyLocations)
        #expect(await service.didObserveCancellation())
    }

    @Test
    func `A changed licence checksum invalidates prior acceptance`() async throws {
        let root = temporaryRoot()
        defer { try? FileManager.default.removeItem(at: root) }

        let fileURL = root.appendingPathComponent("acceptances.json")
        let original = testDescriptor(
            readiness: .ready,
        )
        let changed = testDescriptor(
            readiness: .ready,
            licenceChecksum: String(repeating: "b", count: 64),
        )

        let store = RawCullAIModelLicenceAcceptanceFileStore(
            fileURL: fileURL,
            licenceBundle: licenceBundle(),
        )
        try await store.recordAcceptance(
            for: original,
            rawCullVersion: "2.3.3",
        )
        #expect(try await store.acceptance(for: original) != nil)

        let relaunchedStore =
            RawCullAIModelLicenceAcceptanceFileStore(
                fileURL: fileURL,
                licenceBundle: licenceBundle(),
            )
        #expect(
            try await relaunchedStore.acceptance(for: original) != nil,
        )
        #expect(
            try await relaunchedStore.acceptance(for: changed) == nil,
        )
    }

    private func testDescriptor(
        readiness: RawCullAIModelReleaseReadiness,
        licenceChecksum: String =
            "6e355cc8399a572ed3db329d178a1188400fbbaed4397c28bd5b5fbac2696986",
    ) -> RawCullAIModelDownloadDescriptor {
        RawCullAIModelDownloadDescriptor(
            id: .sam3,
            displayName: "Test Model",
            purpose: "Test the model download flow.",
            publisher: "RawCull Tests",
            modelVersion: "1",
            upstreamRevision: "test-revision",
            resourceName: "Test",
            assetPackID: "no.blogspot.RawCull.models.test",
            assetPackModelPath: "Models/Test",
            upstreamSourceURL: URL(string: "https://example.com/source")!,
            modelCardURL: URL(string: "https://example.com/model-card")!,
            conversionInformationURL: URL(
                string: "https://example.com/conversion",
            ),
            expectedArchiveSHA256: String(repeating: "c", count: 64),
            downloadByteCount: 100,
            installedByteCount: 200,
            licence: RawCullAIModelLicenceDescriptor(
                name: "Test Licence",
                version: "1",
                summary: "A synthetic test licence.",
                completeTextURL: URL(
                    string: "https://example.com/licence",
                )!,
                bundledTextResourceName: "OpenCLIP-DataComp-MIT",
                textSHA256: licenceChecksum,
                requiresExplicitAcceptance: true,
            ),
            releaseReadiness: readiness,
        )
    }

    private func temporaryRoot() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent(
                "RawCullAIModelDownloadsTests",
                isDirectory: true,
            )
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
    }

    private func sha256(_ data: Data) -> String {
        SHA256.hash(data: data)
            .map { String(format: "%02x", $0) }
            .joined()
    }

    private func licenceResourceURL(named resourceName: String) -> URL? {
        if let url = Bundle.main.url(
            forResource: resourceName,
            withExtension: "txt",
        ) {
            return url
        }

        let hostedAppResources = Bundle(
            for: ModelDownloadTestBundleToken.self,
        ).bundleURL
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Resources", isDirectory: true)
        let url = hostedAppResources
            .appendingPathComponent(resourceName)
            .appendingPathExtension("txt")
        return FileManager.default.fileExists(atPath: url.path) ? url : nil
    }

    private func licenceBundle() -> Bundle {
        if Bundle.main.url(
            forResource: "OpenCLIP-DataComp-MIT",
            withExtension: "txt",
        ) != nil {
            return .main
        }

        let hostedAppURL = Bundle(
            for: ModelDownloadTestBundleToken.self,
        ).bundleURL
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        return Bundle(url: hostedAppURL) ?? .main
    }

    @MainActor
    private func waitUntilPresentation(
        _ model: RawCullAIModelManagementModel,
        hasState expectedState: RawCullAIModelDownloadState,
    ) async {
        for _ in 0 ..< 1000 {
            if model.presentations.first?.state == expectedState {
                return
            }
            await Task.yield()
        }
        let actualState = String(describing: model.presentations.first?.state)
        Issue.record(
            "Expected model-management state \(expectedState), got \(actualState).",
        )
    }
}

private final class ModelDownloadTestBundleToken {}

private actor ModelDownloadServiceSpy:
    RawCullAIModelDownloadServicing
{
    private let currentState: RawCullAIModelDownloadState
    private let downloadURL: URL
    private let downloadFailureMessage: String?
    private var downloads = 0
    private var removals = 0

    init(
        state: RawCullAIModelDownloadState,
        downloadURL: URL,
        downloadFailureMessage: String? = nil,
    ) {
        currentState = state
        self.downloadURL = downloadURL
        self.downloadFailureMessage = downloadFailureMessage
    }

    func state(
        for _: RawCullAIModelDownloadDescriptor,
    ) -> RawCullAIModelDownloadState {
        currentState
    }

    func download(
        _: RawCullAIModelDownloadDescriptor,
        progress: @escaping @MainActor @Sendable (Double) -> Void,
    ) async throws -> URL {
        downloads += 1
        if let downloadFailureMessage {
            throw RawCullAIModelDownloadError.backgroundAssetsUnavailable(
                downloadFailureMessage,
            )
        }
        await progress(0.25)
        try Task.checkCancellation()
        await progress(1)
        return downloadURL
    }

    func remove(
        _: RawCullAIModelDownloadDescriptor,
    ) {
        removals += 1
    }

    func downloadCount() -> Int {
        downloads
    }

    func removalCount() -> Int {
        removals
    }
}

private actor ModelManagementDownloadService:
    RawCullAIModelDownloadServicing
{
    private let downloadURL: URL
    private var currentState: RawCullAIModelDownloadState = .ready
    private var progressIsSuspended = false
    private var downloadMayResume = false
    private var removals = 0

    init(downloadURL: URL) {
        self.downloadURL = downloadURL
    }

    func state(
        for _: RawCullAIModelDownloadDescriptor,
    ) -> RawCullAIModelDownloadState {
        currentState
    }

    func download(
        _: RawCullAIModelDownloadDescriptor,
        progress: @escaping @MainActor @Sendable (Double) -> Void,
    ) async throws -> URL {
        await progress(-0.5)
        await progress(0.4)
        progressIsSuspended = true
        while !downloadMayResume {
            try Task.checkCancellation()
            await Task.yield()
        }
        await progress(1.5)
        currentState = .installed(location: downloadURL)
        return downloadURL
    }

    func remove(
        _: RawCullAIModelDownloadDescriptor,
    ) {
        removals += 1
        currentState = .ready
    }

    func waitUntilProgressIsSuspended() async {
        while !progressIsSuspended {
            await Task.yield()
        }
    }

    func resumeDownload() {
        downloadMayResume = true
    }

    func removalCount() -> Int {
        removals
    }
}

private actor CancellableModelManagementDownloadService:
    RawCullAIModelDownloadServicing
{
    private let downloadURL: URL
    private var started = false
    private var observedCancellation = false

    init(downloadURL: URL) {
        self.downloadURL = downloadURL
    }

    func state(
        for _: RawCullAIModelDownloadDescriptor,
    ) -> RawCullAIModelDownloadState {
        .ready
    }

    func download(
        _: RawCullAIModelDownloadDescriptor,
        progress: @escaping @MainActor @Sendable (Double) -> Void,
    ) async throws -> URL {
        started = true
        await progress(0.25)
        do {
            try await Task.sleep(for: .seconds(30))
            return downloadURL
        } catch is CancellationError {
            observedCancellation = true
            throw CancellationError()
        }
    }

    func remove(
        _: RawCullAIModelDownloadDescriptor,
    ) {}

    func waitUntilStarted() async {
        while !started {
            await Task.yield()
        }
    }

    func didObserveCancellation() -> Bool {
        observedCancellation
    }
}

@MainActor
private final class ManagedModelLocationsConsumerSpy:
    RawCullAIManagedModelLocationsApplying
{
    private(set) var snapshots: [[RawCullAIModelDownloadID: URL]] = []

    func applyManagedModelLocations(
        _ locations: [RawCullAIModelDownloadID: URL],
    ) {
        snapshots.append(locations)
    }
}

@MainActor
private final class ModelDownloadProgressProbe {
    private(set) var values: [Double] = []

    func record(_ value: Double) {
        values.append(value)
    }
}
