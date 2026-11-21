import CoreGraphics
import CoreImage
import CoreImage.CIFilterBuiltins
import Foundation
import ImageIO
import Observation
import OSLog
import PhotoAIContracts
import PhotoAIWorkflows

nonisolated enum DeepAIReviewPreset: String, CaseIterable, Codable, Identifiable, Sendable {
    case auto
    case fullSubject
    case headFace

    var id: String {
        rawValue
    }
}

nonisolated enum DeepAIReviewConfidence: String, Codable, Sendable {
    case high
    case medium
    case low
}

nonisolated enum DeepAIReviewReason: String, Codable, Hashable, Sendable {
    case strongestSubjectDetail
    case autofocusInsideSubject
    case localDetailEvidence
    case requestedPromptMatched
}

nonisolated enum DeepAIReviewCandidateIssue: Equatable, Hashable, Sendable {
    case imageDecodeFailed
    case maskUnavailable
    case maskAcquisitionFailed(String)
    case poorMaskQuality
    case specificPromptNotFound
    case subjectDetailUnavailable
    case noReliableLocalPatch
    case backgroundDetailDominated
}

nonisolated struct DeepAIReviewInputCandidate: Equatable, Identifiable, Sendable {
    var id: UUID {
        fileID
    }

    let fileID: UUID
    let fileName: String
    let url: URL
    let burstRank: Int
    let normalSharpnessScore: Float?
    let subjectLabel: String?
    let normalizedAFPoint: CGPoint?
    var iso: Int?
}

nonisolated struct DeepAIReviewRequest: Equatable, Sendable {
    let groupID: Int
    let groupSignature: BurstGroupSignature
    let candidates: [DeepAIReviewInputCandidate]
    let preset: DeepAIReviewPreset
    let scoringSource: SharpnessScoringSource
}

nonisolated struct DeepAIReviewCandidate: Equatable, Identifiable, Sendable {
    var id: UUID {
        fileID
    }

    let fileID: UUID
    let fileName: String
    let rank: Int
    let isCompleted: Bool
    let deepScore: Float?
    let normalSharpnessScore: Float?
    let broadSubjectScore: Float?
    let localDetailScore: Float?
    let fineDetailScore: Float?
    let maskPromptUsed: SubjectSegmentationPrompt?
    let maskConfidence: Float?
    let maskCoverage: Float?
    let autofocusInsideMask: Bool?
    /// Legacy name: indicates a usable mask from the requested prompt, not verified anatomy.
    let promptVerified: Bool?
    var requestedPromptObtained: Bool? {
        promptVerified
    }

    let usedFallbackMask: Bool
    let issues: [DeepAIReviewCandidateIssue]
    var maskStorageKey: SubjectMaskStorageKey?
}

nonisolated struct DeepAIReviewResult: Equatable, Sendable {
    let groupID: Int
    let groupSignature: BurstGroupSignature
    let preset: DeepAIReviewPreset
    let candidates: [DeepAIReviewCandidate]
    let recommendedFileID: UUID?
    /// Relative score separation under the available measurement conditions, not calibrated certainty.
    let confidence: DeepAIReviewConfidence
    let reasons: [DeepAIReviewReason]
    let cautions: [DeepAIReviewCandidateIssue]
    let timestamp: Date

    var recommendedCandidate: DeepAIReviewCandidate? {
        recommendedFileID.flatMap { id in
            candidates.first { $0.fileID == id }
        }
    }
}

nonisolated struct DeepAIReviewProgress: Equatable, Sendable {
    let groupID: Int
    let completedCount: Int
    let totalCount: Int
    let currentFileName: String?
    let candidates: [DeepAIReviewCandidate]
}

nonisolated enum DeepAIReviewFailure: Error, Equatable, Sendable {
    case modelUnavailable(String)
    case noCandidates
    case pipelineFailed(String)
}

nonisolated enum DeepAIReviewState: Equatable, Sendable {
    case idle
    case preparing(groupID: Int, totalCount: Int)
    case running(DeepAIReviewProgress)
    case completing(groupID: Int)
    case cancelled(groupID: Int)
    case failed(groupID: Int?, failure: DeepAIReviewFailure)
    case completed(DeepAIReviewResult)

    var activeGroupID: Int? {
        switch self {
        case .idle:
            nil

        case let .preparing(groupID, _), let .completing(groupID):
            groupID

        case let .cancelled(groupID):
            groupID

        case let .running(progress):
            progress.groupID

        case let .failed(groupID, _):
            groupID

        case let .completed(result):
            result.groupID
        }
    }

    var isRunning: Bool {
        switch self {
        case .preparing, .running, .completing:
            true

        case .idle, .cancelled, .failed, .completed:
            false
        }
    }
}

nonisolated protocol DeepAIReviewServicing: Sendable {
    func review(
        _ request: DeepAIReviewRequest,
        progress: @escaping @Sendable (DeepAIReviewProgress) async -> Void,
    ) async throws -> DeepAIReviewResult
}

nonisolated protocol DeepAIReviewMaskLoading: Sendable {
    func mask(for key: SubjectMaskStorageKey) async -> CGImage?
}

@Observable @MainActor
final class DeepAIReviewFeature {
    var preset: DeepAIReviewPreset = .auto
    private(set) var state: DeepAIReviewState = .idle
    private(set) var availability: RawCullAICapabilityStatus
    private(set) var results: [BurstGroupSignature: DeepAIReviewResult] = [:]
    private(set) var completedCandidatesByFileID: [UUID: DeepAIReviewCandidate] = [:]
    private(set) var completedFileIDsByPreset: [DeepAIReviewPreset: Set<UUID>] = [:]
    private(set) var maskCandidatesByFileID: [UUID: DeepAIReviewCandidate] = [:]

    @ObservationIgnored private var service: (any DeepAIReviewServicing)?
    @ObservationIgnored private var maskLoader: (any DeepAIReviewMaskLoading)?
    /// Segmentation model behind `service`. Results and mask lookups are only valid
    /// for the model that produced them.
    @ObservationIgnored private var installedModelIdentity: ModelIdentity?
    @ObservationIgnored private var drainingTasks: [Task<Void, Never>] = []
    @ObservationIgnored private var task: Task<Void, Never>?
    @ObservationIgnored private var generation = 0

    init(
        availability: RawCullAICapabilityStatus = .unavailable(
            reason: "A segmentation model has not been configured for in-process review.",
        ),
        service: (any DeepAIReviewServicing)? = nil,
        maskLoader: (any DeepAIReviewMaskLoading)? = nil,
    ) {
        self.availability = availability
        self.service = service
        self.maskLoader = maskLoader
    }

    var isRunning: Bool {
        state.isRunning
    }

    func result(for signature: BurstGroupSignature) -> DeepAIReviewResult? {
        results[signature]
    }

    func maskCandidate(for fileID: UUID) -> DeepAIReviewCandidate? {
        maskCandidatesByFileID[fileID]
    }

    var completedCandidates: [DeepAIReviewCandidate] {
        completedCandidatesByFileID.values.sorted {
            $0.fileName.localizedStandardCompare($1.fileName) == .orderedAscending
        }
    }

    func install(
        service: (any DeepAIReviewServicing)?,
        maskLoader: (any DeepAIReviewMaskLoading)?,
        availability: RawCullAICapabilityStatus,
        modelIdentity: ModelIdentity? = nil,
    ) {
        let modelChanged = modelIdentity != installedModelIdentity
        installedModelIdentity = modelIdentity
        self.service = service
        self.maskLoader = maskLoader
        self.availability = availability
        if modelChanged {
            // A run or result from the previous model would be shown as current while
            // the mask overlay looks up the new model's cache keys.
            Logger.process.debugMessageOnly(
                "DeepAIReviewFeature.install(): segmentation model changed; invalidating Deep Review results",
            )
            if isRunning {
                cancel()
            }
            invalidateResults()
        } else if !availability.isAvailable, isRunning {
            cancel()
        }
    }

    private func invalidateResults() {
        results = [:]
        completedCandidatesByFileID = [:]
        completedFileIDsByPreset = [:]
        maskCandidatesByFileID = [:]
        if case .completed = state {
            state = .idle
        }
    }

    func mask(
        for candidate: DeepAIReviewCandidate,
        fileURL: URL,
    ) async -> CGImage? {
        guard candidate.isCompleted,
              let key = candidate.maskStorageKey,
              key.source.url.deletingLastPathComponent().standardizedFileURL.path == fileURL.standardizedFileURL.path,
              key.modelIdentity == installedModelIdentity
        else { return nil }
        let identity = await Task { @concurrent in
            SourceFileIdentity.read(from: fileURL)
        }.value
        guard identity == key.sourceIdentity, key.modelIdentity == installedModelIdentity else { return nil }
        let mask = await maskLoader?.mask(for: key)
        guard key.modelIdentity == installedModelIdentity else { return nil }
        return mask
    }

    func start(_ request: DeepAIReviewRequest) async {
        guard !CombinedReviewLease.shared.isHeld else { return }
        Logger.process.debugMessageOnly(
            "DeepAIReviewFeature.start(): starting group \(request.groupID) with \(request.candidates.count) candidates",
        )
        guard !isRunning else {
            Logger.process.debugMessageOnly(
                "DeepAIReviewFeature.start(): skipped because a review is already running",
            )
            return
        }
        guard availability.isAvailable, let service else {
            Logger.process.debugMessageOnly(
                "DeepAIReviewFeature.start(): failed because the Deep Review service is unavailable",
            )
            state = .failed(
                groupID: request.groupID,
                failure: .modelUnavailable(Self.unavailableReason(for: availability)),
            )
            return
        }
        guard !request.candidates.isEmpty else {
            Logger.process.debugMessageOnly(
                "DeepAIReviewFeature.start(): failed because the request contains no candidates",
            )
            state = .failed(groupID: request.groupID, failure: .noCandidates)
            return
        }

        generation &+= 1
        let runGeneration = generation
        state = .preparing(
            groupID: request.groupID,
            totalCount: RawCullDeepAIReviewPipeline.selectedCandidateCount(
                from: request.candidates.count,
            ),
        )

        let feature = self
        let access = RawCullCatalogAccess.shared.retainAccess(for: request.candidates.map(\.url))
        let task = Task {
            defer { withExtendedLifetime(access) {} }
            do {
                Logger.process.debugMessageOnly(
                    "DeepAIReviewFeature.start(): invoking the Deep Review service",
                )
                let result = try await service.review(request) { progress in
                    await feature.receive(progress, preset: request.preset, generation: runGeneration)
                }
                try Task.checkCancellation()
                guard feature.generation == runGeneration else { return }
                Logger.process.debugMessageOnly(
                    "DeepAIReviewFeature.start(): service returned a result for group \(request.groupID)",
                )
                feature.state = .completing(groupID: request.groupID)
                feature.results[result.groupSignature] = result
                feature.retainCompletedCandidates(result.candidates, preset: request.preset)
                feature.rebuildMaskCandidateIndex()
                feature.state = .completed(result)
                Logger.process.debugMessageOnly(
                    "DeepAIReviewFeature.start(): review completed for group \(request.groupID)",
                )
            } catch is CancellationError {
                Logger.process.debugMessageOnly(
                    "DeepAIReviewFeature.start(): review was cancelled",
                )
                guard feature.generation == runGeneration else { return }
                feature.state = .cancelled(groupID: request.groupID)
            } catch let failure as DeepAIReviewFailure {
                Logger.process.debugMessageOnly(
                    "DeepAIReviewFeature.start(): review failed: \(failure)",
                )
                guard feature.generation == runGeneration else { return }
                feature.state = .failed(groupID: request.groupID, failure: failure)
            } catch {
                Logger.process.debugMessageOnly(
                    "DeepAIReviewFeature.start(): review failed unexpectedly: \(error)",
                )
                guard feature.generation == runGeneration else { return }
                feature.state = .failed(
                    groupID: request.groupID,
                    failure: .pipelineFailed(String(describing: error)),
                )
            }
        }
        self.task = task

        await withTaskCancellationHandler {
            await task.value
        } onCancel: {
            task.cancel()
        }
        drainingTasks.removeAll { $0 == task }
        if generation == runGeneration {
            self.task = nil
        }
    }

    func cancelAndWait() async {
        cancel()
        let draining = drainingTasks
        drainingTasks = []
        for worker in draining {
            await worker.value
        }
    }

    func cancel() {
        Logger.process.debugMessageOnly(
            "DeepAIReviewFeature.cancel(): cancelling the active review",
        )
        let activeGroupID = state.activeGroupID
        generation &+= 1
        if let task {
            drainingTasks.append(task); task.cancel()
        }
        task = nil
        if state.isRunning, let activeGroupID {
            state = .cancelled(groupID: activeGroupID)
        }
    }

    func reset() {
        Logger.process.debugMessageOnly(
            "DeepAIReviewFeature.reset(): resetting Deep Review state",
        )
        cancel()
        invalidateResults()
        state = .idle
    }

    private func receive(_ progress: DeepAIReviewProgress, preset: DeepAIReviewPreset, generation: Int) {
        Logger.process.debugMessageOnly(
            "DeepAIReviewFeature.receive(): received progress "
                + "\(progress.completedCount)/\(progress.totalCount) for group \(progress.groupID)",
        )
        guard self.generation == generation, !Task.isCancelled else { return }
        retainCompletedCandidates(progress.candidates, preset: preset)
        state = .running(progress)
    }

    private func retainCompletedCandidates(_ candidates: [DeepAIReviewCandidate], preset: DeepAIReviewPreset) {
        for candidate in candidates where candidate.isCompleted {
            completedCandidatesByFileID[candidate.fileID] = candidate
            completedFileIDsByPreset[preset, default: []].insert(candidate.fileID)
            if candidate.maskPromptUsed != nil {
                maskCandidatesByFileID[candidate.fileID] = candidate
            }
        }
    }

    private func rebuildMaskCandidateIndex() {
        maskCandidatesByFileID = completedCandidatesByFileID.reduce(into: [:]) { candidates, entry in
            guard entry.value.maskPromptUsed != nil else { return }
            candidates[entry.key] = entry.value
        }
    }

    private nonisolated static func unavailableReason(
        for status: RawCullAICapabilityStatus,
    ) -> String {
        switch status {
        case .checking:
            "RawCull is still checking the selected segmentation model."

        case .available:
            "The selected in-process segmentation pipeline is unavailable."

        case let .missing(expectedLocations):
            expectedLocations.first.map {
                "Install the selected segmentation model at \($0.path)."
            } ?? "Install the selected segmentation model."

        case let .invalid(location, reason):
            location.map {
                "The selected segmentation model at \($0.path) is invalid: \(reason)"
            } ?? "The selected segmentation model is invalid: \(reason)"

        case let .unavailable(reason):
            reason
        }
    }
}

nonisolated protocol DeepAIReviewImageDecoding: Sendable {
    func image(
        for candidate: DeepAIReviewInputCandidate,
        maximumPixelSize: Int,
        source: SharpnessScoringSource,
    ) async throws -> CGImage
}

nonisolated struct RawCullDeepReviewImageDecoder: DeepAIReviewImageDecoding, Sendable {
    @concurrent
    func image(
        for candidate: DeepAIReviewInputCandidate,
        maximumPixelSize: Int,
        source: SharpnessScoringSource,
    ) async throws -> CGImage {
        Logger.process.debugMessageOnly(
            "RawCullDeepReviewImageDecoder.image(): decoding \(candidate.fileName) from \(source)",
        )
        try Task.checkCancellation()
        switch source {
        case .embeddedPreview:
            let source = AIImageSource(
                id: candidate.fileID,
                url: candidate.url,
                displayName: candidate.fileName,
            )
            let image = try await RawCullSimilarityImageDecoder(
                maxPixelSize: maximumPixelSize,
            ).image(for: source)
            Logger.process.debugMessageOnly(
                "RawCullDeepReviewImageDecoder.image(): decoded \(candidate.fileName) at \(image.width)x\(image.height)",
            )
            return image

        case .rawDemosaic:
            // Same render as sharpness scoring so both report on identical pixels.
            guard let result = RawScoringDemosaic.render(url: candidate.url, maximumPixelSize: maximumPixelSize) else {
                try Task.checkCancellation()
                throw DeepAIReviewCandidateIssue.imageDecodeFailed
            }
            try Task.checkCancellation()
            Logger.process.debugMessageOnly(
                "RawCullDeepReviewImageDecoder.image(): decoded \(candidate.fileName) at \(result.width)x\(result.height)",
            )
            return result
        }
    }
}

/// Adapts package cache keys for Deep Review renders while preserving the
/// identity of the real source file. The namespace is used only inside stores.
nonisolated struct DeepAIReviewRenderMaskStore: SubjectMaskStoring {
    let store: any SubjectMaskStoring
    let render: Render

    nonisolated struct Render: Sendable {
        let source: SharpnessScoringSource
        let maximumPixelSize: Int
        let width: Int
        let height: Int

        func storageKey(for key: SubjectMaskStorageKey) -> SubjectMaskStorageKey {
            let version = SharpnessScoringSignature.currentInputPipelineVersion
            let namespace = "deep-review-v\(version)-\(source.rawValue)-\(maximumPixelSize)-\(width)x\(height)"
            return SubjectMaskStorageKey(
                source: AIImageSource(
                    id: key.source.id,
                    url: key.source.url.standardizedFileURL.appendingPathComponent(namespace),
                    displayName: key.source.displayName,
                ),
                sourceIdentity: key.sourceIdentity,
                prompt: key.prompt,
                modelIdentity: key.modelIdentity,
                inputMaxSide: key.inputMaxSide,
            )
        }
    }

    func load(for key: SubjectMaskStorageKey) async -> SubjectSegmentationResult? {
        guard let result = await store.load(for: render.storageKey(for: key)),
              result.mask.width == render.width, result.mask.height == render.height
        else { return nil }
        return result
    }

    func contains(_ key: SubjectMaskStorageKey) async -> Bool {
        await load(for: key) != nil
    }

    func save(_ result: SubjectSegmentationResult, for key: SubjectMaskStorageKey) async throws {
        guard result.mask.width == render.width, result.mask.height == render.height else { return }
        try await store.save(result, for: render.storageKey(for: key))
    }
}

nonisolated struct RawCullDeepAIReviewPipeline: DeepAIReviewServicing, Sendable {
    private let provider: any SubjectSegmenting
    private let maskConfiguration: SubjectMaskRepositoryConfiguration
    private let maskStores: [any SubjectMaskStoring]
    private let decoder: any DeepAIReviewImageDecoding
    private let focusScorer: any SubjectMaskFocusScoring
    private let maximumPixelSize: Int

    init(
        provider: any SubjectSegmenting,
        maskConfiguration: SubjectMaskRepositoryConfiguration,
        maskStores: [any SubjectMaskStoring],
        decoder: any DeepAIReviewImageDecoding = RawCullDeepReviewImageDecoder(),
        focusScorer: any SubjectMaskFocusScoring = SubjectMaskFocusScorer(),
        maximumPixelSize: Int = SharpnessScoringSizeOption.maximumPixelSize,
    ) {
        self.provider = provider
        self.maskConfiguration = maskConfiguration
        self.maskStores = maskStores
        self.decoder = decoder
        self.focusScorer = focusScorer
        self.maximumPixelSize = maximumPixelSize
    }

    static func maskFits(_ selection: SubjectMaskSelection, image: CGImage) -> Bool {
        guard let mask = selection.selected?.result.mask else { return true }
        return mask.width == image.width && mask.height == image.height
    }

    @concurrent
    func review(
        _ request: DeepAIReviewRequest,
        progress: @escaping @Sendable (DeepAIReviewProgress) async -> Void,
    ) async throws -> DeepAIReviewResult {
        Logger.process.debugMessageOnly(
            "RawCullDeepAIReviewPipeline.review(): starting group \(request.groupID) "
                + "with \(request.candidates.count) input candidates",
        )
        let candidates = Self.selectedCandidates(from: request.candidates)
        guard !candidates.isEmpty else { throw DeepAIReviewFailure.noCandidates }
        Logger.process.debugMessageOnly(
            "RawCullDeepAIReviewPipeline.review(): selected \(candidates.count) candidates for detailed review",
        )

        var completed: [DeepAIReviewCandidate] = []
        await progress(Self.progress(
            request: request,
            selectedCandidates: candidates,
            completed: completed,
            currentFileName: candidates.first?.fileName,
        ))

        for candidate in candidates {
            try Task.checkCancellation()
            let row = try await evaluate(candidate, request: request)
            completed.append(row)
            try Task.checkCancellation()
            let nextFileName = candidates.dropFirst(completed.count).first?.fileName
            await progress(Self.progress(
                request: request,
                selectedCandidates: candidates,
                completed: completed,
                currentFileName: nextFileName,
            ))
        }

        try Task.checkCancellation()
        let result = Self.makeResult(request: request, candidates: completed)
        Logger.process.debugMessageOnly(
            "RawCullDeepAIReviewPipeline.review(): finished group \(request.groupID)",
        )
        return result
    }

    nonisolated static func selectedCandidateCount(from totalCount: Int) -> Int {
        totalCount > 12 ? min(totalCount, 8) : totalCount
    }

    nonisolated static func promptAttempts(
        preset: DeepAIReviewPreset,
        subjectLabel: String?,
    ) -> [SubjectSegmentationPrompt] {
        switch preset {
        case .fullSubject:
            [.subject]

        case .headFace:
            specificPromptAttempts(subjectLabel: subjectLabel)

        case .auto:
            automaticPromptAttempts(subjectLabel: subjectLabel)
        }
    }

    nonisolated static func confidence(
        sortedCandidates: [DeepAIReviewCandidate],
    ) -> DeepAIReviewConfidence {
        guard let first = sortedCandidates.first,
              let firstScore = first.deepScore
        else { return .low }
        let secondScore = sortedCandidates.dropFirst().first?.deepScore ?? 0
        let lead = (firstScore - secondScore) / max(firstScore, 1e-6)
        let hasStrongEvidence = first.maskPromptUsed != nil
            && first.localDetailScore != nil
            && first.issues.isEmpty
        if lead >= 0.12, hasStrongEvidence, !first.usedFallbackMask {
            return .high
        }
        if lead >= 0.05 || (hasStrongEvidence && first.usedFallbackMask) {
            return .medium
        }
        return .low
    }

    private func evaluate(
        _ candidate: DeepAIReviewInputCandidate,
        request: DeepAIReviewRequest,
    ) async throws -> DeepAIReviewCandidate {
        Logger.process.debugMessageOnly(
            "RawCullDeepAIReviewPipeline.evaluate(): evaluating \(candidate.fileName)",
        )
        let image: CGImage
        do {
            image = try await decoder.image(
                for: candidate,
                maximumPixelSize: maximumPixelSize,
                source: request.scoringSource,
            )
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            Logger.process.debugMessageOnly(
                "RawCullDeepAIReviewPipeline.evaluate(): image decode failed for \(candidate.fileName): \(error)",
            )
            return Self.failedCandidate(
                candidate,
                issue: .imageDecodeFailed,
            )
        }

        let prompts = Self.promptAttempts(
            preset: request.preset,
            subjectLabel: candidate.subjectLabel,
        )
        let source = AIImageSource(
            id: candidate.fileID,
            url: candidate.url,
            displayName: candidate.fileName,
        )
        let render = DeepAIReviewRenderMaskStore.Render(
            source: request.scoringSource,
            maximumPixelSize: maximumPixelSize,
            width: image.width,
            height: image.height,
        )
        let stores = maskStores.map { DeepAIReviewRenderMaskStore(store: $0, render: render) }
        let repository = SubjectMaskRepository(configuration: maskConfiguration, stores: stores)
        let selector = SubjectMaskSelector(
            repository: repository,
            segmentationService: SegmentationService(
                provider: provider, stores: stores, maxSide: maskConfiguration.inputMaxSide,
            ),
        )
        let selection: SubjectMaskSelection
        do {
            Logger.process.debugMessageOnly(
                "RawCullDeepAIReviewPipeline.evaluate(): requesting a subject mask "
                    + "for \(candidate.fileName) with \(prompts.count) prompt attempts",
            )
            let strategy = SubjectMaskSelectionStrategy(
                orderedPrompts: prompts,
                minimumQuality: .warning,
                acquisitionPolicy: .cacheFirstGenerateIfMissing,
            )
            selection = try await selector.select(for: source, image: image, strategy: strategy)
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            Logger.process.debugMessageOnly(
                "RawCullDeepAIReviewPipeline.evaluate(): subject mask acquisition failed for \(candidate.fileName): \(error)",
            )
            return Self.failedCandidate(
                candidate,
                issue: .maskAcquisitionFailed(String(describing: error)),
            )
        }

        guard Self.maskFits(selection, image: image) else {
            return Self.failedCandidate(
                candidate,
                issue: .maskAcquisitionFailed("The cached subject mask does not match the decoded image size."),
            )
        }

        guard let selected = selection.selected else {
            Logger.process.debugMessageOnly(
                "RawCullDeepAIReviewPipeline.evaluate(): no subject mask was selected for \(candidate.fileName)",
            )
            let failure = selection.attempts.lazy.compactMap { attempt -> String? in
                if case let .failed(reason) = attempt.outcome {
                    reason
                } else {
                    nil
                }
            }.first
            return Self.failedCandidate(
                candidate,
                issue: failure.map(DeepAIReviewCandidateIssue.maskAcquisitionFailed)
                    ?? .maskUnavailable,
            )
        }

        let usedFallback = prompts.firstIndex(of: selected.result.prompt).map { $0 > 0 } ?? true
        let usableMask = selected.quality.level.rank >= SubjectMaskQualityLevel.warning.rank
        var issues: [DeepAIReviewCandidateIssue] = []
        if !usableMask {
            issues.append(.poorMaskQuality)
        }

        let promptVerified = Self.requestedPromptObtained(
            preset: request.preset,
            selectedPrompt: selected.result.prompt,
            usedFallback: usedFallback,
            usableMask: usableMask,
        )
        if request.preset == .headFace, !promptVerified {
            issues.append(.specificPromptNotFound)
        }

        let focusEvidence: SubjectMaskFocusEvidence?
        if usableMask {
            do {
                Logger.process.debugMessageOnly(
                    "RawCullDeepAIReviewPipeline.evaluate(): scoring subject detail for \(candidate.fileName)",
                )
                focusEvidence = try await focusScorer.score(
                    image: image,
                    subjectMask: selected.result.mask,
                    normalizedAFPoint: candidate.normalizedAFPoint,
                    iso: candidate.iso,
                )
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                Logger.process.debugMessageOnly(
                    "RawCullDeepAIReviewPipeline.evaluate(): subject-detail scoring failed for \(candidate.fileName): \(error)",
                )
                focusEvidence = nil
            }
        } else {
            focusEvidence = nil
        }

        if focusEvidence == nil {
            issues.append(.subjectDetailUnavailable)
        } else {
            if focusEvidence?.usableLocalPatch == false {
                issues.append(.noReliableLocalPatch)
            }
            if focusEvidence?.backgroundDominancePenaltyApplied == true {
                issues.append(.backgroundDetailDominated)
            }
        }

        let key = await repository.storageKey(for: source, prompt: selected.result.prompt)
        let result = DeepAIReviewCandidate(
            fileID: candidate.fileID,
            fileName: candidate.fileName,
            rank: candidate.burstRank,
            isCompleted: true,
            deepScore: focusEvidence?.finalScore,
            normalSharpnessScore: candidate.normalSharpnessScore,
            broadSubjectScore: focusEvidence?.broadSubjectScore,
            localDetailScore: focusEvidence?.localDetailScore,
            fineDetailScore: focusEvidence?.fineDetailScore,
            maskPromptUsed: selected.result.prompt,
            maskConfidence: selected.result.confidence,
            maskCoverage: focusEvidence?.maskCoverage ?? selected.geometry.coverage,
            autofocusInsideMask: focusEvidence?.autofocusInsideMask,
            promptVerified: promptVerified,
            usedFallbackMask: usedFallback,
            issues: issues,
            maskStorageKey: render.storageKey(for: key),
        )
        Logger.process.debugMessageOnly(
            "RawCullDeepAIReviewPipeline.evaluate(): finished \(candidate.fileName); score available: \(result.deepScore != nil)",
        )
        return result
    }

    private nonisolated static func selectedCandidates(
        from candidates: [DeepAIReviewInputCandidate],
    ) -> [DeepAIReviewInputCandidate] {
        let ranked = candidates.sorted {
            if $0.burstRank == $1.burstRank {
                $0.fileName.localizedStandardCompare($1.fileName) == .orderedAscending
            } else {
                $0.burstRank < $1.burstRank
            }
        }
        return ranked.count > 12 ? Array(ranked.prefix(8)) : ranked
    }

    private nonisolated static func automaticPromptAttempts(
        subjectLabel: String?,
    ) -> [SubjectSegmentationPrompt] {
        let label = subjectLabel?.lowercased() ?? ""
        if containsAny(label, terms: ["bird", "raptor", "wildlife"]) {
            return [.birdHead, .bird, .subject]
        }
        if containsAny(label, terms: ["person", "people", "human", "face"]) {
            return [.face, .person, .subject]
        }
        if label.contains("deer") {
            return [.animalHead, .deer, .animal, .subject]
        }
        if containsAny(label, terms: ["animal", "mammal"]) {
            return [.animalHead, .animal, .subject]
        }
        return [.subject]
    }

    private nonisolated static func specificPromptAttempts(
        subjectLabel: String?,
    ) -> [SubjectSegmentationPrompt] {
        automaticPromptAttempts(subjectLabel: subjectLabel)
    }

    private nonisolated static func containsAny(
        _ value: String,
        terms: [String],
    ) -> Bool {
        terms.contains { value.contains($0) }
    }

    private nonisolated static func requestedPromptObtained(
        preset: DeepAIReviewPreset,
        selectedPrompt: SubjectSegmentationPrompt,
        usedFallback: Bool,
        usableMask: Bool,
    ) -> Bool {
        guard usableMask else { return false }
        return switch preset {
        case .fullSubject:
            selectedPrompt == .subject

        case .headFace:
            !usedFallback && [.birdHead, .animalHead, .face].contains(selectedPrompt)

        case .auto:
            !usedFallback
        }
    }

    private nonisolated static func failedCandidate(
        _ candidate: DeepAIReviewInputCandidate,
        issue: DeepAIReviewCandidateIssue,
    ) -> DeepAIReviewCandidate {
        DeepAIReviewCandidate(
            fileID: candidate.fileID,
            fileName: candidate.fileName,
            rank: candidate.burstRank,
            isCompleted: true,
            deepScore: nil,
            normalSharpnessScore: candidate.normalSharpnessScore,
            broadSubjectScore: nil,
            localDetailScore: nil,
            fineDetailScore: nil,
            maskPromptUsed: nil,
            maskConfidence: nil,
            maskCoverage: nil,
            autofocusInsideMask: nil,
            promptVerified: nil,
            usedFallbackMask: false,
            issues: [issue],
        )
    }

    private nonisolated static func placeholder(
        _ candidate: DeepAIReviewInputCandidate,
    ) -> DeepAIReviewCandidate {
        DeepAIReviewCandidate(
            fileID: candidate.fileID,
            fileName: candidate.fileName,
            rank: candidate.burstRank,
            isCompleted: false,
            deepScore: nil,
            normalSharpnessScore: candidate.normalSharpnessScore,
            broadSubjectScore: nil,
            localDetailScore: nil,
            fineDetailScore: nil,
            maskPromptUsed: nil,
            maskConfidence: nil,
            maskCoverage: nil,
            autofocusInsideMask: nil,
            promptVerified: nil,
            usedFallbackMask: false,
            issues: [],
        )
    }

    private nonisolated static func progress(
        request: DeepAIReviewRequest,
        selectedCandidates: [DeepAIReviewInputCandidate],
        completed: [DeepAIReviewCandidate],
        currentFileName: String?,
    ) -> DeepAIReviewProgress {
        let completedByID = Dictionary(uniqueKeysWithValues: completed.map { ($0.fileID, $0) })
        let rows = selectedCandidates.map { candidate in
            completedByID[candidate.fileID] ?? placeholder(candidate)
        }
        return DeepAIReviewProgress(
            groupID: request.groupID,
            completedCount: completed.count,
            totalCount: selectedCandidates.count,
            currentFileName: currentFileName,
            candidates: rows,
        )
    }

    private nonisolated static func makeResult(
        request: DeepAIReviewRequest,
        candidates: [DeepAIReviewCandidate],
    ) -> DeepAIReviewResult {
        Logger.process.debugMessageOnly(
            "RawCullDeepAIReviewPipeline.makeResult(): building a result from \(candidates.count) evaluated candidates",
        )
        let sorted = candidates.sorted {
            let lhs = $0.deepScore ?? -.infinity
            let rhs = $1.deepScore ?? -.infinity
            if lhs == rhs {
                return $0.rank < $1.rank
            }
            return lhs > rhs
        }
        let recommended = sorted.first { $0.deepScore?.isFinite == true }
        var reasons: [DeepAIReviewReason] = []
        if let recommended {
            reasons.append(.strongestSubjectDetail)
            if recommended.autofocusInsideMask == true {
                reasons.append(.autofocusInsideSubject)
            }
            if recommended.localDetailScore != nil {
                reasons.append(.localDetailEvidence)
            }
            if recommended.requestedPromptObtained == true {
                reasons.append(.requestedPromptMatched)
            }
        }
        let cautions = candidates
            .flatMap(\.issues)
            .reduce(into: [DeepAIReviewCandidateIssue]()) { result, issue in
                if !result.contains(issue) {
                    result.append(issue)
                }
            }
        let result = DeepAIReviewResult(
            groupID: request.groupID,
            groupSignature: request.groupSignature,
            preset: request.preset,
            candidates: sorted,
            recommendedFileID: recommended?.fileID,
            confidence: confidence(sortedCandidates: sorted),
            reasons: reasons,
            cautions: cautions,
            timestamp: Date(),
        )
        Logger.process.debugMessageOnly(
            "RawCullDeepAIReviewPipeline.makeResult(): result created; winner available: \(result.recommendedFileID != nil)",
        )
        return result
    }
}

extension DeepAIReviewCandidateIssue: Error {}
