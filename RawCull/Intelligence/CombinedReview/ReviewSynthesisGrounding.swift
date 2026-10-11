import Foundation

/// Validates structural support, never visual truth. IDs are resolved before this boundary.
nonisolated struct ReviewSynthesisGrounding {
    let result: CombinedReviewResult

    struct Support {
        let subjectID: ReviewSubjectID?
        let regionID: ReviewRegionID?
        let crop: Bool
        let measurement: Bool
    }

    func support(_ reference: ReviewEvidenceReference) throws -> Support {
        func reject(_ check: String) -> ReviewValidationIssue {
            .init(.ownership, check, field: "claims.evidence", reference: reference)
        }
        switch reference.kind {
        case .observation:
            guard let observation = result.observations.first(where: { $0.id.rawValue == reference.id }),
                  observation.provenance.imageID == result.file.id,
                  observation.availability == .available,
                  observation.provenance.compatibility.fields["stageVersion"] == ReviewPipelineContract.stageVersions[observation.regionID == nil ? .overview : .cropObservation],
                  !observation.provenance.workID.rawValue.contains(":reconcile") else { throw reject("synthesis.availableIndependentObservation") }
            guard let regionID = observation.regionID else { return .init(subjectID: nil, regionID: nil, crop: false, measurement: false) }
            guard let region = result.regions.first(where: { $0.id == regionID }), region.imageID == result.file.id,
                  region.sourceIdentity == observation.provenance.sourceIdentity else { throw reject("synthesis.registeredObservationRegion") }
            if let subjectID = region.subjectID {
                guard result.subjects.contains(where: { $0.id == subjectID && $0.imageID == result.file.id && $0.availability == .available && $0.registration?.version == ReviewMaskRegistration.version && $0.registration?.sourceIdentity == region.sourceIdentity }) else { throw reject("synthesis.registeredRegionSubject") }
            }
            return .init(subjectID: region.subjectID, regionID: regionID,
                         crop: observation.targetIdentified == true, measurement: false)
        case .measurement:
            guard let measurement = result.measurements.first(where: { $0.id.rawValue == reference.id }),
                  measurement.provenance.imageID == result.file.id, measurement.hasCurrentMaskSemantics,
                  measurement.values.values.allSatisfy(\.isFinite),
                  result.subjects.contains(where: { $0.id == measurement.subjectID && $0.imageID == result.file.id && $0.availability == .available && $0.registration?.version == ReviewMaskRegistration.version && $0.registration?.sourceIdentity == measurement.maskContract?.sourceIdentity }) else { throw reject("synthesis.qualifiedSubjectMeasurement") }
            return .init(subjectID: measurement.subjectID, regionID: nil, crop: false, measurement: true)
        default: throw reject("synthesis.supportKind")
        }
    }

    func validate(_ claim: ReviewClaim) throws -> ReviewClaim {
        let supported = try claim.evidence.map(support)
        let conflicts = try claim.contradictions.map(support)
        guard ["composition", "exposure", "visibility", "detail", "suggestion"].contains(claim.type) else { throw ReviewValidationIssue(.unsupportedDomain, "synthesis.claimType", field: "claims.type") }
        let subjects = Set(supported.compactMap(\.subjectID))
        let regions = Set(supported.compactMap(\.regionID))
        if let subject = claim.subjectID {
            guard subjects == [subject] else { throw ReviewValidationIssue(.ownership, "synthesis.claimSubject", field: "claims.subjectID") }
        }
        if let region = claim.regionID {
            guard regions == [region] else { throw ReviewValidationIssue(.ownership, "synthesis.claimRegion", field: "claims.regionID") }
        }
        guard Set(claim.evidence).isDisjoint(with: claim.contradictions) else { throw ReviewValidationIssue(.grounding, "synthesis.selfContradiction", field: "claims.contradictions") }
        if !subjects.isEmpty {
            guard conflicts.allSatisfy({ support in support.subjectID.map(subjects.contains) ?? true }) else { throw ReviewValidationIssue(.ownership, "synthesis.contradictionSubject", field: "claims.contradictions") }
        }
        // Measurements establish only deterministic metric summaries, not model-written photographic claims.
        guard supported.contains(where: { !$0.measurement }) else { throw ReviewValidationIssue(.grounding, "synthesis.observationRequired", field: "claims.evidence") }
        if supported.contains(where: \.measurement) {
            guard claim.type == "detail", supported.filter(\.crop).allSatisfy({ support in support.subjectID.map { subjects == [$0] } ?? false }) else {
                throw ReviewValidationIssue(.ownership, "synthesis.measurementCropSubject", field: "claims.evidence")
            }
        }
        if claim.type == "detail" {
            guard subjects.count <= 1, regions.count == 1, supported.contains(where: \.crop) else { throw ReviewValidationIssue(.grounding, "synthesis.targetCropRequired", field: "claims.evidence") }
            guard !claim.text.contains(where: \.isNumber) else { throw ReviewValidationIssue(.grounding, "synthesis.numericPresentationIsDeterministic", field: "claims.text") }
        }
        try validateFocusScope(claim, supported: supported, subjects: subjects)
        var qualified = claim
        qualified.subjectID = claim.subjectID ?? (subjects.count == 1 ? subjects.first : nil)
        qualified.regionID = claim.regionID ?? (regions.count == 1 ? regions.first : nil)
        return qualified
    }

    private func validateFocusScope(_ claim: ReviewClaim, supported: [Support], subjects: Set<ReviewSubjectID>) throws {
        let words = claim.text.lowercased().split(whereSeparator: { !$0.isLetter })
        guard words.contains(where: { $0.hasPrefix("focus") || $0.hasPrefix("sharp") || $0.hasPrefix("blur") }) else { return }
        guard subjects.count == 1, supported.contains(where: { $0.crop && $0.subjectID == subjects.first }) else {
            throw ReviewValidationIssue(.grounding, "synthesis.focusNeedsRegisteredSubjectCrop", field: "claims.evidence")
        }
    }

    func measurementSummary(_ measurement: ReviewMeasurement) throws -> String {
        _ = try support(.init(kind: .measurement, id: measurement.id.rawValue))
        guard let measurement = result.measurements.first(where: { $0.id == measurement.id }) else { throw ReviewRunError.invalidEvidence }
        return "Subject \(measurement.subjectID.rawValue) · measurement \(measurement.id.rawValue) · scorer \(measurement.scorerVersion ?? "unknown"): " + measurement.values.keys.sorted().map { "\($0)=\(measurement.values[$0, default: 0])" }.joined(separator: ", ") + ". Render-dependent, uncalibrated metrics."
    }
}
