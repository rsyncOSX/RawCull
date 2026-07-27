import CoreGraphics
import Foundation
import PhotoAIContracts

public enum SubjectMaskAcquisitionPolicy: String, Codable, Sendable {
    case cacheOnly
    case cacheFirstGenerateIfMissing
}

public struct SubjectMaskSelectionStrategy: Sendable {
    public let orderedPrompts: [SubjectSegmentationPrompt]
    public let minimumQuality: SubjectMaskQualityLevel
    public let minimumConfidence: Float
    public let acquisitionPolicy: SubjectMaskAcquisitionPolicy
    public let stopsAtFirstAcceptableMask: Bool

    public init(
        orderedPrompts: [SubjectSegmentationPrompt] = [.subject, .person, .bird, .animal],
        minimumQuality: SubjectMaskQualityLevel = .warning,
        minimumConfidence: Float = 0,
        acquisitionPolicy: SubjectMaskAcquisitionPolicy = .cacheFirstGenerateIfMissing,
        stopsAtFirstAcceptableMask: Bool = true
    ) {
        var seen: Set<SubjectSegmentationPrompt> = []
        self.orderedPrompts = orderedPrompts.filter { seen.insert($0).inserted }
        self.minimumQuality = minimumQuality
        self.minimumConfidence = minimumConfidence
        self.acquisitionPolicy = acquisitionPolicy
        self.stopsAtFirstAcceptableMask = stopsAtFirstAcceptableMask
    }
}

public struct SubjectMaskSelectionCandidate: Sendable {
    public let result: SubjectSegmentationResult
    public let geometry: SubjectMaskGeometry
    public let quality: SubjectMaskQuality
    public let wasCached: Bool

    public init(
        result: SubjectSegmentationResult,
        geometry: SubjectMaskGeometry,
        quality: SubjectMaskQuality,
        wasCached: Bool
    ) {
        self.result = result
        self.geometry = geometry
        self.quality = quality
        self.wasCached = wasCached
    }
}

public struct SubjectMaskSelectionAttempt: Equatable, Sendable {
    public enum Outcome: Equatable, Sendable {
        case cacheMiss
        case candidate(quality: SubjectMaskQualityLevel, confidence: Float, wasCached: Bool)
        case failed(String)
    }

    public let prompt: SubjectSegmentationPrompt
    public let outcome: Outcome

    public init(prompt: SubjectSegmentationPrompt, outcome: Outcome) {
        self.prompt = prompt
        self.outcome = outcome
    }
}

public struct SubjectMaskSelection: Sendable {
    public let selected: SubjectMaskSelectionCandidate?
    public let attempts: [SubjectMaskSelectionAttempt]
    public let metMinimumQuality: Bool

    public init(
        selected: SubjectMaskSelectionCandidate?,
        attempts: [SubjectMaskSelectionAttempt],
        metMinimumQuality: Bool
    ) {
        self.selected = selected
        self.attempts = attempts
        self.metMinimumQuality = metMinimumQuality
    }
}

/// Package-owned prompt fallback and mask selection. Candidate/winner policy
/// for a culling workflow remains in the host application.
public struct SubjectMaskSelector: Sendable {
    public let repository: SubjectMaskRepository
    public let segmentationService: SegmentationService?

    public init(
        repository: SubjectMaskRepository,
        segmentationService: SegmentationService? = nil
    ) {
        self.repository = repository
        self.segmentationService = segmentationService
    }

    public func select(
        for source: AIImageSource,
        image: CGImage? = nil,
        strategy: SubjectMaskSelectionStrategy = SubjectMaskSelectionStrategy()
    ) async throws -> SubjectMaskSelection {
        var attempts: [SubjectMaskSelectionAttempt] = []
        var best: SubjectMaskSelectionCandidate?

        for prompt in strategy.orderedPrompts {
            try Task.checkCancellation()
            let cached = await repository.cachedMask(for: source, prompt: prompt)
            let result: SubjectSegmentationResult
            let wasCached: Bool
            if let cached {
                result = cached
                wasCached = true
            } else if strategy.acquisitionPolicy == .cacheFirstGenerateIfMissing,
                      let segmentationService,
                      let image {
                do {
                    result = try await segmentationService.segment(
                        image: image,
                        source: source,
                        prompt: prompt
                    )
                    wasCached = false
                } catch is CancellationError {
                    throw CancellationError()
                } catch {
                    attempts.append(SubjectMaskSelectionAttempt(
                        prompt: prompt,
                        outcome: .failed(String(describing: error))
                    ))
                    continue
                }
            } else {
                attempts.append(SubjectMaskSelectionAttempt(
                    prompt: prompt,
                    outcome: .cacheMiss
                ))
                continue
            }

            let geometry = SubjectMaskGeometry.measure(mask: result.mask)
            let quality = SubjectMaskQuality(geometry: geometry)
            let candidate = SubjectMaskSelectionCandidate(
                result: result,
                geometry: geometry,
                quality: quality,
                wasCached: wasCached
            )
            attempts.append(SubjectMaskSelectionAttempt(
                prompt: prompt,
                outcome: .candidate(
                    quality: quality.level,
                    confidence: result.confidence,
                    wasCached: wasCached
                )
            ))
            if Self.isBetter(candidate, than: best) {
                best = candidate
            }
            if strategy.stopsAtFirstAcceptableMask,
               Self.meetsMinimum(candidate, strategy: strategy) {
                break
            }
        }

        return SubjectMaskSelection(
            selected: best,
            attempts: attempts,
            metMinimumQuality: best.map {
                Self.meetsMinimum($0, strategy: strategy)
            } ?? false
        )
    }

    private static func meetsMinimum(
        _ candidate: SubjectMaskSelectionCandidate,
        strategy: SubjectMaskSelectionStrategy
    ) -> Bool {
        candidate.quality.level.rank >= strategy.minimumQuality.rank
            && candidate.result.confidence >= strategy.minimumConfidence
    }

    private static func isBetter(
        _ candidate: SubjectMaskSelectionCandidate,
        than current: SubjectMaskSelectionCandidate?
    ) -> Bool {
        guard let current else { return true }
        if candidate.quality.level.rank != current.quality.level.rank {
            return candidate.quality.level.rank > current.quality.level.rank
        }
        if candidate.result.confidence != current.result.confidence {
            return candidate.result.confidence > current.result.confidence
        }
        return candidate.geometry.coverage > current.geometry.coverage
    }
}
