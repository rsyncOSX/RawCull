import CryptoKit
import Foundation
@testable import RawCull
import Testing

@Suite("AI model downloads", .tags(.smoke))
struct RawCullAIModelDownloadsTests {
    @Test
    func `Production catalog includes only configured models`() throws {
        let catalog = RawCullAIModelDownloadCatalog.production

        #expect(catalog.models.map(\.id) == [
            .clipDataComp,
            .clipOpenAI,
        ])
        #expect(
            catalog.descriptor(for: .clipDataComp)?.releaseReadiness.isReady
                == true,
        )
        #expect(
            catalog.descriptor(for: .clipDataComp)?.expectedArchiveSHA256
                == "7ee162d01c18ae4ba414bc6d2d95135eadf14c6b013371513cf3a32f31bd9740",
        )
        #expect(
            catalog.descriptor(for: .clipDataComp)?.downloadByteCount
                == 282_967_218,
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
                == "31e60a9cd13bc7349a33cdc8a162a9a62ac460371e4d18406c0d3cf7ebda01e0",
        )
        #expect(
            catalog.descriptor(for: .clipOpenAI)?.downloadByteCount
                == 282_865_714,
        )
        #expect(
            RawCullAIModelDownloadSource.selfHosted(
                manifestURL: RawCullAIModelDownloadSource
                    .productionManifestURL,
            ).isConfigured,
        )

        for descriptor in catalog.models {
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
    func `macOS 27 beta 5 avoids fatal Background Assets validation`() async {
        #expect(
            !RawCullBackgroundAssetsRuntime.isUsable(
                operatingSystemVersionString:
                "Version 27.0 (Build 26A5406e)",
            ),
        )
        #expect(
            RawCullBackgroundAssetsRuntime.isUsable(
                operatingSystemVersionString:
                "Version 27.0 (Build 26A5406f)",
            ),
        )

        let service = RawCullManagedBackgroundAssetsModelDownloadService(
            source: .selfHosted(
                manifestURL: RawCullAIModelDownloadSource
                    .productionManifestURL,
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
}

private final class ModelDownloadTestBundleToken {}

private actor ModelDownloadServiceSpy:
    RawCullAIModelDownloadServicing
{
    private let currentState: RawCullAIModelDownloadState
    private let downloadURL: URL
    private var downloads = 0
    private var removals = 0

    init(
        state: RawCullAIModelDownloadState,
        downloadURL: URL,
    ) {
        currentState = state
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
        downloads += 1
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

@MainActor
private final class ModelDownloadProgressProbe {
    private(set) var values: [Double] = []

    func record(_ value: Double) {
        values.append(value)
    }
}
