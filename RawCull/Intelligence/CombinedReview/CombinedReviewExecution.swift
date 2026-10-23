import AppKit
import CoreGraphics
import Foundation

nonisolated struct CombinedReviewPlan: Codable, Sendable {
    var omissions: [ReviewRegionOmission]?
    let subjects: [ReviewSubjectRecord]
    let regions: [ReviewRegionRecord]
    let uninspected: [ReviewRegionID]
}

nonisolated struct CombinedReviewHeadCandidates: Codable, Sendable {
    let records: [ReviewSubjectRecord]
    let omissions: [ReviewRegionOmission]
}

nonisolated struct CombinedReviewContext: Sendable {
    let snapshot: ReviewRunSnapshot
    let file: ReviewFileSnapshot
    let source: ReviewImageSource
    let qwen: ReviewModelSnapshot
    let overview: CombinedReviewOverview?
}

extension CombinedReviewFeature {
    func execute(_ backend: any CombinedReviewBackendServing) async throws {
        let snapshot = try currentManifest().snapshot
        results = []; selectionReport = nil; comparisonInputReference = nil
        let order = snapshot.files.sorted { $0.id.rawValue < $1.id.rawValue }
        let allocation = ReviewBudget.cropAllocation(images: order.map(\.id), counts: Dictionary(uniqueKeysWithValues: order.map { ($0.id, snapshot.depth.cropsPerImage) }), depth: snapshot.depth)
        for file in order {
            try Task.checkCancellation()
            activeFile = file
            cropAllowance = allocation.filter { $0 == file.id }.count
            result = .init(file: file)
            do {
                let context = try await prepare(backend)
                let (plan, masks, segments) = try await plan(backend, context: context)
                let terminal = try await inspect(backend, context: context, plan: plan, masks: masks, segmentIDs: segments)
                try await finish(backend, context: context, plan: plan, terminalIDs: terminal)
            } catch is CancellationError { throw CancellationError() } catch {
                for item in manifest?.work ?? [] where item.imageID == file.id && (item.state == .pending || item.state == .running) {
                    let diagnostic = await failureDiagnostic(error, item: item)
                    try Task.checkCancellation()
                    if item.state == .running {
                        try manifest?.finish(item.id, state: .failed, reason: diagnostic.compactReason)
                    } else {
                        try manifest?.skip(item.id, reason: diagnostic.compactReason)
                    }
                    if let index = manifest?.work.firstIndex(where: { $0.id == item.id }) {
                        manifest?.work[index].diagnostic = diagnostic
                    }
                }
                try await store.saveManifest(currentManifest())
                if snapshot.files.count == 1 {
                    throw error
                }
                limitation("Image review unavailable: " + ReviewValidationIssue.classify(error).check)
                result?.failures[Self.workID(file.id, "source").rawValue] = ReviewValidationIssue.classify(error).check
            }
            if let result {
                results.append(result)
            }
        }
        activeFile = nil
        if snapshot.files.count > 1 {
            try await compare(backend)
        }
        progress = results.contains { $0.report?.incomplete != false } ? "Complete with limitations" : "Complete"
    }

    func prepare(_ backend: any CombinedReviewBackendServing) async throws -> CombinedReviewContext {
        let run = try currentManifest(), snapshot = run.snapshot
        guard let file = activeFile, let preference = ReviewSourcePreference(rawValue: snapshot.sourcePreference), let qwen = snapshot.models["qwen"] else { throw ReviewRunError.invalidSnapshot }
        result = .init(file: file)
        progress = "Loading full review source"
        try await ReviewCatalogSession.revalidate(snapshot.files)
        let source = try await sourceLoader.load(.init(url: file.url, preference: preference, policy: .appearance))
        guard source.metadata.fileIdentity == file.fingerprint else { throw ReviewRunError.incompatible }
        let sourceID = Self.workID(file.id, "source"), overviewID = Self.workID(file.id, "overview")
        let sourceRecord: ReviewSourceRecord? = try await perform(sourceID) {
            .init(imageID: file.id, sourceIdentity: source.metadata.identity, width: source.image.width, height: source.image.height,
                  orientation: source.metadata.originalOrientation, fidelity: source.metadata.fidelity.rawValue, policy: source.metadata.policy.rawValue,
                  colorSpace: source.metadata.outputColorSpace, renderSettings: source.metadata.renderSettings, limitations: source.metadata.limitations)
        }
        guard let sourceRecord, sourceRecord.sourceIdentity == source.metadata.identity else { throw ReviewRunError.incompatible }
        result?.source = sourceRecord
        for reason in source.metadata.limitations {
            limitation(reason)
        }
        limitation("Eye localization unavailable. Head and subject masks do not establish eye detail.")
        if file.normalizedAFPoint == nil {
            limitation("AF mapping is unavailable for this review; focus measurements use subject masks without an AF point.")
        }
        limitation("Exposure and crop suggestions are hypotheses; no rendered edit has been evaluated. RAW recovery is untested.")
        let overviewInput = await retain(source.overview)
        result?.overviewInputReference = overviewInput
        progress = "Independent overview and subject discovery"
        let overview: CombinedReviewOverview? = try await perform(overviewID, category: .overview) {
            let prompt = try CombinedReviewResponse.admitted(CombinedReviewResponse.overviewInstruction, model: qwen, outputTokens: snapshot.responseTokens)
            let text = try await backend.respond(instruction: prompt, image: source.overview, tokens: snapshot.responseTokens)
            return try CombinedReviewResponse.validated(text) { try CombinedReviewResponse.overview($0) }
        }
        result?.overview = overview
        if let overview {
            for note in overview.validationNotes ?? [] {
                limitation(note)
            }
            let origin = try provenance(overviewID, source: source, input: overviewInput)
            result?.observations.append(.init(id: .init(rawValue: file.id.rawValue + ":overview"), regionID: nil,
                                              text: overview.observations, uncertainty: overview.uncertainty, availability: .available,
                                              provenance: origin))
        } else {
            limitation("Overview/discovery unavailable; crop observations remain independent.")
        }
        return .init(snapshot: snapshot, file: file, source: source, qwen: qwen, overview: overview)
    }

    func plan(_ backend: any CombinedReviewBackendServing, context: CombinedReviewContext) async throws -> (CombinedReviewPlan, [ReviewSubjectID: CGImage], [ReviewWorkID]) {
        let snapshot = context.snapshot, file = context.file, source = context.source, qwen = context.qwen
        let sourceID = Self.workID(file.id, "source"), overviewID = Self.workID(file.id, "overview"), identityID = Self.workID(file.id, "identity")
        let overview = context.overview
        let maskProcessing = ReviewMaskProcessing()
        var subjects: [ReviewSubjectRecord] = []
        var masks: [ReviewSubjectID: CGImage] = [:]
        var segmentIDs: [ReviewWorkID] = []
        if snapshot.models["sam"] != nil, let overview {
            for (index, concept) in overview.concepts.enumerated() {
                progress = "Segmenting \(concept)"
                let id = try addWork("segment:\(index)", stage: .segmentation, parents: [sourceID, overviewID], source: source.metadata.identity, region: concept)
                segmentIDs.append(id)
                let records: [ReviewSubjectRecord]? = try await perform(id, category: .sam) {
                    let candidates = try await backend.segment(image: source.image, file: file, concept: concept)
                    let retained = try await maskProcessing.register(candidates, source: source)
                    var values: [ReviewSubjectRecord] = []
                    for registered in retained {
                        let candidate = registered.retained
                        let maskKey = await retain(candidate.mask, force: true)
                        let subjectID = ReviewSubjectID(rawValue: file.id.rawValue + ":subject:" + String(index) + ":" + candidate.descriptor.id)
                        masks[subjectID] = candidate.mask
                        try values.append(.init(maskContract: SubjectMaskContract.make(mask: candidate.mask, sourceIdentity: source.metadata.identity), registration: registered.registration, id: subjectID, imageID: file.id, concept: concept,
                                                normalizedBounds: candidate.descriptor.normalizedBoundingBox, maskConfidence: candidate.descriptor.score,
                                                aliases: candidate.descriptor.aliases, maskInputReference: maskKey, availability: .available))
                    }
                    return values
                }
                subjects += records ?? []
            }
        } else {
            limitation("SAM unavailable or discovery failed; subject identity and masked detail abstain.")
        }
        // Deduplicate across all discovered concepts through the existing SAM policy.
        var allCandidates: [ObjectInstanceDeduplicator.Candidate] = []
        for subject in subjects {
            if masks[subject.id] == nil, let key = subject.maskInputReference {
                masks[subject.id] = await exactInput(key)
            }
            if let mask = masks[subject.id], let candidate = try? ObjectInstanceDeduplicator.candidate(concept: subject.concept, mask: mask, score: subject.maskConfidence, bounds: subject.normalizedBounds, id: subject.id.rawValue) {
                allCandidates.append(candidate)
            }
        }
        let retainedIDs = try await maskProcessing.retainedIDs(allCandidates)
        subjects = subjects.filter { retainedIDs.contains($0.id.rawValue) }
        subjects = try await maskProcessing.assignPriority(subjects, cues: overview?.primarySubjects ?? [], contextual: overview?.contextualConcepts ?? [], masks: masks, provenance: overviewID.rawValue)
        if !subjects.isEmpty, !subjects.contains(where: { $0.relevance?.role == .primaryCandidate }) {
            limitation("Main-subject priority is ambiguous or unassigned; whole foreground regions share priority in stable ID order.")
        }
        var heads: [ReviewSubjectRecord] = []
        var headOmissions: [ReviewRegionOmission] = []
        if snapshot.models["sam"] != nil, !subjects.isEmpty {
            let headID = try addWork("segment:head", stage: .segmentation, parents: [sourceID, overviewID], source: source.metadata.identity, region: "head")
            segmentIDs.append(headID)
            let values: CombinedReviewHeadCandidates? = try await perform(headID, category: .sam) {
                let candidates = try await backend.segment(image: source.image, file: file, concept: "head")
                var records: [ReviewSubjectRecord] = [], omissions: [ReviewRegionOmission] = []
                for registered in try await maskProcessing.register(candidates, source: source) {
                    let candidate = registered.retained
                    let bounds = candidate.descriptor.normalizedBoundingBox
                    // Association requires a small, contained head candidate; ambiguous overlaps abstain.
                    let parents = subjects.filter { $0.normalizedBounds.contains(bounds) && bounds.width * bounds.height < $0.normalizedBounds.width * $0.normalizedBounds.height * 0.6 }
                    guard parents.count == 1, let parent = parents.first else {
                        omissions.append(.init(regionID: .init(rawValue: ReviewCompatibility.digest(headID.rawValue + ":" + candidate.descriptor.sourceInstanceID)), subjectID: nil,
                                               reason: .ambiguousAnatomy, detail: "Head-query foreground has no unique parent association; no anatomical label is qualified"))
                        continue
                    }
                    try await records.append(.init(maskContract: SubjectMaskContract.make(mask: candidate.mask, sourceIdentity: source.metadata.identity), registration: registered.registration, id: parent.id, imageID: file.id, concept: "Generic candidate region within " + parent.concept,
                                                   normalizedBounds: bounds, maskConfidence: candidate.descriptor.score, aliases: [],
                                                   maskInputReference: retain(candidate.mask, force: true), availability: .available))
                }
                return .init(records: records, omissions: omissions)
            }
            heads = values?.records ?? []; headOmissions = values?.omissions ?? []
        }
        limitation("Anatomy is unverified. SAM head queries and containment alone do not establish a head or eyes; retained candidates are generic regions.")
        for subject in subjects + heads {
            if let warning = subject.registration?.warning {
                limitation(subject.id.rawValue + ": " + warning)
            }
            if subject.registration?.touchesSourceEdge == true {
                limitation(subject.id.rawValue + ": foreground touches the source edge; visibility may be partial.")
            }
        }
        // The identity plan persists deterministic crop decisions independently of later measurements.
        replaceDependencies(identityID, with: [sourceID, overviewID] + segmentIDs)
        let plan: CombinedReviewPlan? = try await perform(identityID) {
            var proposed: [(CGRect, String, ReviewSubjectID?)] = []
            for subject in subjects {
                try proposed.append((source.metadata.sourceSpace.sourceRect(fromNormalized: subject.normalizedBounds), "Registered foreground: \(subject.concept); identity unverified", subject.id))
            }
            for manual in snapshot.userRegions ?? [] where manual.imageID == file.id {
                try proposed.append((source.metadata.sourceSpace.sourceRect(fromNormalized: manual.normalizedRect), manual.purpose, nil))
            }
            for head in heads {
                try proposed.append((source.metadata.sourceSpace.sourceRect(fromNormalized: head.normalizedBounds), head.concept + "; anatomy unverified", head.id))
            }
            if proposed.isEmpty {
                proposed.append((source.metadata.sourceSpace.bounds, "Whole-frame fallback; no verified subject", nil))
            }
            let geometry = ReviewEncoderGeometry(width: qwen.encoderWidth, height: qwen.encoderHeight, strategy: .stretch)
            var records: [ReviewRegionRecord] = [], omitted: [ReviewRegionID] = [], omissions: [ReviewRegionOmission] = headOmissions
            for proposal in proposed {
                let region: ReviewRegion
                do { region = try source.region(rect: proposal.0, purpose: proposal.1, encoder: geometry) } catch {
                    let id = ReviewRegionID(rawValue: ReviewCompatibility.digest(source.metadata.identity + proposal.1 + String(describing: proposal.0)))
                    omitted.append(id); omissions.append(.init(regionID: id, subjectID: proposal.2, reason: .geometryFailure, detail: "Invalid registered source rectangle; region omitted"))
                    continue
                }
                let id = ReviewRegionID(rawValue: region.id)
                if records.count >= cropAllowance {
                    omitted.append(id)
                    let contextual = subjects.first { $0.id == proposal.2 }?.relevance?.role == .contextual
                    omissions.append(.init(regionID: id, subjectID: proposal.2, reason: contextual ? .contextualPriority : .budgetDepthPolicy,
                                           detail: contextual ? "Contextual region follows main-subject coverage within immutable crop caps" : "Depth/allocation cap; generic anatomy follows whole-subject coverage"))
                    continue
                }
                let crop: CGImage
                do { crop = try source.crop(region) } catch {
                    omitted.append(id); omissions.append(.init(regionID: id, subjectID: proposal.2, reason: .unavailableInput, detail: "Registered crop input unavailable"))
                    continue
                }
                let input = await retain(crop)
                var support: ReviewCropSupport?
                if let subjectID = proposal.2, let mask = masks[subjectID] {
                    support = try await maskProcessing.cropSupport(
                        subjectID: subjectID, mask: mask, width: source.image.width, height: source.image.height,
                        cropRect: region.sourceRect, encoderRect: region.encoder.retainedSourceRect,
                        sourceEdgeContact: subjects.first { $0.id == subjectID }?.registration?.touchesSourceEdge ?? false,
                    )
                }
                records.append(.init(support: support, id: id, imageID: file.id, subjectID: proposal.2, sourceIdentity: source.metadata.identity, purpose: proposal.1,
                                     requestedRect: region.requestedRect, paddedRect: region.paddedRect, sourceRect: region.sourceRect,
                                     retainedSourceRect: region.encoder.retainedSourceRect, encoderSize: region.encoder.encoderSize,
                                     scaleX: Double(region.encoder.scaleX), scaleY: Double(region.encoder.scaleY), edgeClipped: region.edgeClipped,
                                     intendedRegionRetained: region.intendedRegionRetained, fidelity: source.metadata.fidelity.rawValue,
                                     policy: source.metadata.policy.rawValue, inputReference: input))
            }
            return .init(omissions: omissions, subjects: subjects, regions: records, uninspected: omitted)
        }
        guard let plan else { throw ReviewRunError.invalidEvidence }
        result?.subjects = plan.subjects; result?.regions = plan.regions; result?.omissions = plan.omissions ?? []
        if !plan.uninspected.isEmpty {
            limitation("\(plan.uninspected.count) candidate regions were outside the chosen crop budget.")
        }
        if plan.subjects.isEmpty {
            limitation("No verified subject mask survived segmentation; whole-frame fallback does not establish subject sharpness.")
        }
        return (plan, masks, segmentIDs)
    }

    func inspect(_ backend: any CombinedReviewBackendServing, context: CombinedReviewContext, plan: CombinedReviewPlan,
                 masks initialMasks: [ReviewSubjectID: CGImage], segmentIDs: [ReviewWorkID]) async throws -> [ReviewWorkID] {
        let snapshot = context.snapshot, file = context.file, source = context.source, qwen = context.qwen
        let sourceID = Self.workID(file.id, "source"), overviewID = Self.workID(file.id, "overview"), identityID = Self.workID(file.id, "identity")
        guard let preference = ReviewSourcePreference(rawValue: snapshot.sourcePreference) else { throw ReviewRunError.invalidSnapshot }
        var masks = initialMasks
        var technical: ReviewImageSource?
        if !plan.subjects.isEmpty {
            do {
                technical = try await sourceLoader.load(.init(url: file.url, preference: preference, policy: .technical)); if let technical {
                    _ = try source.mapSourceRect(source.metadata.sourceSpace.bounds, to: technical)
                }
            } catch is CancellationError { throw CancellationError() } catch { technical = nil; limitation("Technical render alignment unavailable: \(error)") }
        }
        var terminalIDs: [ReviewWorkID] = [overviewID, identityID] + segmentIDs
        for subject in plan.subjects {
            let id = try addWork("measure:\(subject.id.rawValue)", stage: .measurement, parents: [identityID], source: technical?.metadata.identity ?? "unavailable", region: subject.id.rawValue)
            terminalIDs.append(id)
            let measurement: ReviewMeasurement? = try await perform(id) {
                if masks[subject.id] == nil, let key = subject.maskInputReference {
                    masks[subject.id] = await exactInput(key)
                }
                guard let technical, let mask = masks[subject.id],
                      mask.width == technical.image.width, mask.height == technical.image.height,
                      let contract = subject.maskContract else { throw SubjectMaskDecodingError.unsafeRegistration }
                try contract.validate(mask: mask, sourceIdentity: source.metadata.identity)
                guard let measured = try await scorer.score(image: technical.image, subjectMask: mask, normalizedAFPoint: file.normalizedAFPoint) else { throw ReviewValidationIssue(.maskDecoding, "measurement.availableScore", field: "subjectMask") }
                var values = ["subjectDetail": Double(measured.finalScore), "fineDetail": Double(measured.fineDetailScore), "maskCoverage": Double(measured.maskCoverage)]
                guard measured.scorerVersion == SubjectMaskFocusScorer.semanticsVersion else { throw ReviewRunError.incompatible }
                if let count = measured.foregroundCount {
                    values["foregroundPixelCount"] = Double(count)
                }
                if let count = measured.totalPixelCount {
                    values["totalPixelCount"] = Double(count)
                }
                if let count = measured.usableForegroundCount {
                    values["usableForegroundPixelCount"] = Double(count)
                }
                if let count = measured.interiorPixelCount {
                    values["interiorPixelCount"] = Double(count)
                }
                if let border = measured.borderPixels {
                    values["excludedBorderPixels"] = Double(border)
                }
                if let foreground = measured.foregroundCount, let total = measured.totalPixelCount, total > 0 {
                    values["foregroundCoverage"] = Double(foreground) / Double(total)
                }
                if let usable = measured.usableForegroundCount, let interior = measured.interiorPixelCount, interior > 0 {
                    values["usableInteriorCoverage"] = Double(usable) / Double(interior)
                }
                if measured.suspectNearFullOccupancy == true {
                    limitation("Subject mask covers at least 95% of the raster; subject specificity is uncertain. This is not calibrated focus evidence.")
                }
                if let broad = measured.broadSubjectScore {
                    values["broadDetail"] = Double(broad)
                }
                if let local = measured.localDetailScore {
                    values["localDetail"] = Double(local)
                }
                if let inside = measured.autofocusInsideMask {
                    values["autofocusInsideMask"] = inside ? 1 : 0
                }
                guard values.values.allSatisfy(\.isFinite) else { throw ReviewValidationIssue(.maskDecoding, "measurement.finiteValues", field: "values") }
                return try .init(scorerVersion: measured.scorerVersion, maskContract: contract, foregroundBounds: measured.foregroundBounds, id: .init(rawValue: id.rawValue), subjectID: subject.id, values: values, availability: .available,
                                 reason: "Render-dependent detail metric; no calibrated sharp/blur threshold or eye claim", provenance: provenance(id, source: technical))
            }
            if let measurement {
                guard measurement.hasCurrentMaskSemantics else { throw ReviewRunError.incompatible }
                result?.measurements.append(measurement)
            }
        }
        if let clipModel = snapshot.models["clip"] {
            let id = try addWork("clip:overview", stage: .clip, parents: [sourceID], source: source.metadata.identity, region: "overview")
            terminalIDs.append(id)
            let value: CombinedReviewCLIPResult? = try await perform(id, category: .clip) { try await backend.clip(image: source.overview, criteria: snapshot.criteria, model: clipModel) }
            result?.clip["overview"] = value
        } else {
            limitation("CLIP unavailable or its input geometry is unverified; relevance/matching evidence disabled.")
        }
        for region in plan.regions {
            try Task.checkCancellation()
            guard region.sourceIdentity == source.metadata.identity, let crop = source.image.cropping(to: region.sourceRect) else { throw ReviewRunError.incompatible }
            progress = "Inspecting \(region.purpose)"
            let id = try addWork("crop:\(region.id.rawValue)", stage: .cropObservation, parents: [sourceID, identityID], source: source.metadata.identity, region: region.id.rawValue)
            terminalIDs.append(id)
            let inspection: CombinedReviewInspection? = try await perform(id, category: .crop) {
                let prompt = """
                Inspect this crop for four separate criteria. Intended generic target: \(plan.subjects.first(where: { $0.id == region.subjectID })?.concept ?? "unspecified"). Region ID: \(region.id.rawValue). Purpose: \(region.purpose).
                Return JSON only: {"regionID":"\(region.id.rawValue)","criteria":{"composition":null,"exposure":null,"visibility":null,"detail":null},"uncertainty":"","targetIdentified":false}.
                Include all keys. Each criterion is a visible observation STRING or null when unsupported. Replace example nulls with evidence when available; the example is not a conclusion. Determine targetIdentified from visible generic-target presence before writing criteria. Unknown species or individual identity does not make a visible target absent.
                Each non-null string: one criterion-specific sentence, aim for 80 characters, hard maximum 120. Never use an empty string or supported/text object. Never repeat a sentence across criteria.
                composition: placement, framing or obstructions. exposure: illumination or tonal contrast; a light-colored sky alone is not exposure evidence.
                visibility: visible extent or occlusion of the intended generic target; species/identity uncertainty is not visibility.
                detail: resolved surface texture of that target only, never background texture or anatomical detail. If unresolved, use detail=null; never write a sentence saying no texture is resolved.
                targetIdentified means the intended generic target is visibly present and distinguishable. It does not mean species identification, individual identity, verified anatomy or fine-detail quality. Never assume presence from Purpose alone. Purpose gives no intended target: false only when the explicit intended generic target is also unspecified.
                intended generic target absent/indistinguishable: targetIdentified=false and detail=null.
                Text must stay within framing, illumination, occlusion and surface texture. Do not describe body parts, species, focus, sharpness or RAW recovery. Anatomical limitations belong in uncertainty only (max 160 characters).
                """
                return try await validatedResponse(instruction: CombinedReviewResponse.admitted(prompt, model: qwen, outputTokens: snapshot.responseTokens), image: crop, model: qwen, tokens: snapshot.responseTokens, backend: backend) { try CombinedReviewResponse.inspection($0, regionID: region.id.rawValue, requireCriteria: true, preserveValidCriteria: true) }
            }
            if let inspection {
                for note in inspection.validationNotes ?? [] {
                    limitation("Crop " + region.id.rawValue + ": " + note)
                }
                if inspection.targetIdentified != true || inspection.insufficientEvidence {
                    limitation("Crop \(region.id.rawValue) cannot establish target-specific detail; target support is absent or unknown.")
                }
                let origin = try provenance(id, source: source, input: region.inputReference)
                result?.observations.append(.init(targetIdentified: inspection.targetIdentified, criteria: inspection.criteria, id: .init(rawValue: id.rawValue), regionID: region.id,
                                                  text: inspection.observations, uncertainty: inspection.uncertainty,
                                                  availability: inspection.insufficientEvidence ? .unknown : .available,
                                                  provenance: origin))
            }
            if let clipModel = snapshot.models["clip"] {
                let clipID = try addWork("clip:\(region.id.rawValue)", stage: .clip, parents: [identityID], source: source.metadata.identity, region: region.id.rawValue)
                terminalIDs.append(clipID)
                let value: CombinedReviewCLIPResult? = try await perform(clipID, category: .clip) { try await backend.clip(image: crop, criteria: snapshot.criteria, model: clipModel) }
                result?.clip[region.id.rawValue] = value
            }
        }
        return terminalIDs
    }

    func finish(_ backend: any CombinedReviewBackendServing, context: CombinedReviewContext, plan: CombinedReviewPlan, terminalIDs initialIDs: [ReviewWorkID]) async throws {
        let file = context.file, source = context.source, qwen = context.qwen
        var terminalIDs = initialIDs
        for (id, reason) in result?.failures ?? [:] {
            limitation("Stage \(id) unavailable: \(reason)")
        }
        if !(result?.measurements.isEmpty ?? true), result?.observations.contains(where: { $0.regionID != nil && $0.availability == .available }) == true {
            let id = try addWork("reconcile", stage: .reconciliation, parents: terminalIDs, source: source.metadata.identity)
            terminalIDs.append(id)
            progress = "Reconciling terminal evidence"
            let reconciled: ReviewImageReport? = try await perform(id, category: .reconciliation) {
                try await synthesize(backend, source: source, qwen: qwen, plan: plan, reconciliation: true)
            }
            if let reconciled {
                // Keep references on each reconciled claim; it is not independent corroboration.
                for claim in reconciled.claims {
                    let origin = try provenance(id, source: source, input: result?.overviewInputReference)
                    result?.observations.append(.init(id: .init(rawValue: id.rawValue + ":" + ReviewCompatibility.digest(claim.text)), regionID: nil,
                                                      text: claim.text + " [Reconciliation of: " + claim.evidence.map(\.id).joined(separator: ", ") + "]",
                                                      uncertainty: claim.uncertainty + "; same Qwen model, not independent confirmation", availability: .available,
                                                      provenance: origin))
                }
            }
        }
        for (id, reason) in result?.failures ?? [:] {
            limitation("Stage \(id) unavailable: \(reason)")
        }
        let reportID = Self.workID(file.id, "report")
        replaceDependencies(reportID, with: terminalIDs)
        progress = "Synthesizing grounded report"
        let report: ReviewImageReport? = try await perform(reportID, category: .report) {
            try await synthesize(backend, source: source, qwen: qwen, plan: plan)
        }
        if let report {
            result?.report = report
        } else {
            limitation("Report synthesis failed validation; completed observations remain available. No generated claim is accepted.")
            let summary = result.map(ReviewEvidenceOnlySummary.make)
            result?.evidenceOnlySummary = summary
            if let summary {
                if manifest?.evidenceOnlySummaries == nil {
                    manifest?.evidenceOnlySummaries = [:]
                }
                manifest?.evidenceOnlySummaries?[file.id.rawValue] = summary
            }
            let inspected = result?.observations.filter { $0.regionID != nil && $0.availability == .available }.compactMap(\.regionID) ?? []
            let missing = plan.regions.map(\.id).filter { !inspected.contains($0) } + plan.uninspected
            let fallback = ReviewImageReport(id: .init(rawValue: file.id.rawValue + ":report"), imageID: file.id, claims: [], limitations: result?.limitations ?? [], incomplete: true,
                                             inspectedRegions: inspected, uninspectedRegions: missing)
            result?.report = fallback
            try await store.saveManifest(currentManifest())
        }
        try await store.saveManifest(currentManifest())
        progress = result?.report?.incomplete == true ? "Complete with limitations" : "Complete"
    }

    func synthesize(_ backend: any CombinedReviewBackendServing, source: ReviewImageSource, qwen: ReviewModelSnapshot, plan: CombinedReviewPlan, reconciliation: Bool = false) async throws -> ReviewImageReport {
        guard let value = result, let snapshot = manifest?.snapshot else { throw ReviewRunError.invalidSnapshot }
        let grounding = ReviewSynthesisGrounding(result: value)
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
        var rows: [(reference: ReviewEvidenceReference, text: String)] = []
        var aliases: [ReviewEvidenceReference: ReviewEvidenceReference] = [:]
        // Reconciliation is inspectable reasoning, not another independent evidence source.
        // Feeding its prose and nested provenance IDs back in bloats context and confuses the schema.
        for observation in value.observations where observation.availability == .available && observation.provenance.workID != Self.workID(value.file.id, "reconcile") {
            let stored = ReviewEvidenceReference(kind: .observation, id: observation.id.rawValue)
            let support = try grounding.support(stored)
            let subjectLabel = support.subjectID.flatMap { id in value.subjects.firstIndex(where: { $0.id == id }).map { "s\($0 + 1)" } } ?? "none"
            let regionLabel = support.regionID.flatMap { id in value.regions.firstIndex(where: { $0.id == id }).map { "r\($0 + 1)" } } ?? "whole-frame"
            let eligibleTypes = observation.criteria == nil ? "composition,visibility" : support.claimTypes
            let scope = " subject=\(subjectLabel) region=\(regionLabel) targetSupported=\(support.crop) subjectDetailSupported=\(support.subjectDetailSupported) types=\(eligibleTypes)"
            let ref = ReviewEvidenceReference(kind: .observation, id: "o\(aliases.count + 1)")
            let evidenceText: String = if let criteria = observation.criteria {
                ReviewCriterionObservations.types.compactMap { type in
                    guard let entry = criteria[type], entry.supported else { return nil }
                    return type + ": " + entry.text
                }.joined(separator: " | ")
            } else {
                observation.text
            }
            let row = try String(decoding: encoder.encode(ref), as: UTF8.self) + scope + " " + evidenceText
            rows.append((ref, row)); aliases[ref] = .init(kind: .observation, id: observation.id.rawValue)
        }
        // Metrics are displayed deterministically. They cannot independently support generated prose,
        // and must never displace the primary subject or overview in the model context.
        guard !rows.isEmpty else { throw ReviewValidationIssue(.grounding, "synthesis.availableEvidence") }
        func priority(_ row: (reference: ReviewEvidenceReference, text: String)) -> Int {
            guard let stored = aliases[row.reference], let support = try? grounding.support(stored) else { return 4 }
            if let subject = support.subjectID {
                let rank = value.subjects.first(where: { $0.id == subject })?.relevance?.rank ?? 2
                return rank < 2 ? 0 : rank == 2 ? 1 : 3
            }
            return support.regionID == nil ? 2 : 4
        }
        let orderedRows = rows.enumerated().sorted { left, right in
            let l = priority(left.element), r = priority(right.element)
            return l == r ? left.offset < right.offset : l < r
        }.map(\.element)
        let schema = """
        \(reconciliation ? "Reconcile independent observations; abstain when unsupported." : "Synthesize the per-image report.")
        Goal: \(snapshot.criteria)
        Return JSON only: {"composition":null,"exposure":null,"visibility":null,"detail":null}.
        Include all four keys. Each value is ONE eligible row ID string or null to abstain.
        Choose the most useful supported row for each category. Never write observation prose or evidence objects.
        Allowed row IDs for each category are listed below. Use only those IDs; never borrow another category.
        Select detail only when an eligible detail row exists. Null means no supported selection.
        Code copies the selected criterion text and evidence ID without rewriting. No invented claims or contradictions.
        Source: \(source.metadata.fidelity.rawValue), \(source.image.width)x\(source.image.height), SDR sRGB. Failed stages: \(value.failures.count).
        """
        // Reserve 320 bytes for allowed row IDs and 480 for validation feedback.
        // Repair never drops schema or evidence rows to fit the model context.
        var selected: [String] = []
        var included: Set<ReviewEvidenceReference> = []
        for row in orderedRows {
            if (try? CombinedReviewResponse.admitted(schema + "\n" + (selected + [row.text]).joined(separator: "\n") + String(repeating: " ", count: 800), model: qwen, outputTokens: snapshot.responseTokens)) != nil {
                selected.append(row.text)
                included.insert(row.reference)
            } else {
                limitation("Some optional evidence was omitted to stay within the verified model context.")
            }
        }
        let inspected = value.observations.filter { $0.regionID != nil && $0.availability == .available }.compactMap(\.regionID)
        let missing = plan.regions.map(\.id).filter { !inspected.contains($0) } + plan.uninspected
        if included.isEmpty {
            throw ReviewValidationIssue(.grounding, "synthesis.includedEvidence")
        }
        // Only already-grounded criterion/row pairs are selectable.
        var candidates: [String: [String: ReviewClaim]] = [:]
        for row in orderedRows where included.contains(row.reference) {
            guard let stored = aliases[row.reference] else { continue }
            let support = try grounding.support(stored)
            for type in ReviewCriterionObservations.types {
                let text: String
                if let criteria = support.criteria {
                    guard let entry = criteria[type], entry.supported,
                          type != "detail" || support.subjectDetailSupported else { continue }
                    text = entry.text
                } else {
                    guard ["composition", "visibility"].contains(type) else { continue }
                    text = support.observationText
                }
                let claim = ReviewClaim(text: text, type: type, evidence: [stored], uncertainty: "", contradictions: [])
                // Same ownership and focus checks as generated claims; unavailable pairs stay out.
                guard (try? CombinedReviewResponse.validateSelectedClaim(claim)) != nil else { continue }
                if let qualified = try? grounding.validate(claim) {
                    candidates[type, default: [:]][row.reference.id] = qualified
                }
            }
        }
        let allowed = ReviewCriterionObservations.types.map { type in
            type + ": " + orderedRows.filter { candidates[type]?[$0.reference.id] != nil }.map { $0.reference.id }.joined(separator: ",")
        }.joined(separator: "\n")
        let preferredRows = Dictionary(uniqueKeysWithValues: ReviewCriterionObservations.types.compactMap { type -> (String, String)? in
            guard let row = orderedRows.first(where: { included.contains($0.reference) && candidates[type]?[$0.reference.id] != nil }) else { return nil }
            return (type, row.reference.id)
        })
        let prompt = try CombinedReviewResponse.admitted(schema + "\n" + selected.joined(separator: "\n") + "\nAllowed row IDs by category:\n" + allowed, model: qwen, outputTokens: snapshot.responseTokens)
        return try await validatedResponse(instruction: prompt, image: source.overview, model: qwen, tokens: snapshot.responseTokens, backend: backend) { text in
            let generated = try CombinedReviewResponse.selectedReport(text, imageID: value.file.id, candidates: candidates,
                                                                      limitations: result?.limitations ?? [], regions: inspected, uninspected: missing,
                                                                      incomplete: !missing.isEmpty || !value.failures.isEmpty || value.measurements.isEmpty || value.clip.isEmpty || value.limitations.contains(where: { $0.reason.contains("; criterion abstained") }), preferredRows: preferredRows)
            let missingCriteria = ["composition", "exposure", "visibility", "detail"].filter { criterion in
                !generated.claims.contains { $0.type == criterion }
            }
            let coverage = missingCriteria.map { ReviewLimitation(id: .init(rawValue: value.file.id.rawValue + ":coverage:" + $0), reason: "No supported " + $0 + " claim; abstained because admitted observations did not establish this criterion.", relatedEvidence: []) }
            return ReviewImageReport(id: generated.id, imageID: generated.imageID, claims: generated.claims, limitations: generated.limitations + coverage,
                                     incomplete: generated.incomplete || !missingCriteria.isEmpty, inspectedRegions: generated.inspectedRegions, uninspectedRegions: generated.uninspectedRegions)
        }
    }
}

extension CombinedReviewFeature {
    /// Draw directly into a fixed-size bitmap: no screen scale, cropping, or stretching.
    static func comparisonBoard(_ images: [(ReviewImageID, CGImage)]) throws -> (CGImage, [ReviewBoardCell]) {
        guard (2 ... 8).contains(images.count), Set(images.map(\.0)).count == images.count,
              let context = CGContext(data: nil, width: 2048, height: 2048, bitsPerComponent: 8, bytesPerRow: 8192,
                                      space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { throw ReviewRunError.invalidEvidence }
        context.setFillColor(CGColor(gray: 0.18, alpha: 1)); context.fill(CGRect(x: 0, y: 0, width: 2048, height: 2048))
        let columns = images.count <= 4 ? 2 : 4, rows = (images.count + columns - 1) / columns
        let width = CGFloat(2048) / CGFloat(columns), height = CGFloat(2048) / CGFloat(rows)
        var cells: [ReviewBoardCell] = []
        for (index, entry) in images.sorted(by: { $0.0.rawValue < $1.0.rawValue }).enumerated() {
            let left = CGFloat(index % columns) * width, top = CGFloat(index / columns) * height
            let scale = min(width / CGFloat(entry.1.width), (height - 48) / CGFloat(entry.1.height))
            let rect = CGRect(x: left + (width - CGFloat(entry.1.width) * scale) / 2,
                              y: top + 48 + (height - 48 - CGFloat(entry.1.height) * scale) / 2,
                              width: CGFloat(entry.1.width) * scale, height: CGFloat(entry.1.height) * scale)
            context.draw(entry.1, in: CGRect(x: rect.minX, y: 2048 - rect.maxY, width: rect.width, height: rect.height))
            NSGraphicsContext.saveGraphicsState()
            NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: false)
            (entry.0.rawValue as NSString).draw(in: CGRect(x: left + 8, y: 2048 - top - 40, width: width - 16, height: 32),
                                                withAttributes: [.font: NSFont.monospacedSystemFont(ofSize: 16, weight: .medium), .foregroundColor: NSColor.white])
            NSGraphicsContext.restoreGraphicsState()
            cells.append(.init(imageID: entry.0, rect: rect, sourceWidth: entry.1.width, sourceHeight: entry.1.height))
        }
        guard let board = context.makeImage() else { throw ReviewRunError.invalidEvidence }
        return (board, cells)
    }
}
