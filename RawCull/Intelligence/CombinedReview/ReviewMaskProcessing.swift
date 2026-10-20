import CoreGraphics
import Foundation

nonisolated struct ReviewRegisteredCandidate: Sendable {
    let retained: ObjectInstanceDeduplicator.Retained
    let registration: ReviewMaskRegistration
}

/// Per-image worker. Full-raster scans never execute on the UI actor.
/// Cache only the most recently used foreground to bound additional raster memory.
actor ReviewMaskProcessing {
    private var cachedSubjectID: ReviewSubjectID?
    private var cachedMask: CGImage?
    private var cachedForeground: SubjectMaskForeground?

    func register(_ candidates: [ObjectInstanceDeduplicator.Candidate], source: ReviewImageSource) throws -> [ReviewRegisteredCandidate] {
        var registrations: [String: ReviewMaskRegistration] = [:]
        let registered = try candidates.map { candidate in
            try Task.checkCancellation()
            let registration = try ReviewMaskRegistration.make(mask: candidate.mask, source: source, producerBounds: candidate.normalizedBoundingBox)
            registrations[candidate.sourceInstanceID] = registration
            return try ObjectInstanceDeduplicator.candidate(
                concept: candidate.concept.query, mask: candidate.mask, score: candidate.score,
                bounds: registration.normalizedBounds(width: source.image.width, height: source.image.height),
                id: candidate.sourceInstanceID,
            )
        }
        let retained = ObjectInstanceDeduplicator.retain(registered, maximumCount: 8)
        try Task.checkCancellation()
        return try retained.map { candidate in
            guard let registration = registrations[candidate.descriptor.sourceInstanceID] else { throw ReviewRunError.invalidEvidence }
            return .init(retained: candidate, registration: registration)
        }
    }

    func retainedIDs(_ candidates: [ObjectInstanceDeduplicator.Candidate]) throws -> Set<String> {
        try Task.checkCancellation()
        let ids = Set(ObjectInstanceDeduplicator.retain(candidates, maximumCount: 8).map(\.descriptor.sourceInstanceID))
        try Task.checkCancellation()
        return ids
    }

    func assignPriority(_ subjects: [ReviewSubjectRecord], cues: [ReviewPrimarySubjectCue], contextual: [String],
                        masks: [ReviewSubjectID: CGImage], provenance: String) throws -> [ReviewSubjectRecord] {
        try Task.checkCancellation()
        return try ReviewSubjectPriority.assign(subjects, cues: cues, contextual: contextual, masks: masks, provenance: provenance)
    }

    func cropSupport(subjectID: ReviewSubjectID, mask: CGImage, width: Int, height: Int,
                     cropRect: CGRect, encoderRect: CGRect, sourceEdgeContact: Bool) throws -> ReviewCropSupport {
        try Task.checkCancellation()
        let foreground: SubjectMaskForeground
        if cachedSubjectID == subjectID, cachedMask === mask, let cachedForeground,
           cachedForeground.width == width, cachedForeground.height == height {
            foreground = cachedForeground
        } else {
            cachedForeground = nil
            foreground = try SubjectMaskForeground.decode(mask, width: width, height: height)
            cachedSubjectID = subjectID
            cachedMask = mask
            cachedForeground = foreground
        }
        let crop = ReviewMaskRegistration.retainedFraction(foreground, in: cropRect)
        try Task.checkCancellation()
        let encoder = cropRect == encoderRect ? crop : ReviewMaskRegistration.retainedFraction(foreground, in: encoderRect)
        try Task.checkCancellation()
        return .init(registrationVersion: ReviewMaskRegistration.version,
                     subjectForegroundRetained: crop, encoderForegroundRetained: encoder,
                     sourceEdgeContact: sourceEdgeContact,
                     anatomicalSupport: "unverified; foreground retention is not semantic identity")
    }
}
