import Foundation

/// Validates structural support, never visual truth. IDs are resolved before this boundary.
nonisolated struct ReviewSynthesisGrounding {
    let result: CombinedReviewResult

    struct Support {
        let subjectID: ReviewSubjectID?
        let regionID: ReviewRegionID?
        let crop: Bool
        let measurement: Bool
        let observationText: String
        let criteria: ReviewCriterionObservations?

        init(subjectID: ReviewSubjectID?, regionID: ReviewRegionID?, crop: Bool, measurement: Bool, observationText: String = "", criteria: ReviewCriterionObservations? = nil) {
            self.subjectID = subjectID; self.regionID = regionID
            self.crop = crop; self.measurement = measurement; self.observationText = observationText; self.criteria = criteria
        }

        /// Prompt eligibility follows the same structural boundary as validation.
        var subjectDetailSupported: Bool {
            crop && subjectID != nil && regionID != nil && !measurement && (criteria?.detail.supported ?? ReviewSynthesisGrounding.hasTexture(observationText))
        }

        var claimTypes: String {
            if measurement {
                return "none"
            }
            if let criteria {
                let types = ReviewCriterionObservations.types.filter { criteria[$0]?.supported == true && ($0 != "detail" || subjectDetailSupported) }
                return types.isEmpty ? "none" : types.joined(separator: ",")
            }
            return "composition,visibility" + (ReviewSynthesisGrounding.hasLighting(observationText) ? ",exposure" : "") + (subjectDetailSupported ? ",detail" : "")
        }
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
            guard let regionID = observation.regionID else { return .init(subjectID: nil, regionID: nil, crop: false, measurement: false, observationText: observation.text, criteria: observation.criteria) }
            guard let region = result.regions.first(where: { $0.id == regionID }), region.imageID == result.file.id,
                  region.sourceIdentity == observation.provenance.sourceIdentity else { throw reject("synthesis.registeredObservationRegion") }
            if let subjectID = region.subjectID {
                guard result.subjects.contains(where: { $0.id == subjectID && $0.imageID == result.file.id && $0.availability == .available && $0.registration?.version == ReviewMaskRegistration.version && $0.registration?.sourceIdentity == region.sourceIdentity }) else { throw reject("synthesis.registeredRegionSubject") }
            }
            return .init(subjectID: region.subjectID, regionID: regionID,
                         crop: observation.targetIdentified == true, measurement: false, observationText: observation.text, criteria: observation.criteria)

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
        let subjectScoped = claim.subjectID != nil || claim.type == "detail"
        if subjectScoped, !subjects.isEmpty {
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
            guard subjects.count == 1, regions.count == 1, supported.contains(where: \.crop) else { throw ReviewValidationIssue(.grounding, "synthesis.targetCropRequired", field: "claims.evidence") }
            guard !claim.text.contains(where: \.isNumber) else { throw ReviewValidationIssue(.grounding, "synthesis.numericPresentationIsDeterministic", field: "claims.text") }
        }
        if supported.contains(where: { $0.criteria != nil }) {
            guard claim.evidence.count == 1, supported.contains(where: { support in
                guard let entry = support.criteria?[claim.type], entry.supported,
                      claim.type != "detail" || support.subjectDetailSupported else { return false }
                return Self.sameText(claim.text, entry.text)
            }) else { throw ReviewValidationIssue(.grounding, "synthesis.criterionObservation", field: "claims.text") }
        } else {
            // Legacy observations remain inspectable with their conservative v15 checks.
            if claim.type == "detail" {
                guard Self.hasTexture(claim.text), supported.contains(where: { $0.subjectDetailSupported && Self.isExcerpt(claim.text, of: $0.observationText) }) else {
                    throw ReviewValidationIssue(.grounding, "synthesis.detailObservationExcerpt", field: "claims.text")
                }
            }
            if claim.type == "exposure" {
                guard Self.hasLighting(claim.text), supported.contains(where: { !$0.measurement && Self.hasLighting($0.observationText) && Self.isExcerpt(claim.text, of: $0.observationText) }) else {
                    throw ReviewValidationIssue(.grounding, "synthesis.exposureObservationExcerpt", field: "claims.text")
                }
            }
        }
        try validateFocusScope(claim, supported: supported, subjects: subjects)
        var qualified = claim
        let scopedSubjects = subjects.union(conflicts.compactMap(\.subjectID))
        let scopedRegions = regions.union(conflicts.compactMap(\.regionID))
        qualified.subjectID = claim.subjectID ?? (scopedSubjects.count == 1 ? scopedSubjects.first : nil)
        qualified.regionID = claim.regionID ?? (scopedRegions.count == 1 ? scopedRegions.first : nil)
        return qualified
    }

    private func validateFocusScope(_ claim: ReviewClaim, supported: [Support], subjects: Set<ReviewSubjectID>) throws {
        let words = claim.text.lowercased().split(whereSeparator: { !$0.isLetter })
        guard words.contains(where: { $0.hasPrefix("focus") || $0.hasPrefix("sharp") || $0.hasPrefix("blur") }) else { return }
        guard subjects.count == 1, supported.contains(where: { support in
            guard support.crop, support.subjectID == subjects.first else { return false }
            if let criteria = support.criteria {
                guard let entry = criteria[claim.type], entry.supported else { return false }
                return Self.sameText(claim.text, entry.text)
            }
            return Self.isExcerpt(claim.text, of: support.observationText)
        }) else {
            throw ReviewValidationIssue(.grounding, "synthesis.focusNeedsRegisteredSubjectCrop", field: "claims.evidence")
        }
    }

    private static func sameText(_ left: String, _ right: String) -> Bool {
        let trim = CharacterSet.whitespacesAndNewlines.union(.punctuationCharacters)
        return left.lowercased().trimmingCharacters(in: trim) == right.lowercased().trimmingCharacters(in: trim)
    }

    private static func words(_ text: String) -> [String] {
        text.lowercased().split(whereSeparator: { !$0.isLetter && !$0.isNumber }).map(String.init)
    }

    /// Whole sentences preserve negation and modifiers that a substring could omit.
    private static func isExcerpt(_ text: String, of observation: String) -> Bool {
        let claim = words(text)
        guard !claim.isEmpty else { return false }
        return observation.split(whereSeparator: { ".!?".contains($0) }).contains { words(String($0)) == claim }
            || words(observation) == claim
    }

    static func hasTexture(_ text: String) -> Bool {
        words(text).contains { $0.hasPrefix("textur") }
    }

    static func hasLighting(_ text: String) -> Bool {
        let lower = text.lowercased()
        return lower.contains("golden light") || lower.contains("warm light") || lower.contains("soft light") || words(text).contains { ["lighting", "sunlight", "illumination", "illuminated", "sunlit", "shadow", "shadows", "highlight", "highlights", "exposure", "overexposed", "underexposed", "contrast"].contains($0) }
    }

    func measurementSummary(_ measurement: ReviewMeasurement) throws -> String {
        _ = try support(.init(kind: .measurement, id: measurement.id.rawValue))
        guard let measurement = result.measurements.first(where: { $0.id == measurement.id }) else { throw ReviewRunError.invalidEvidence }
        return "Subject \(measurement.subjectID.rawValue) · measurement \(measurement.id.rawValue) · scorer \(measurement.scorerVersion ?? "unknown"): " + measurement.values.keys.sorted().map { "\($0)=\(measurement.values[$0, default: 0])" }.joined(separator: ", ") + ". Render-dependent, uncalibrated metrics."
    }
}
