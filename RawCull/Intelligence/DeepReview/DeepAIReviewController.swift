import Foundation
import Observation

nonisolated struct DeepAIReviewSourceCandidate: Equatable, Sendable {
    let fileID: UUID
    let fileName: String
    let url: URL
    let burstRank: Int
    let normalSharpnessScore: Float?
    let subjectLabel: String?
    let normalizedAFPoint: CGPoint?
}

nonisolated struct DeepAIReviewGroupContext: Equatable, Sendable {
    let groupID: Int
    let groupSignature: BurstGroupSignature
    let candidates: [DeepAIReviewSourceCandidate]
    let scoringSource: SharpnessScoringSource
}

@MainActor
protocol DeepAIReviewApplicationContext: AnyObject {
    var isDeepAIReviewBlockedByOtherWork: Bool { get }

    func deepAIReviewContext(
        for groupFiles: [FileItem],
    ) -> DeepAIReviewGroupContext?
}

nonisolated enum DeepAIReviewPresentationState: Equatable, Sendable {
    case checking(expectedLocations: [URL])
    case unavailable(reason: String)
    case ready
    case preparing(groupID: Int, totalCount: Int)
    case running(DeepAIReviewProgress)
    case completing(groupID: Int)
    case cancelled(groupID: Int)
    case failed(groupID: Int?, failure: DeepAIReviewFailure)
    case completed(DeepAIReviewResult)
}

/// Runtime-owned boundary for the optional Deep Review capability.
///
/// The controller adapts application burst evidence into a backend request and
/// exposes one stable model/actions surface. The operation model remains focused
/// on task ownership, progress, cancellation, and cached results.
@Observable @MainActor
final class DeepAIReviewController {
    @ObservationIgnored private let feature: DeepAIReviewFeature
    @ObservationIgnored private weak var applicationContext:
        (any DeepAIReviewApplicationContext)?

    init(feature: DeepAIReviewFeature = DeepAIReviewFeature()) {
        self.feature = feature
    }

    var preset: DeepAIReviewPreset {
        get { feature.preset }
        set { feature.preset = newValue }
    }

    var isRunning: Bool {
        feature.isRunning
    }

    var isActionUnavailable: Bool {
        !feature.availability.isAvailable
            || applicationContext?.isDeepAIReviewBlockedByOtherWork != false
            || feature.isRunning
    }

    func isRunning(groupID: Int?) -> Bool {
        feature.isRunning && feature.state.activeGroupID == groupID
    }

    func result(for signature: BurstGroupSignature) -> DeepAIReviewResult? {
        feature.result(for: signature)
    }

    func presentationState(
        groupID: Int,
        groupSignature: BurstGroupSignature,
    ) -> DeepAIReviewPresentationState {
        if let result = feature.result(for: groupSignature) {
            return .completed(result)
        }
        if let activeState = activePresentationState(groupID: groupID) {
            return activeState
        }
        return availabilityPresentationState
    }

    private func activePresentationState(
        groupID: Int,
    ) -> DeepAIReviewPresentationState? {
        switch feature.state {
        case let .preparing(activeGroupID, totalCount) where activeGroupID == groupID:
            .preparing(groupID: activeGroupID, totalCount: totalCount)

        case let .running(progress) where progress.groupID == groupID:
            .running(progress)

        case let .completing(activeGroupID) where activeGroupID == groupID:
            .completing(groupID: activeGroupID)

        case let .cancelled(activeGroupID) where activeGroupID == groupID:
            .cancelled(groupID: activeGroupID)

        case let .failed(activeGroupID, failure)
            where activeGroupID == nil || activeGroupID == groupID:
            .failed(groupID: activeGroupID, failure: failure)

        case .idle, .preparing, .running, .completing, .cancelled, .failed, .completed:
            nil
        }
    }

    private var availabilityPresentationState: DeepAIReviewPresentationState {
        switch feature.availability {
        case let .checking(expectedLocations):
            return .checking(expectedLocations: expectedLocations)

        case .available:
            return .ready

        case let .missing(expectedLocations):
            let reason = expectedLocations.first.map {
                "Install the selected segmentation model at \($0.path)."
            } ?? "Install the selected segmentation model."
            return .unavailable(reason: reason)

        case let .invalid(location, reason):
            let message = location.map {
                "The selected segmentation model at \($0.path) is invalid: \(reason)"
            } ?? "The selected segmentation model is invalid: \(reason)"
            return .unavailable(reason: message)

        case let .unavailable(reason):
            return .unavailable(reason: reason)
        }
    }

    func bindApplicationContext(_ context: any DeepAIReviewApplicationContext) {
        if let applicationContext {
            assert(applicationContext === context)
            return
        }
        applicationContext = context
    }

    func start(for groupFiles: [FileItem]) async {
        guard !isActionUnavailable,
              let context = applicationContext?.deepAIReviewContext(for: groupFiles)
        else { return }

        let request = DeepAIReviewRequest(
            groupID: context.groupID,
            groupSignature: context.groupSignature,
            candidates: context.candidates.map { candidate in
                DeepAIReviewInputCandidate(
                    fileID: candidate.fileID,
                    fileName: candidate.fileName,
                    url: candidate.url,
                    burstRank: candidate.burstRank,
                    normalSharpnessScore: candidate.normalSharpnessScore,
                    subjectLabel: candidate.subjectLabel,
                    normalizedAFPoint: candidate.normalizedAFPoint,
                )
            },
            preset: preset,
            scoringSource: context.scoringSource,
        )
        await feature.start(request)
    }

    func cancel() {
        feature.cancel()
    }

    func reset() {
        feature.reset()
    }

    func sharesFeatureIdentity(with feature: DeepAIReviewFeature) -> Bool {
        self.feature === feature
    }
}
