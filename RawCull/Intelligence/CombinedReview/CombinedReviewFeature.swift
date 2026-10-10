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
    static let stageVersions = ReviewPipelineContract.stageVersions
    var criteria = "Describe composition, exposure, subject visibility and technical detail."
    var depth: ReviewDepth = .standard
    var sourcePreference: ReviewSourcePreference = .highQualityPreview
    var retainInputs = true
    var userRegion: CGRect?
    private(set) var isRunning = false
    private(set) var isCheckingParameters = false
    private(set) var sourceAvailability: ReviewSourceAvailability?
    private(set) var resumeDisabledReason: String? = "Checking saved settings…"
    private(set) var parameterStatus = "Select 1–8 images to check available settings."
    @ObservationIgnored private var parameterRevision = 0
    private var checkedSelection: [ReviewSelectedFile] = []

    var criteriaStatus: String? {
        let goal = criteria.trimmingCharacters(in: .whitespacesAndNewlines)
        if goal.isEmpty {
            return "Start disabled: enter review criteria."
        }
        if goal.utf8.count > 512 {
            return "Start disabled: review criteria must fit within 512 UTF-8 bytes."
        }
        return nil
    }

    var canStartReview: Bool {
        !isRunning && !isCheckingParameters && criteriaStatus == nil &&
            sourceAvailability.map { $0.reason(for: sourcePreference) == nil } == true
    }

    func canStartReview(for selected: [ReviewSelectedFile]) -> Bool {
        canStartReview && checkedSelection == selected
    }

    func prepareResumeParameters() async {
        guard !isRunning, let saved = manifest else { return }
        let id = saved.snapshot.id
        resumeDisabledReason = "Checking saved settings…"
        do {
            try await ReviewCatalogSession.revalidate(saved.snapshot.files)
            var availability = ReviewSourceAvailability()
            for file in saved.snapshot.files {
                let value = try await sourceLoader.availability(for: file.url)
                availability.previewDisabledReason = availability.previewDisabledReason ?? value.previewDisabledReason
                availability.rawDisabledReason = availability.rawDisabledReason ?? value.rawDisabledReason
            }
            guard !Task.isCancelled, manifest?.snapshot.id == id else { return }
            if let preference = ReviewSourcePreference(rawValue: saved.snapshot.sourcePreference) {
                resumeDisabledReason = availability.reason(for: preference).map { $0 + " Rerun with current settings instead." }
            } else {
                resumeDisabledReason = "The saved source setting is unsupported. Rerun with current settings."
            }
        } catch {
            guard manifest?.snapshot.id == id else { return }
            resumeDisabledReason = "The saved image changed or is unavailable. Rerun with current settings."
        }
    }

    func prepareParameters(_ selected: [ReviewSelectedFile]) async {
        guard !isRunning else { return }
        parameterRevision += 1
        let revision = parameterRevision
        sourceAvailability = nil
        checkedSelection = []
        guard !selected.isEmpty, selected.count <= 8 else {
            isCheckingParameters = false
            parameterStatus = "Review settings disabled: select 1–8 images. Larger selections require an expanded coverage plan and a separate run."
            return
        }
        isCheckingParameters = true
        parameterStatus = "Checking available image sources…"
        defer {
            if revision == parameterRevision {
                isCheckingParameters = false
            }
        }
        do {
            var availability = ReviewSourceAvailability()
            for file in selected {
                let value = try await sourceLoader.availability(for: file.url)
                availability.previewDisabledReason = availability.previewDisabledReason ?? value.previewDisabledReason
                availability.rawDisabledReason = availability.rawDisabledReason ?? value.rawDisabledReason
            }
            guard !Task.isCancelled, !isRunning, revision == parameterRevision else { return }
            sourceAvailability = availability
            checkedSelection = selected
            if availability.reason(for: sourcePreference) != nil {
                if availability.previewDisabledReason == nil {
                    sourcePreference = .highQualityPreview
                } else if availability.rawDisabledReason == nil {
                    sourcePreference = .rawDetail
                }
            }
            var messages: [String] = []
            if let reason = availability.rawDisabledReason {
                messages.append("RAW detail disabled: " + reason)
            }
            if let reason = availability.previewDisabledReason {
                messages.append("High-quality preview disabled: " + reason)
            }
            if availability.reason(for: sourcePreference) == nil {
                messages.append(sourcePreference == .rawDetail ? "RAW detail available." : "High-quality preview available.")
            } else {
                messages.append("Start disabled: no supported image source is available.")
            }
            parameterStatus = messages.isEmpty ? "All review settings available." : messages.joined(separator: " ")
        } catch {
            guard revision == parameterRevision else { return }
            parameterStatus = "Review settings disabled: the selected image could not be checked."
        }
    }

    var progress = "Ready"
    private(set) var failureMessage: String?
    var result: CombinedReviewResult?
    var results: [CombinedReviewResult] = []
    var displayedResults: [CombinedReviewResult] {
        if let result, !results.contains(where: { $0.file.id == result.file.id }) {
            return results + [result]
        }
        return results
    }

    var selectionReport: ReviewSelectionReport?
    var comparisonInputReference: String?
    @ObservationIgnored var activeFile: ReviewFileSnapshot?
    @ObservationIgnored var cropAllowance = 0
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
    @ObservationIgnored private var storageRevision = 0
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
        await prepareParameters(selected)
        guard canStartReview(for: selected) else { return }
        let goal = criteria.trimmingCharacters(in: .whitespacesAndNewlines)
        let id = UUID()
        do {
            try lease.acquire(id)
            isRunning = true; failureMessage = nil; progress = "Checking source and models"
            lease.invalidateOwner = { [weak self] in self?.cancel() }
            let backend = try backendFactory()
            let selectedDepth = depth, selectedPreference = sourcePreference, retention = retainInputs
            let requestedRegion = selected.count == 1 ? userRegion : nil
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
                                                     renderVersion: ReviewPipelineContract.renderVersion, models: models,
                                                     stageVersions: Self.stageVersions,
                                                     responseTokens: 768, pipelineVersion: ReviewPipelineContract.version, created: Date(), expandedSelectionPlan: nil,
                                                     userRegions: requestedRegion.map { [.init(imageID: files[0].id, normalizedRect: $0, purpose: "User region; location only")] })
                    try snapshot.validate()
                    if let previous = manifest {
                        savedHistory.removeAll { $0.snapshot.id == previous.snapshot.id }
                        savedHistory.insert(previous, at: 0)
                    }
                    result = nil; results = []; selectionReport = nil
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
        guard manifest == nil, !isRunning, !lease.isHeld else { return }
        let revision = storageRevision
        do {
            let history = try await store.historyManifests()
            let saved = try await store.latestManifest()
            guard revision == storageRevision, manifest == nil, !lease.isHeld else { return }
            savedHistory = history
            if let saved {
                manifest = saved
                progress = saved.cancelled ? "Saved run available to resume" : "Saved evidence available"
            }
        } catch { failureMessage = "Saved review unavailable: \(error)" }
    }

    func resume() async {
        guard !isRunning, let saved = manifest else { return }
        await prepareResumeParameters()
        guard !isRunning, resumeDisabledReason == nil, manifest?.snapshot.id == saved.snapshot.id else { return }
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
                    try ReviewPipelineContract.validate(saved.snapshot)
                    try saved.validate()
                    let expected = try saved.expectedCompatibility()
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

    func clearAllReviews() async throws {
        guard !isRunning else { throw ReviewRunError.invalidTransition }
        let reservation = UUID()
        try lease.acquire(reservation)
        defer { lease.release(reservation) }
        storageRevision += 1
        try await store.clearAll()
        result = nil; results = []; selectionReport = nil; comparisonInputReference = nil
        manifest = nil
        savedHistory = []
        userRegion = nil
        failureMessage = nil
        progress = "Ready"
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
        var work: [ReviewWorkItem] = []
        for file in snapshot.files {
            let source = workID(file.id, "source"), overview = workID(file.id, "overview"), identity = workID(file.id, "identity")
            func item(_ name: String, stage: ReviewStage, parents: [ReviewWorkID], terminal: Bool = false) throws -> ReviewWorkItem {
                try .init(id: workID(file.id, name), imageID: file.id, stage: stage,
                          dependencies: parents.map { .init(id: $0, allowsUnavailable: terminal) },
                          compatibility: ReviewCompatibility.make(snapshot: snapshot, image: file, stage: stage))
            }
            try work.append(contentsOf: [item("source", stage: .source, parents: []),
                                         item("overview", stage: .overview, parents: [source]),
                                         item("identity", stage: .identity, parents: [source, overview], terminal: true),
                                         item("report", stage: .report, parents: [identity, overview], terminal: true)])
        }
        if snapshot.files.count > 1 {
            let file = snapshot.files[0]
            try work.append(.init(id: workID(file.id, "selection"), imageID: file.id, stage: .comparison,
                                  dependencies: snapshot.files.map { .init(id: workID($0.id, "report"), allowsUnavailable: true) },
                                  compatibility: ReviewCompatibility.make(snapshot: snapshot, image: file, stage: .comparison)))
        }
        return try CombinedReviewRunV1(snapshot: snapshot, work: work, budget: ReviewBudget(depth: snapshot.depth, images: snapshot.files.count))
    }
}
