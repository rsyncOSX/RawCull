import AppKit
import CoreGraphics
import Foundation

nonisolated struct CombinedReviewPlan: Codable, Sendable {
    let subjects: [ReviewSubjectRecord]
    let regions: [ReviewRegionRecord]
    let uninspected: [ReviewRegionID]
}

nonisolated struct CombinedReviewContext: Sendable {
    let snapshot: ReviewRunSnapshot
    let file: ReviewFileSnapshot
    let source: ReviewImageSource
    let qwen: ReviewModelSnapshot
    let overview: CombinedReviewOverview?
}

nonisolated struct CombinedReviewPair: Sendable {
    let left: CombinedReviewResult
    let right: CombinedReviewResult
    let leftRegion: ReviewRegionRecord
    let rightRegion: ReviewRegionRecord
}

extension CombinedReviewFeature {
    func perform<Value: Codable & Sendable>(_ id: ReviewWorkID, category: ReviewAttemptCategory? = nil,
                                            operation: () async throws -> Value) async throws -> Value?
    {
        try Task.checkCancellation()
        guard let item = manifest?.work.first(where: { $0.id == id }) else { throw ReviewRunError.invalidDependency }
        if item.state == .completed, let key = item.artifactKey {
            let artifact = try await store.loadArtifact(key: key, expected: item.compatibility)
            return try JSONDecoder().decode(Value.self, from: artifact.payload)
        }
        if item.state.terminal {
            result?.failures[id.rawValue] = item.reason; return nil
        }
        do {
            try manifest?.begin(id, category: category)
            try await store.saveManifest(currentManifest())
            let value = try await operation()
            try Task.checkCancellation()
            let payload = try JSONEncoder().encode(value)
            let key = store.artifactKey(id, compatibility: item.compatibility)
            var completed = try currentManifest()
            try completed.finish(id, state: .completed, artifactKey: key)
            try await store.commit(.init(workID: id, compatibility: item.compatibility, payload: payload, created: Date()), manifest: completed)
            manifest = completed
            return value
        } catch is CancellationError { throw CancellationError() } catch {
            try Task.checkCancellation()
            if manifest?.work.first(where: { $0.id == id })?.state == .running {
                try manifest?.finish(id, state: .failed, reason: String(describing: error))
            } else {
                try manifest?.skip(id, reason: String(describing: error))
            }
            result?.failures[id.rawValue] = String(describing: error)
            try await store.saveManifest(currentManifest())
            return nil
        }
    }

    func addWork(_ name: String, stage: ReviewStage, parents: [ReviewWorkID], source: String, region: String = "") throws -> ReviewWorkID {
        let run = try currentManifest()
        guard let file = activeFile else { throw ReviewRunError.invalidSnapshot }
        let id = Self.workID(file.id, name)
        if let existing = run.work.first(where: { $0.id == id }) {
            let expected = try ReviewCompatibility.make(snapshot: run.snapshot, image: file, stage: stage,
                                                        sourceRender: source, region: region)
            guard existing.stage == stage, existing.compatibility == expected else { throw ReviewRunError.incompatible }
            return id
        }
        try manifest?.work.append(.init(id: id, imageID: file.id, stage: stage,
                                        dependencies: parents.map { .init(id: $0, allowsUnavailable: true) },
                                        compatibility: ReviewCompatibility.make(snapshot: run.snapshot, image: file, stage: stage, sourceRender: source, region: region)))
        return id
    }

    func retain(_ image: CGImage, force: Bool = false) async -> String? {
        guard force || manifest?.snapshot.retentionPolicy == .exactInputs else { return nil }
        return try? await store.retainInput(Self.encodeInput(image))
    }

    @concurrent static func encodeInput(_ image: CGImage) async throws -> Data {
        try Task.checkCancellation()
        return try ReviewImageSource.pngData(for: image)
    }

    func limitation(_ reason: String) {
        guard let file = result?.file, result?.limitations.contains(where: { $0.reason == reason }) != true else { return }
        result?.limitations.append(.init(id: .init(rawValue: file.id.rawValue + ":limit:" + ReviewCompatibility.digest(reason)), reason: reason, relatedEvidence: []))
    }

    func provenance(_ id: ReviewWorkID, source: ReviewImageSource, input: String? = nil) throws -> ReviewEvidenceProvenance {
        guard let item = manifest?.work.first(where: { $0.id == id }), let file = result?.file else { throw ReviewRunError.invalidEvidence }
        return .init(workID: id, imageID: file.id, sourceIdentity: source.metadata.identity,
                     renderPolicy: source.metadata.policy.rawValue, compatibility: item.compatibility,
                     modelIdentity: item.compatibility.fields["model"], inputReference: input)
    }

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
                if snapshot.files.count == 1 {
                    throw error
                }
                limitation("Image review unavailable: \(error)")
                result?.failures[Self.workID(file.id, "source").rawValue] = String(describing: error)
                for item in manifest?.work ?? [] where item.imageID == file.id && item.stage != .comparison {
                    if item.state == .pending {
                        try manifest?.skip(item.id, reason: "Image preparation failed: \(error)")
                    }
                    if item.state == .running {
                        try manifest?.finish(item.id, state: .failed, reason: "Image preparation failed: \(error)")
                    }
                }
                try await store.saveManifest(currentManifest())
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
        guard let file = activeFile else { throw ReviewRunError.invalidSnapshot }
        guard let preference = ReviewSourcePreference(rawValue: snapshot.sourcePreference), let qwen = snapshot.models["qwen"] else { throw ReviewRunError.invalidSnapshot }
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
        limitation("AF mapping is unavailable for this review; focus measurements use subject masks without an AF point.")
        limitation("Exposure and crop suggestions are hypotheses; no rendered edit has been evaluated. RAW recovery is untested.")
        let overviewInput = await retain(source.overview)
        result?.overviewInputReference = overviewInput
        progress = "Independent overview and subject discovery"
        let overview: CombinedReviewOverview? = try await perform(overviewID, category: .overview) {
            let prompt = try CombinedReviewResponse.admitted(CombinedReviewResponse.overviewInstruction, model: qwen, outputTokens: snapshot.responseTokens)
            return try await CombinedReviewResponse.overview(backend.respond(instruction: prompt, image: source.overview, tokens: snapshot.responseTokens))
        }
        result?.overview = overview
        if let overview {
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
                    let retained = ObjectInstanceDeduplicator.retain(candidates, maximumCount: 8)
                    var values: [ReviewSubjectRecord] = []
                    for candidate in retained {
                        let maskKey = await retain(candidate.mask, force: true)
                        let subjectID = ReviewSubjectID(rawValue: file.id.rawValue + ":subject:" + String(index) + ":" + candidate.descriptor.id)
                        masks[subjectID] = candidate.mask
                        values.append(.init(id: subjectID, imageID: file.id, concept: concept,
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
        let retainedIDs = Set(ObjectInstanceDeduplicator.retain(allCandidates, maximumCount: 8).map(\.descriptor.sourceInstanceID))
        subjects = subjects.filter { retainedIDs.contains($0.id.rawValue) }
        var heads: [ReviewSubjectRecord] = []
        if snapshot.models["sam"] != nil, !subjects.isEmpty {
            let headID = try addWork("segment:head", stage: .segmentation, parents: [sourceID, overviewID], source: source.metadata.identity, region: "head")
            segmentIDs.append(headID)
            let values: [ReviewSubjectRecord]? = try await perform(headID, category: .sam) {
                let candidates = try await backend.segment(image: source.image, file: file, concept: "head")
                var records: [ReviewSubjectRecord] = []
                for candidate in ObjectInstanceDeduplicator.retain(candidates, maximumCount: 8) {
                    let bounds = candidate.descriptor.normalizedBoundingBox
                    // Association requires a small, contained head candidate; ambiguous overlaps abstain.
                    let parents = subjects.filter { $0.normalizedBounds.contains(bounds) && bounds.width * bounds.height < $0.normalizedBounds.width * $0.normalizedBounds.height * 0.6 }
                    guard parents.count == 1, let parent = parents.first else { continue }
                    await records.append(.init(id: parent.id, imageID: file.id, concept: "Head candidate within " + parent.concept,
                                               normalizedBounds: bounds, maskConfidence: candidate.descriptor.score, aliases: [],
                                               maskInputReference: retain(candidate.mask, force: true), availability: .available))
                }
                return records
            }
            heads = values ?? []
        }
        if heads.isEmpty {
            limitation("No unambiguous contained head candidate; whole-subject regions are the detail fallback.")
        }
        // The identity plan persists deterministic crop decisions independently of later measurements.
        replaceDependencies(identityID, with: [sourceID, overviewID] + segmentIDs)
        let plan: CombinedReviewPlan? = try await perform(identityID) {
            var proposed: [(CGRect, String, ReviewSubjectID?)] = []
            for manual in snapshot.userRegions ?? [] where manual.imageID == file.id {
                try proposed.append((source.metadata.sourceSpace.sourceRect(fromNormalized: manual.normalizedRect), manual.purpose, nil))
            }
            for head in heads {
                try proposed.append((source.metadata.sourceSpace.sourceRect(fromNormalized: head.normalizedBounds), head.concept + "; eyes unverified", head.id))
            }
            for subject in subjects {
                try proposed.append((source.metadata.sourceSpace.sourceRect(fromNormalized: subject.normalizedBounds), "Subject: \(subject.concept)", subject.id))
            }
            if proposed.isEmpty {
                proposed.append((source.metadata.sourceSpace.bounds, "Whole-frame fallback; no verified subject", nil))
            }
            let geometry = ReviewEncoderGeometry(width: qwen.encoderWidth, height: qwen.encoderHeight, strategy: .stretch)
            var records: [ReviewRegionRecord] = [], omitted: [ReviewRegionID] = []
            for (index, proposal) in proposed.enumerated() {
                let region = try source.region(rect: proposal.0, purpose: proposal.1, encoder: geometry)
                let id = ReviewRegionID(rawValue: region.id)
                if index >= cropAllowance {
                    omitted.append(id); continue
                }
                let input = try await retain(source.crop(region))
                records.append(.init(id: id, imageID: file.id, subjectID: proposal.2, sourceIdentity: source.metadata.identity, purpose: proposal.1,
                                     requestedRect: region.requestedRect, paddedRect: region.paddedRect, sourceRect: region.sourceRect,
                                     retainedSourceRect: region.encoder.retainedSourceRect, encoderSize: region.encoder.encoderSize,
                                     scaleX: Double(region.encoder.scaleX), scaleY: Double(region.encoder.scaleY), edgeClipped: region.edgeClipped,
                                     intendedRegionRetained: region.intendedRegionRetained, fidelity: source.metadata.fidelity.rawValue,
                                     policy: source.metadata.policy.rawValue, inputReference: input))
            }
            return .init(subjects: subjects, regions: records, uninspected: omitted)
        }
        guard let plan else { throw ReviewRunError.invalidEvidence }
        result?.subjects = plan.subjects; result?.regions = plan.regions
        if !plan.uninspected.isEmpty {
            limitation("\(plan.uninspected.count) candidate regions were outside the chosen crop budget.")
        }
        if plan.subjects.isEmpty {
            limitation("No verified subject mask survived segmentation; whole-frame fallback does not establish subject sharpness.")
        }
        return (plan, masks, segmentIDs)
    }

    func inspect(_ backend: any CombinedReviewBackendServing, context: CombinedReviewContext, plan: CombinedReviewPlan,
                 masks initialMasks: [ReviewSubjectID: CGImage], segmentIDs: [ReviewWorkID]) async throws -> [ReviewWorkID]
    {
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
                      mask.width == technical.image.width, mask.height == technical.image.height else { throw ReviewRunError.invalidEvidence }
                guard let measured = try await scorer.score(image: technical.image, subjectMask: mask, normalizedAFPoint: nil) else { throw ReviewRunError.invalidEvidence }
                var values = ["subjectDetail": Double(measured.finalScore), "fineDetail": Double(measured.fineDetailScore), "maskCoverage": Double(measured.maskCoverage)]
                if let broad = measured.broadSubjectScore {
                    values["broadDetail"] = Double(broad)
                }
                if let local = measured.localDetailScore {
                    values["localDetail"] = Double(local)
                }
                guard values.values.allSatisfy(\.isFinite) else { throw ReviewRunError.invalidEvidence }
                return try .init(id: .init(rawValue: id.rawValue), subjectID: subject.id, values: values, availability: .available,
                                 reason: "Render-dependent detail metric; no calibrated sharp/blur threshold or eye claim", provenance: provenance(id, source: technical))
            }
            if let measurement {
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
                Inspect only surface texture, light/dark areas and framing in this unannotated crop.
                User criteria: \(snapshot.criteria).
                Region ID: \(region.id.rawValue). Purpose: \(region.purpose).
                Return JSON only {"regionID":"\(region.id.rawValue)","observations":"visible detail, at most 500 characters","uncertainty":"limits, at most 200 characters","insufficientEvidence":false}.
                Write one short sentence about texture and illumination in observations. Ignore anatomy, body parts, gaze and species.
                Put any anatomical limitations in uncertainty only. Observations must not discuss sharpness of individual body parts.
                If these restrictions leave no supported observation, set insufficientEvidence to true.
                Do not identify a species or claim edited results or calibrated quality. Do not assume other passes agree.
                """
                return try await CombinedReviewResponse.inspection(backend.respond(instruction: CombinedReviewResponse.admitted(prompt, model: qwen, outputTokens: snapshot.responseTokens), image: crop, tokens: snapshot.responseTokens), regionID: region.id.rawValue)
            }
            if let inspection {
                let origin = try provenance(id, source: source, input: region.inputReference)
                result?.observations.append(.init(id: .init(rawValue: id.rawValue), regionID: region.id,
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
            let fallback = ReviewImageReport(id: .init(rawValue: file.id.rawValue + ":report"), imageID: file.id, claims: [], limitations: result?.limitations ?? [], incomplete: true,
                                             inspectedRegions: result?.observations.compactMap(\.regionID) ?? [], uninspectedRegions: plan.regions.map(\.id) + plan.uninspected)
            result?.report = fallback
        }
        try await store.saveManifest(currentManifest())
        progress = result?.report?.incomplete == true ? "Complete with limitations" : "Complete"
    }

    func replaceDependencies(_ id: ReviewWorkID, with parents: [ReviewWorkID]) {
        guard let index = manifest?.work.firstIndex(where: { $0.id == id }), let item = manifest?.work[index], item.state == .pending else { return }
        var replacement = ReviewWorkItem(id: item.id, imageID: item.imageID, stage: item.stage,
                                         dependencies: parents.map { .init(id: $0, allowsUnavailable: true) }, compatibility: item.compatibility)
        replacement.attempts = item.attempts
        manifest?.work[index] = replacement
    }

    func synthesize(_ backend: any CombinedReviewBackendServing, source: ReviewImageSource, qwen: ReviewModelSnapshot, plan: CombinedReviewPlan, reconciliation: Bool = false) async throws -> ReviewImageReport {
        guard let value = result, let snapshot = manifest?.snapshot else { throw ReviewRunError.invalidSnapshot }
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
        var rows: [(reference: ReviewEvidenceReference, text: String)] = []
        var aliases: [ReviewEvidenceReference: ReviewEvidenceReference] = [:]
        // Reconciliation is inspectable reasoning, not another independent evidence source.
        // Feeding its prose and nested provenance IDs back in bloats context and confuses the schema.
        for observation in value.observations where observation.availability == .available && observation.provenance.workID != Self.workID(value.file.id, "reconcile") {
            let ref = ReviewEvidenceReference(kind: .observation, id: "o\(aliases.count + 1)")
            let row = try String(decoding: encoder.encode(ref), as: UTF8.self) + " " + observation.text + " Uncertainty: " + observation.uncertainty
            rows.append((ref, row)); aliases[ref] = .init(kind: .observation, id: observation.id.rawValue)
        }
        for measurement in value.measurements {
            let ref = ReviewEvidenceReference(kind: .measurement, id: "m\(aliases.count + 1)")
            try rows.append((ref, String(decoding: encoder.encode(ref), as: UTF8.self) + " " + String(decoding: encoder.encode(measurement.values), as: UTF8.self)))
            aliases[ref] = .init(kind: .measurement, id: measurement.id.rawValue)
        }
        guard let exampleRow = rows.reversed().first(where: { $0.reference.kind == .observation }) ?? rows.last else { throw ReviewRunError.invalidEvidence }
        let exampleObservation = value.observations.first { $0.id.rawValue == aliases[exampleRow.reference]?.id }
        let example = ReviewClaim(text: exampleObservation.map { String($0.text.prefix(400)) } ?? "A render-dependent subject-detail measurement is available.",
                                  type: exampleObservation == nil ? "detail" : "composition", evidence: [exampleRow.reference],
                                  uncertainty: exampleObservation.map { String($0.uncertainty.prefix(200)) } ?? "The metric has no calibrated sharpness threshold.", contradictions: [])
        let exampleJSON = try String(decoding: encoder.encode(["claims": [example]]), as: UTF8.self)
        let schema = """
        \(reconciliation ? "Reconcile completed independent crop observations and terminal measured evidence, noting conflicts or abstaining." : "Synthesize the per-image report.")
        Review this photograph for: \(snapshot.criteria). Use only supplied evidence references.
        Return JSON only, using this exact structure and field types. This example is drawn from supplied evidence:
        \(exampleJSON)
        Write at most three descriptive claims. evidence and contradictions are arrays of kind/id objects; uncertainty is a string.
        Use only supplied short IDs with their matching kind. Never invent references.
        Source: \(source.metadata.fidelity.rawValue), \(source.image.width)x\(source.image.height), SDR sRGB.
        Available: \(value.measurements.count) measurements; \(value.observations.filter { $0.regionID != nil && $0.availability == .available }.count) crop observations. Failed stages: \(value.failures.count).
        Restrict claim text to composition, lighting, subject visibility and visible texture. Put anatomical limitations in uncertainty only.
        Allowed types: composition, exposure, visibility, detail, suggestion. Lighting uses exposure, not a new type.
        Missing stages require abstention. Do not mention eyes, iris, gaze or recovery in claim text.
        No RAW recovery or probability/quality claims from CLIP; detail requires a crop observation or measurement.
        Suggestions are untested hypotheses. Same-model agreement is not independent confirmation.
        Detail measurements are render-dependent, uncalibrated metrics, not sharp/blur labels.
        """
        // Keep crop observations ahead of overview; disclose any omitted optional evidence.
        var selected: [String] = []
        var included: Set<ReviewEvidenceReference> = []
        let orderedRows = [exampleRow] + rows.reversed().filter { $0.reference != exampleRow.reference }
        for row in orderedRows {
            if (try? CombinedReviewResponse.admitted(schema + "\n" + (selected + [row.text]).joined(separator: "\n"), model: qwen, outputTokens: snapshot.responseTokens)) != nil {
                selected.append(row.text)
                included.insert(row.reference)
            } else {
                limitation("Some optional evidence was omitted to stay within the verified model context.")
            }
        }
        let inspected = value.observations.filter { $0.regionID != nil && $0.availability == .available }.compactMap(\.regionID)
        let missing = plan.regions.map(\.id).filter { !inspected.contains($0) } + plan.uninspected
        if included.isEmpty {
            throw ReviewRunError.invalidEvidence
        }
        let prompt = try CombinedReviewResponse.admitted(schema + "\n" + selected.joined(separator: "\n"), model: qwen, outputTokens: snapshot.responseTokens)
        let text = try await backend.respond(instruction: prompt, image: source.overview, tokens: snapshot.responseTokens)
        let generated = try CombinedReviewResponse.report(text, imageID: value.file.id, allowed: included, limitations: result?.limitations ?? [], regions: inspected,
                                                          uninspected: missing, incomplete: !missing.isEmpty || !value.failures.isEmpty || value.measurements.isEmpty || value.clip.isEmpty)
        // Aliases exist only inside this request. Persist the real, validated provenance IDs.
        let claims = try generated.claims.map { claim in
            func resolve(_ reference: ReviewEvidenceReference) throws -> ReviewEvidenceReference {
                guard included.contains(reference), let stored = aliases[reference] else { throw ReviewRunError.invalidEvidence }
                return stored
            }
            return try ReviewClaim(text: claim.text, type: claim.type, evidence: claim.evidence.map(resolve),
                                   uncertainty: claim.uncertainty, contradictions: claim.contradictions.map(resolve))
        }
        let report = ReviewImageReport(id: generated.id, imageID: generated.imageID, claims: claims, limitations: generated.limitations,
                                       incomplete: generated.incomplete, inspectedRegions: generated.inspectedRegions, uninspectedRegions: generated.uninspectedRegions)
        for claim in report.claims {
            guard ["composition", "exposure", "visibility", "detail", "suggestion"].contains(claim.type) else { throw ReviewRunError.invalidEvidence }
            if claim.type == "detail" {
                let detailIDs = Set(value.observations.filter { $0.regionID != nil && $0.availability == .available }.map { $0.id.rawValue } + value.measurements.map { $0.id.rawValue })
                guard claim.evidence.contains(where: { detailIDs.contains($0.id) }) else { throw ReviewRunError.invalidEvidence }
                let lower = claim.text.lowercased()
                if ["sharp", "blur", "soft", "focus"].contains(where: lower.contains) {
                    let cropIDs = Set(value.observations.filter { $0.regionID != nil && $0.availability == .available }.map { $0.id.rawValue })
                    guard claim.evidence.contains(where: { $0.kind == .observation && cropIDs.contains($0.id) }) else { throw ReviewRunError.invalidEvidence }
                }
            }
        }
        return report
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

    func comparisonPrompt(_ values: [CombinedReviewResult], model: ReviewModelSnapshot, pair: Bool = false) throws -> (text: String, pruned: Bool) {
        let snapshot = try currentManifest().snapshot
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
        let schema = """
        Compare for goal: \(snapshot.criteria). Board labels are image IDs/annotations. \(pair ? "Matched candidate crops; individual identity unverified." : "Full-frame appearance board; no fine-detail evidence.")
        Require shared scene AND subject evidence; generic concepts do not establish identity. Unrelated/missing/conflicting evidence: abstain. Technical detail requires compatible fidelity/scale and cited crop observations from EACH image. CLIP is not quality. No eye/RAW recovery/identity claims. Suggestions are untested.
        JSON only: {"comparability":"insufficient","decision":"abstain","preferred":[],"reason":"Different scenes; retain individual reports.","claims":[]}
        comparability=comparable/unrelated/insufficient; decision=preferred/tie/abstain; preferred=image IDs (1/2+/0). Reason: ONE sentence, max 200 chars; never enumerate photographs there.
        At most 3 claims: {"imageIDs":["ID"],"claim":{"text":"strength/weakness/tradeoff","type":"composition","evidence":[{"kind":"observation","id":"ID"}],"uncertainty":"limits","contradictions":[]}}. Each named image must contribute evidence. Types: composition/exposure/visibility/detail/suggestion. Unresolved ties stay ties. Rows are excerpts; omitted evidence cannot support claims.
        """
        func mandatoryRows(excerptLimit: Int) throws -> [String] {
            var rows: [String] = []
            for value in values {
                let observation = value.observations.first(where: { $0.regionID == nil && $0.availability == .available })
                    ?? value.observations.first(where: { $0.availability == .available && !$0.provenance.workID.rawValue.contains(":reconcile") })
                guard let observation else { throw ReviewRunError.invalidEvidence }
                let reference = try String(decoding: encoder.encode(ReviewEvidenceReference(kind: .observation, id: observation.id.rawValue)), as: UTF8.self)
                rows.append("\(value.file.id.rawValue) \(value.source?.fidelity ?? "unavailable") missing=\(value.report?.incomplete != false) \(reference) \(observation.text.prefix(excerptLimit)) [excerpt; limits: \(observation.uncertainty.prefix(excerptLimit / 2))]")
            }
            return rows
        }
        var prompt = "", excerptLimit = 80
        for limit in [80, 60, 40, 20] {
            let candidate = try schema + "\n" + mandatoryRows(excerptLimit: limit).joined(separator: "\n")
            if (try? CombinedReviewResponse.admitted(candidate, model: model, outputTokens: snapshot.responseTokens)) != nil {
                prompt = candidate; excerptLimit = limit; break
            }
        }
        guard !prompt.isEmpty else { throw ReviewRunError.invalidEvidence }
        var pruned = values.contains { value in
            value.observations.contains { $0.text.count > excerptLimit || $0.uncertainty.count > excerptLimit / 2 }
        }
        let crops = values.map { $0.observations.filter { $0.regionID != nil && $0.availability == .available } }
        for round in 0 ..< (crops.map(\.count).max() ?? 0) {
            for (index, observations) in crops.enumerated() where round < observations.count {
                let observation = observations[round]
                let row = try values[index].file.id.rawValue + " " + String(decoding: encoder.encode(ReviewEvidenceReference(kind: .observation, id: observation.id.rawValue)), as: UTF8.self) + " " + observation.text + " Limits: " + observation.uncertainty
                if (try? CombinedReviewResponse.admitted(prompt + "\n" + row, model: model, outputTokens: snapshot.responseTokens)) != nil {
                    prompt += "\n" + row
                } else {
                    pruned = true
                }
            }
        }
        for value in values {
            for measurement in value.measurements where measurement.availability == .available {
                let reference = try String(decoding: encoder.encode(ReviewEvidenceReference(kind: .measurement, id: measurement.id.rawValue)), as: UTF8.self)
                let row = try value.file.id.rawValue + " " + reference + " technical; uncalibrated " + String(decoding: encoder.encode(measurement.values), as: UTF8.self)
                if (try? CombinedReviewResponse.admitted(prompt + "\n" + row, model: model, outputTokens: snapshot.responseTokens)) != nil {
                    prompt += "\n" + row
                } else {
                    pruned = true
                }
            }
        }
        return try (CombinedReviewResponse.admitted(prompt, model: model, outputTokens: snapshot.responseTokens), pruned)
    }

    static func validatePromptReferences(_ report: ReviewSelectionReport, prompt: String) throws {
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
        for reference in report.claims.flatMap({ $0.claim.evidence + $0.claim.contradictions }) {
            guard try prompt.contains(String(decoding: encoder.encode(reference), as: UTF8.self)) else { throw ReviewRunError.invalidEvidence }
        }
    }

    func compare(_ backend: any CombinedReviewBackendServing) async throws {
        let snapshot = try currentManifest().snapshot
        guard let qwen = snapshot.models["qwen"], let preference = ReviewSourcePreference(rawValue: snapshot.sourcePreference) else { throw ReviewRunError.invalidSnapshot }
        let id = Self.workID(snapshot.files[0].id, "selection")
        progress = "Comparing completed image evidence"
        let report: ReviewSelectionReport? = try await perform(id, category: .comparison) {
            guard results.allSatisfy({ $0.source != nil && $0.observations.contains { $0.availability == .available } }) else {
                return ReviewSelectionReport(comparability: .insufficient, decision: .abstain, preferred: [], claims: [], reason: "At least one image lacks source or validated observation evidence. Individual outcomes are retained.")
            }
            var images: [(ReviewImageID, CGImage)] = []
            for value in results {
                // Load one source at a time; retain only the small overview for the board.
                let source = try await sourceLoader.load(.init(url: value.file.url, preference: preference, policy: .appearance))
                guard source.metadata.identity == value.source?.sourceIdentity else { throw ReviewRunError.incompatible }
                images.append((value.file.id, source.overview))
            }
            let (board, cells) = try Self.comparisonBoard(images)
            let input = await retain(board)
            comparisonInputReference = input
            let prompt = try comparisonPrompt(results, model: qwen)
            let response = try await backend.respond(instruction: prompt.text, image: board, tokens: snapshot.responseTokens)
            var report = try ReviewSelectionReport.decode(response)
            try report.validate(results: results)
            try Self.validatePromptReferences(report, prompt: prompt.text)
            report.cells = cells; report.inputReference = input; report.contextPruned = prompt.pruned
            report.omittedPairs = results.count * (results.count - 1) / 2
            return report
        }
        selectionReport = report ?? .init(comparability: .insufficient, decision: .abstain, preferred: [], claims: [], reason: "Comparison failed validation or exceeded context. Individual reports remain available.")
        comparisonInputReference = selectionReport?.inputReference ?? comparisonInputReference
        try await comparePairs(backend, model: qwen, preference: preference)
    }

    func comparePairs(_ backend: any CombinedReviewBackendServing, model: ReviewModelSnapshot, preference: ReviewSourcePreference) async throws {
        guard let report = selectionReport, report.comparability == .comparable, report.decision == .tie else { return }
        let snapshot = try currentManifest().snapshot
        let candidates = results.filter { report.preferred.contains($0.file.id) }.sorted { $0.file.id.rawValue < $1.file.id.rawValue }
        var eligible: [CombinedReviewPair] = []
        for (index, left) in candidates.enumerated() {
            for right in candidates.dropFirst(index + 1) {
                // No automatic matching of multiple similar subjects. Same concept is a candidate, never proof of identity.
                guard left.subjects.count == 1, right.subjects.count == 1, left.subjects[0].concept == right.subjects[0].concept,
                      let leftRegion = left.regions.first(where: { $0.subjectID == left.subjects[0].id }),
                      let rightRegion = right.regions.first(where: { $0.subjectID == right.subjects[0].id }),
                      leftRegion.fidelity == rightRegion.fidelity, leftRegion.policy == rightRegion.policy,
                      abs(leftRegion.scaleX / rightRegion.scaleX - 1) <= 0.1, abs(leftRegion.scaleY / rightRegion.scaleY - 1) <= 0.1,
                      leftRegion.intendedRegionRetained, rightRegion.intendedRegionRetained else { continue }
                eligible.append(.init(left: left, right: right, leftRegion: leftRegion, rightRegion: rightRegion))
            }
        }
        for pair in eligible.prefix(snapshot.depth.pairCap) {
            let left = pair.left, right = pair.right, leftRegion = pair.leftRegion, rightRegion = pair.rightRegion
            let workID = Self.workID(snapshot.files[0].id, "pair:" + left.file.id.rawValue + ":" + right.file.id.rawValue)
            if manifest?.work.contains(where: { $0.id == workID }) != true {
                try manifest?.work.append(.init(id: workID, imageID: snapshot.files[0].id, stage: .comparison,
                                                dependencies: [.init(id: Self.workID(snapshot.files[0].id, "selection"), allowsUnavailable: false)],
                                                compatibility: ReviewCompatibility.make(snapshot: snapshot, image: snapshot.files[0], stage: .comparison, region: leftRegion.id.rawValue + ":" + rightRegion.id.rawValue)))
            }
            let value: ReviewSelectionReport? = try await perform(workID, category: .comparison) {
                var crops: [(ReviewImageID, CGImage)] = []
                for (value, region) in [(left, leftRegion), (right, rightRegion)] {
                    let source = try await sourceLoader.load(.init(url: value.file.url, preference: preference, policy: .appearance))
                    guard source.metadata.identity == region.sourceIdentity, let crop = source.image.cropping(to: region.sourceRect) else { throw ReviewRunError.incompatible }
                    crops.append((value.file.id, crop))
                }
                let (board, cells) = try Self.comparisonBoard(crops)
                let prompt = try comparisonPrompt([left, right], model: model, pair: true)
                var value = try await ReviewSelectionReport.decode(backend.respond(instruction: prompt.text, image: board, tokens: snapshot.responseTokens))
                try value.validate(results: [left, right]); try Self.validatePromptReferences(value, prompt: prompt.text); value.cells = cells; value.inputReference = await retain(board); value.contextPruned = prompt.pruned
                return value
            }
            if let value {
                selectionReport?.pairReports.append(value)
            }
        }
        let completedPairs = selectionReport?.pairReports.count ?? 0
        selectionReport?.omittedPairs = max(0, report.omittedPairs - completedPairs)
        // Pair suggestions remain explicit tradeoffs. They cannot silently resolve a selection-wide tie.
    }
}
