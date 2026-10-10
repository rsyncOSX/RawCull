import CoreGraphics
import Foundation
import Observation
import RawParserKit

nonisolated struct CombinedReviewResult: Sendable {
    let file: ReviewFileSnapshot
    var source: ReviewSourceRecord?
    var overview: CombinedReviewOverview?
    var subjects: [ReviewSubjectRecord] = []
    var regions: [ReviewRegionRecord] = []
    var observations: [ReviewObservation] = []
    var measurements: [ReviewMeasurement] = []
    var clip: [String: CombinedReviewCLIPResult] = [:]
    var report: ReviewImageReport?
    var limitations: [ReviewLimitation] = []
    var failures: [String: String] = [:]
    var overviewInputReference: String?
}

@Observable @MainActor
final class CombinedReviewFeature {
    static let stageVersions = Dictionary(uniqueKeysWithValues: ReviewStage.allCases.map {
        ($0, [.cropObservation, .reconciliation, .report].contains($0) ? "combined-v2" : "combined-v1")
    })
    var criteria = "Describe composition, exposure, subject visibility and technical detail."
    var depth: ReviewDepth = .standard
    var sourcePreference: ReviewSourcePreference = .highQualityPreview
    var retainInputs = true
    var userRegion: CGRect?
    private(set) var isRunning = false
    var progress = "Ready"
    private(set) var failureMessage: String?
    var result: CombinedReviewResult?
    private(set) var savedHistory: [CombinedReviewRunV1] = []
    var taskHistory: [CombinedReviewRunV1] {
        let previous = savedHistory.filter { $0.snapshot.id != manifest?.snapshot.id }
        return manifest.map { [$0] + previous } ?? previous
    }

    var manifest: CombinedReviewRunV1?
    @ObservationIgnored let store: ReviewArtifactStore
    @ObservationIgnored let sourceLoader: any ReviewImageSourceLoading
    @ObservationIgnored let scorer: any SubjectMaskFocusScoring
    @ObservationIgnored let lease: CombinedReviewLease
    @ObservationIgnored let backendFactory: @MainActor () throws -> any CombinedReviewBackendServing
    @ObservationIgnored var beforeStart: (@MainActor () async -> Void)?
    @ObservationIgnored private var task: Task<Void, Never>?
    @ObservationIgnored private var catalogSession: ReviewCatalogSession?

    init(store: ReviewArtifactStore = ReviewArtifactStore(), sourceLoader: any ReviewImageSourceLoading = ReviewImageSourceService(),
         scorer: any SubjectMaskFocusScoring = SubjectMaskFocusScorer(), lease: CombinedReviewLease = .shared,
         backendFactory: @escaping @MainActor () throws -> any CombinedReviewBackendServing)
    {
        self.store = store; self.sourceLoader = sourceLoader; self.scorer = scorer; self.lease = lease; self.backendFactory = backendFactory
    }

    func analyze(_ selected: [ReviewSelectedFile]) async {
        guard !isRunning else { return }
        guard selected.count == 1 else {
            failureMessage = "Combined Review currently accepts one image. Selection comparison arrives in phase 5."
            return
        }
        let goal = criteria.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !goal.isEmpty, goal.utf8.count <= 512 else { failureMessage = "Enter criteria up to 512 UTF-8 bytes."; return }
        let id = UUID()
        do {
            try lease.acquire(id)
            isRunning = true; failureMessage = nil; progress = "Checking source and models"
            lease.invalidateOwner = { [weak self] in self?.cancel() }
            let backend = try backendFactory()
            let selectedDepth = depth, selectedPreference = sourcePreference, retention = retainInputs
            let requestedRegion = userRegion
            let worker = Task { [weak self] in
                guard let self else { return }
                defer { isRunning = false; task = nil; catalogSession = nil; lease.release(id) }
                do {
                    await beforeStart?()
                    let files = try await ReviewCatalogSession.freeze(selected)
                    catalogSession = ReviewCatalogSession(urls: files.map(\.url))
                    let models = try await backend.models()
                    try Task.checkCancellation()
                    let snapshot = ReviewRunSnapshot(id: id, files: files, criteria: goal, depth: selectedDepth,
                                                     sourcePreference: selectedPreference.rawValue, retentionPolicy: retention ? .exactInputs : .compact,
                                                     renderVersion: "review-srgb-v1", models: models,
                                                     stageVersions: Self.stageVersions,
                                                     responseTokens: 768, pipelineVersion: "combined-v1", created: Date(), expandedSelectionPlan: nil,
                                                     userRegions: requestedRegion.map { [.init(imageID: files[0].id, normalizedRect: $0, purpose: "User region; location only")] })
                    try snapshot.validate()
                    if let previous = manifest {
                        savedHistory.removeAll { $0.snapshot.id == previous.snapshot.id }
                        savedHistory.insert(previous, at: 0)
                    }
                    result = nil
                    manifest = try Self.initialManifest(snapshot)
                    try await store.saveManifest(currentManifest())
                    try await execute(backend)
                } catch is CancellationError { await persistCancellation(); progress = "Cancelled — completed evidence retained" } catch { failureMessage = Self.message(for: error); progress = "Review stopped"; await persistCancellation() }
            }
            task = worker
            await worker.value
        } catch { isRunning = false; lease.release(id); failureMessage = String(describing: error) }
    }

    func restoreStoredRun() async {
        guard manifest == nil, !isRunning else { return }
        do {
            savedHistory = try await store.historyManifests()
            if let saved = try await store.latestManifest() {
                manifest = saved
                progress = saved.cancelled ? "Saved run available to resume" : "Saved evidence available"
            }
        } catch { failureMessage = "Saved review unavailable: \(error)" }
    }

    func resume() async {
        guard !isRunning, let saved = manifest else { return }
        let id = saved.snapshot.id
        do {
            try lease.acquire(id); isRunning = true; failureMessage = nil
            lease.invalidateOwner = { [weak self] in self?.cancel() }
            let backend = try backendFactory()
            let worker = Task { [weak self] in
                guard let self else { return }
                defer { isRunning = false; task = nil; catalogSession = nil; lease.release(id) }
                do {
                    await beforeStart?()
                    catalogSession = ReviewCatalogSession(urls: saved.snapshot.files.map(\.url))
                    try await ReviewCatalogSession.revalidate(saved.snapshot.files)
                    guard try await backend.models() == saved.snapshot.models else { throw ReviewRunError.incompatible }
                    guard saved.snapshot.pipelineVersion == "combined-v1", saved.snapshot.renderVersion == "review-srgb-v1", saved.snapshot.stageVersions == Self.stageVersions else { throw ReviewRunError.incompatible }
                    let expected = Dictionary(uniqueKeysWithValues: saved.work.map { ($0.id, $0.compatibility) })
                    let valid = await store.validArtifactKeys(for: saved)
                    var restored = saved; restored.restore(expected: expected, validArtifacts: valid, retryFailed: false)
                    manifest = restored
                    try await execute(backend)
                } catch is CancellationError { await persistCancellation(); progress = "Cancelled — completed evidence retained" } catch { failureMessage = "Resume unavailable: \(Self.message(for: error))"; progress = "Resume stopped — rerun with current settings"; await persistCancellation() }
            }
            task = worker; await worker.value
        } catch { isRunning = false; lease.release(id); failureMessage = String(describing: error) }
    }

    func cancel() {
        task?.cancel()
        manifest?.cancel()
        progress = "Cancelling"
    }

    private static func message(for error: any Error) -> String {
        (error as? any LocalizedError)?.errorDescription ?? String(describing: error)
    }

    func exactInput(_ key: String) async -> CGImage? {
        guard let bytes = try? await store.input(key) else { return nil }
        return OrientationNormalizedImageLoader.loadCGImage(from: bytes)
    }

    func clearRetainedInputs() async {
        try? await store.clearInputs()
    }

    func currentManifest() throws -> CombinedReviewRunV1 {
        guard let manifest else { throw ReviewRunError.invalidSnapshot }
        return manifest
    }

    func persistCancellation() async {
        manifest?.cancel()
        if let manifest {
            try? await store.saveManifest(manifest)
        }
    }

    static func workID(_ image: ReviewImageID, _ name: String) -> ReviewWorkID {
        .init(rawValue: image.rawValue + ":" + name)
    }

    static func initialManifest(_ snapshot: ReviewRunSnapshot) throws -> CombinedReviewRunV1 {
        let file = snapshot.files[0]
        let source = workID(file.id, "source"), overview = workID(file.id, "overview"), identity = workID(file.id, "identity")
        func item(_ name: String, stage: ReviewStage, parents: [ReviewWorkID], terminal: Bool = false) throws -> ReviewWorkItem {
            try .init(id: workID(file.id, name), imageID: file.id, stage: stage,
                      dependencies: parents.map { .init(id: $0, allowsUnavailable: terminal) },
                      compatibility: ReviewCompatibility.make(snapshot: snapshot, image: file, stage: stage))
        }
        return try CombinedReviewRunV1(snapshot: snapshot, work: [item("source", stage: .source, parents: []),
                                                                  item("overview", stage: .overview, parents: [source]), item("identity", stage: .identity, parents: [source, overview], terminal: true),
                                                                  item("report", stage: .report, parents: [identity, overview], terminal: true)], budget: ReviewBudget(depth: snapshot.depth, images: 1))
    }
}
