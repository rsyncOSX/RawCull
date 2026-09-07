import Foundation

nonisolated struct RawCullAIModelDownloadPresentation: Equatable, Identifiable, Sendable {
    let descriptor: RawCullAIModelDownloadDescriptor
    let state: RawCullAIModelDownloadState
    let licenceAccepted: Bool

    var id: RawCullAIModelDownloadID {
        descriptor.id
    }
}

@MainActor
protocol RawCullAIManagedModelLocationsApplying: AnyObject {
    func applyManagedModelLocations(
        _ locations: [RawCullAIModelDownloadID: URL],
    ) async
}

/// Settings-facing lifecycle state for downloadable AI model resources.
///
/// SwiftUI sees prepared presentation values and actions. The catalog,
/// coordinator, acceptance store, service, locations, and task ownership remain
/// private to this focused model-management boundary.
@Observable @MainActor
final class RawCullAIModelManagementModel {
    private(set) var presentations: [RawCullAIModelDownloadPresentation]

    @ObservationIgnored private let catalog: RawCullAIModelDownloadCatalog
    @ObservationIgnored private let coordinator: RawCullAIModelDownloadCoordinator
    @ObservationIgnored private let rawCullVersion: String
    @ObservationIgnored private weak var locationsConsumer:
        (any RawCullAIManagedModelLocationsApplying)?
    @ObservationIgnored private var states: [
        RawCullAIModelDownloadID: RawCullAIModelDownloadState
    ]
    @ObservationIgnored private var acceptedLicenceModelIDs:
        Set<RawCullAIModelDownloadID> = []
    @ObservationIgnored private var downloadTasks:
        [RawCullAIModelDownloadID: Task<Void, Never>] = [:]
    @ObservationIgnored private var refreshGeneration = 0
    @ObservationIgnored private var removingModelIDs: Set<RawCullAIModelDownloadID> = []

    init(
        catalog: RawCullAIModelDownloadCatalog = .production,
        coordinator: RawCullAIModelDownloadCoordinator,
        rawCullVersion: String,
    ) {
        self.catalog = catalog
        self.coordinator = coordinator
        self.rawCullVersion = rawCullVersion
        let initialStates = Dictionary(
            uniqueKeysWithValues: catalog.models.map {
                ($0.id, RawCullAIModelDownloadState.checking)
            },
        )
        states = initialStates
        presentations = Self.makePresentations(
            catalog: catalog,
            states: initialStates,
            acceptedLicenceModelIDs: [],
        )
    }

    convenience init(
        paths: RawCullAIPaths,
        catalog: RawCullAIModelDownloadCatalog = .production,
        coordinator: RawCullAIModelDownloadCoordinator? = nil,
        rawCullVersion: String? = nil,
    ) {
        self.init(
            catalog: catalog,
            coordinator: coordinator ?? .live(paths: paths, catalog: catalog),
            rawCullVersion: rawCullVersion
                ?? Bundle.main.object(
                    forInfoDictionaryKey: "CFBundleShortVersionString",
                ) as? String
                ?? "unknown",
        )
    }

    func bindLocationsConsumer(
        _ consumer: any RawCullAIManagedModelLocationsApplying,
    ) {
        precondition(
            locationsConsumer == nil,
            "RawCullAIModelManagementModel locations consumer may only be bound once.",
        )
        locationsConsumer = consumer
    }

    func refresh() async {
        await refresh(completing: nil)
    }

    private func refresh(completing completedID: RawCullAIModelDownloadID?) async {
        refreshGeneration &+= 1
        let generation = refreshGeneration
        let snapshot = await coordinator.snapshot()
        guard !Task.isCancelled || completedID != nil else { return }

        if refreshGeneration == generation {
            apply(snapshot: snapshot, completing: completedID)
        } else if let completedID, let state = snapshot.states[completedID] {
            // Another row may have progressed while this operation finished.
            // Its progress must not strand this row in Downloading/Removing.
            setState(state, for: completedID)
        } else {
            return
        }
        await locationsConsumer?.applyManagedModelLocations(
            states.compactMapValues(\.installedLocation),
        )
    }

    func acceptModelLicence(
        for id: RawCullAIModelDownloadID,
    ) async {
        do {
            try await coordinator.acceptLicence(
                for: id,
                rawCullVersion: rawCullVersion,
            )
            await refresh()
        } catch is CancellationError {
            return
        } catch {
            setState(.failed(message: error.localizedDescription), for: id)
        }
    }

    func startModelDownload(
        _ id: RawCullAIModelDownloadID,
    ) {
        guard downloadTasks[id] == nil, !removingModelIDs.contains(id) else { return }
        guard let state = states[id], state.canStartDownload else { return }

        setState(.downloading(progress: 0), for: id)
        downloadTasks[id] = Task { [weak self] in
            guard let self else { return }
            await performModelDownload(id)
        }
    }

    func cancelModelDownload(
        _ id: RawCullAIModelDownloadID,
    ) {
        downloadTasks[id]?.cancel()
    }

    func removeManagedModel(
        _ id: RawCullAIModelDownloadID,
    ) async {
        guard downloadTasks[id] == nil, !removingModelIDs.contains(id) else { return }
        removingModelIDs.insert(id)
        defer { removingModelIDs.remove(id) }
        setState(.removing, for: id)
        do {
            try await coordinator.remove(id)
            await refresh(completing: id)
        } catch is CancellationError {
            await refresh(completing: id)
        } catch {
            setState(.failed(message: error.localizedDescription), for: id)
        }
    }

    private func performModelDownload(
        _ id: RawCullAIModelDownloadID,
    ) async {
        defer { downloadTasks[id] = nil }

        do {
            _ = try await coordinator.download(
                id,
                progress: { [weak self] progress in
                    guard let self, !Task.isCancelled else { return }
                    setState(
                        .downloading(progress: min(max(progress, 0), 1)),
                        for: id,
                    )
                },
            )
            try Task.checkCancellation()
            setState(.validating, for: id)
            await refresh(completing: id)
        } catch is CancellationError {
            await refresh(completing: id)
        } catch {
            setState(.failed(message: error.localizedDescription), for: id)
        }
    }

    private func apply(
        snapshot: RawCullAIModelDownloadsSnapshot,
        completing completedID: RawCullAIModelDownloadID?,
    ) {
        var refreshedStates = snapshot.states
        let activeIDs = Set(downloadTasks.keys).union(removingModelIDs)
        for id in activeIDs where id != completedID {
            refreshedStates[id] = states[id]
        }
        states = refreshedStates
        acceptedLicenceModelIDs = snapshot.acceptedLicenceModelIDs
        rebuildPresentations()
    }

    private func setState(
        _ state: RawCullAIModelDownloadState,
        for id: RawCullAIModelDownloadID,
    ) {
        // Invalidate snapshots requested before this operation/progress change.
        refreshGeneration &+= 1
        states[id] = state
        rebuildPresentations()
    }

    private func rebuildPresentations() {
        presentations = Self.makePresentations(
            catalog: catalog,
            states: states,
            acceptedLicenceModelIDs: acceptedLicenceModelIDs,
        )
    }

    private static func makePresentations(
        catalog: RawCullAIModelDownloadCatalog,
        states: [RawCullAIModelDownloadID: RawCullAIModelDownloadState],
        acceptedLicenceModelIDs: Set<RawCullAIModelDownloadID>,
    ) -> [RawCullAIModelDownloadPresentation] {
        catalog.models.map { descriptor in
            RawCullAIModelDownloadPresentation(
                descriptor: descriptor,
                state: states[descriptor.id] ?? .checking,
                licenceAccepted: acceptedLicenceModelIDs.contains(descriptor.id),
            )
        }
    }
}

private nonisolated extension RawCullAIModelDownloadState {
    var canStartDownload: Bool {
        switch self {
        case .ready, .failed:
            true

        case .checking, .unavailable, .licenceRequired, .notConfigured,
             .downloading, .validating, .installed, .removing:
            false
        }
    }
}
