import CoreGraphics
import CoreImage
import CoreImage.CIFilterBuiltins
import Foundation
import ImageIO
import Observation
import PhotoAIContracts
import PhotoAIWorkflows

nonisolated enum DeepAIReviewPreset: String, CaseIterable, Codable, Identifiable, Sendable {
    case auto
    case fullSubject
    case headFace

    var id: String { rawValue }
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
    var id: UUID { fileID }

    let fileID: UUID
    let fileName: String
    let url: URL
    let burstRank: Int
    let normalSharpnessScore: Float?
    let subjectLabel: String?
    let normalizedAFPoint: CGPoint?
}

nonisolated struct DeepAIReviewRequest: Equatable, Sendable {
    let groupID: Int
    let groupSignature: BurstGroupSignature
    let candidates: [DeepAIReviewInputCandidate]
    let preset: DeepAIReviewPreset
    let scoringSource: SharpnessScoringSource
}

nonisolated struct DeepAIReviewCandidate: Equatable, Identifiable, Sendable {
    var id: UUID { fileID }

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
    let promptVerified: Bool?
    let usedFallbackMask: Bool
    let issues: [DeepAIReviewCandidateIssue]
}

nonisolated struct DeepAIReviewResult: Equatable, Sendable {
    let groupID: Int
    let groupSignature: BurstGroupSignature
    let preset: DeepAIReviewPreset
    let candidates: [DeepAIReviewCandidate]
    let recommendedFileID: UUID?
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
    case failed(groupID: Int?, failure: DeepAIReviewFailure)
    case completed(DeepAIReviewResult)

    var activeGroupID: Int? {
        switch self {
        case .idle:
            nil
        case let .preparing(groupID, _), let .completing(groupID):
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
        case .idle, .failed, .completed:
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

@Observable @MainActor
final class DeepAIReviewFeature {
    var preset: DeepAIReviewPreset = .auto
    private(set) var state: DeepAIReviewState = .idle
    private(set) var availability: RawCullAICapabilityStatus
    private(set) var results: [BurstGroupSignature: DeepAIReviewResult] = [:]

    @ObservationIgnored private var service: (any DeepAIReviewServicing)?
    @ObservationIgnored private var task: Task<Void, Never>?
    @ObservationIgnored private var generation = 0

    init(
        availability: RawCullAICapabilityStatus = .unavailable(
            reason: "SAM 3 has not been configured for in-process review.",
        ),
        service: (any DeepAIReviewServicing)? = nil,
    ) {
        self.availability = availability
        self.service = service
    }

    var isRunning: Bool { state.isRunning }

    func result(for signature: BurstGroupSignature) -> DeepAIReviewResult? {
        results[signature]
    }

    func install(
        service: (any DeepAIReviewServicing)?,
        availability: RawCullAICapabilityStatus,
    ) {
        self.service = service
        self.availability = availability
        if !availability.isAvailable, isRunning {
            cancel()
        }
    }

    func start(_ request: DeepAIReviewRequest) async {
        guard !isRunning else { return }
        guard availability.isAvailable, let service else {
            state = .failed(
                groupID: request.groupID,
                failure: .modelUnavailable(Self.unavailableReason(for: availability)),
            )
            return
        }
        guard !request.candidates.isEmpty else {
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
        let task = Task {
            do {
                let result = try await service.review(request) { progress in
                    await feature.receive(progress, generation: runGeneration)
                }
                try Task.checkCancellation()
                guard feature.generation == runGeneration else { return }
                feature.state = .completing(groupID: request.groupID)
                feature.results[result.groupSignature] = result
                feature.state = .completed(result)
            } catch is CancellationError {
                guard feature.generation == runGeneration else { return }
                feature.state = .idle
            } catch let failure as DeepAIReviewFailure {
                guard feature.generation == runGeneration else { return }
                feature.state = .failed(groupID: request.groupID, failure: failure)
            } catch {
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
        if generation == runGeneration {
            self.task = nil
        }
    }

    func cancel() {
        generation &+= 1
        task?.cancel()
        task = nil
        state = .idle
    }

    func reset() {
        cancel()
        results = [:]
    }

    private func receive(_ progress: DeepAIReviewProgress, generation: Int) {
        guard self.generation == generation, !Task.isCancelled else { return }
        state = .running(progress)
    }

    private nonisolated static func unavailableReason(
        for status: RawCullAICapabilityStatus,
    ) -> String {
        switch status {
        case .checking:
            "RawCull is still checking the SAM 3 model."
        case .available:
            "The SAM 3 in-process pipeline is unavailable."
        case let .missing(expectedLocations):
            expectedLocations.first.map {
                "Install SAM 3 at \($0.path)."
            } ?? "Install the SAM 3 model."
        case let .invalid(location, reason):
            location.map {
                "The SAM 3 model at \($0.path) is invalid: \(reason)"
            } ?? "The SAM 3 model is invalid: \(reason)"
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
        try Task.checkCancellation()
        switch source {
        case .embeddedPreview:
            let source = AIImageSource(
                id: candidate.fileID,
                url: candidate.url,
                displayName: candidate.fileName,
            )
            return try await RawCullSimilarityImageDecoder(
                maxPixelSize: maximumPixelSize,
            ).image(for: source)

        case .rawDemosaic:
            guard let rawFilter = CIRAWFilter(imageURL: candidate.url) else {
                throw DeepAIReviewCandidateIssue.imageDecodeFailed
            }
            rawFilter.sharpnessAmount = 0
            rawFilter.detailAmount = 0.6
            rawFilter.contrastAmount = 1
            rawFilter.exposure = 0

            guard var image = rawFilter.outputImage else {
                throw DeepAIReviewCandidateIssue.imageDecodeFailed
            }
            let maximumDimension = max(image.extent.width, image.extent.height)
            if maximumDimension > CGFloat(maximumPixelSize), maximumDimension > 0 {
                let scale = CGFloat(maximumPixelSize) / maximumDimension
                image = image.transformed(
                    by: CGAffineTransform(scaleX: scale, y: scale),
                )
            }
            try Task.checkCancellation()
            let context = CIContext(options: [
                .cacheIntermediates: false,
                .workingColorSpace: NSNull(),
            ])
            guard let result = context.createCGImage(image, from: image.extent) else {
                throw DeepAIReviewCandidateIssue.imageDecodeFailed
            }
            return result
        }
    }
}

nonisolated struct RawCullDeepAIReviewPipeline: DeepAIReviewServicing, Sendable {
    private let selector: SubjectMaskSelector
    private let decoder: any DeepAIReviewImageDecoding
    private let focusScorer: any SubjectMaskFocusScoring
    private let maximumPixelSize: Int

    init(
        selector: SubjectMaskSelector,
        decoder: any DeepAIReviewImageDecoding = RawCullDeepReviewImageDecoder(),
        focusScorer: any SubjectMaskFocusScoring = SubjectMaskFocusScorer(),
        maximumPixelSize: Int = SharpnessScoringSizeOption.maximumPixelSize,
    ) {
        self.selector = selector
        self.decoder = decoder
        self.focusScorer = focusScorer
        self.maximumPixelSize = maximumPixelSize
    }

    @concurrent
    func review(
        _ request: DeepAIReviewRequest,
        progress: @escaping @Sendable (DeepAIReviewProgress) async -> Void,
    ) async throws -> DeepAIReviewResult {
        let candidates = Self.selectedCandidates(from: request.candidates)
        guard !candidates.isEmpty else { throw DeepAIReviewFailure.noCandidates }

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
        return Self.makeResult(request: request, candidates: completed)
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
        let selection: SubjectMaskSelection
        do {
            selection = try await selector.select(
                for: source,
                image: image,
                strategy: SubjectMaskSelectionStrategy(
                    orderedPrompts: prompts,
                    minimumQuality: .warning,
                    acquisitionPolicy: .cacheFirstGenerateIfMissing,
                ),
            )
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            return Self.failedCandidate(
                candidate,
                issue: .maskAcquisitionFailed(String(describing: error)),
            )
        }

        guard let selected = selection.selected else {
            let failure = selection.attempts.lazy.compactMap { attempt -> String? in
                if case let .failed(reason) = attempt.outcome { reason } else { nil }
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

        let promptVerified = Self.promptVerified(
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
                focusEvidence = try await focusScorer.score(
                    image: image,
                    subjectMask: selected.result.mask,
                    normalizedAFPoint: candidate.normalizedAFPoint,
                )
            } catch is CancellationError {
                throw CancellationError()
            } catch {
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

        return DeepAIReviewCandidate(
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
        )
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

    private nonisolated static func promptVerified(
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
        let sorted = candidates.sorted {
            let lhs = $0.deepScore ?? -.infinity
            let rhs = $1.deepScore ?? -.infinity
            if lhs == rhs { return $0.rank < $1.rank }
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
            if recommended.promptVerified == true {
                reasons.append(.requestedPromptMatched)
            }
        }
        let cautions = candidates
            .flatMap(\.issues)
            .reduce(into: [DeepAIReviewCandidateIssue]()) { result, issue in
                if !result.contains(issue) { result.append(issue) }
            }
        return DeepAIReviewResult(
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
    }
}

extension DeepAIReviewCandidateIssue: Error {}
