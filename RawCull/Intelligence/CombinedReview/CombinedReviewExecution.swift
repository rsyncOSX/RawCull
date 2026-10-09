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

extension CombinedReviewFeature {
    func perform<Value: Codable & Sendable>(_ id: ReviewWorkID, category: ReviewAttemptCategory? = nil,
                                            operation: () async throws -> Value) async throws -> Value? {
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
        let run = try currentManifest(), file = run.snapshot.files[0], id = Self.workID(file.id, name)
        if run.work.contains(where: { $0.id == id }) {
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
        let context = try await prepare(backend)
        let (plan, masks, segments) = try await plan(backend, context: context)
        let terminal = try await inspect(backend, context: context, plan: plan, masks: masks, segmentIDs: segments)
        try await finish(backend, context: context, plan: plan, terminalIDs: terminal)
    }

    func prepare(_ backend: any CombinedReviewBackendServing) async throws -> CombinedReviewContext {
        let run = try currentManifest(), snapshot = run.snapshot, file = snapshot.files[0]
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
                if index >= snapshot.depth.cropsPerImage {
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
                Inspect this unannotated source crop independently for: \(snapshot.criteria).
                Region ID: \(region.id.rawValue). Purpose: \(region.purpose).
                Return JSON only {"regionID":"\(region.id.rawValue)","observations":"visible detail, at most 500 characters","uncertainty":"limits, at most 200 characters","insufficientEvidence":false}.
                Abstain on unseen detail. Eye identity/localization is unverified; never claim eye sharpness.
                Do not claim RAW recovery, edited results, or calibrated quality scores. Do not assume other passes agree.
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
        let snapshot = context.snapshot, file = context.file, source = context.source, qwen = context.qwen
        let sourceID = Self.workID(file.id, "source"), overviewID = Self.workID(file.id, "overview"), identityID = Self.workID(file.id, "identity")
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
        var rows: [String] = [], allowed: Set<ReviewEvidenceReference> = []
        for observation in value.observations where observation.availability == .available {
            let ref = ReviewEvidenceReference(kind: .observation, id: observation.id.rawValue)
            let row = try String(decoding: encoder.encode(ref), as: UTF8.self) + " " + observation.text + " Uncertainty: " + observation.uncertainty
            rows.append(row); allowed.insert(ref)
        }
        for measurement in value.measurements {
            let ref = ReviewEvidenceReference(kind: .measurement, id: measurement.id.rawValue)
            try rows.append(String(decoding: encoder.encode(ref), as: UTF8.self) + " " + String(decoding: encoder.encode(measurement.values), as: UTF8.self))
            allowed.insert(ref)
        }
        let schema = """
        \(reconciliation ? "Reconcile completed independent crop observations and terminal measured evidence, noting conflicts or abstaining." : "Synthesize the per-image report.")
        Review this photograph for: \(snapshot.criteria). Use only supplied evidence references.
        Return JSON only {"claims":[{"text":"grounded claim","type":"composition","evidence":[{"kind":"observation","id":"exact ID"}],"uncertainty":"limits","contradictions":[]}]}.
        Source: \(source.metadata.fidelity.rawValue), \(source.image.width)x\(source.image.height), SDR sRGB.
        Available: \(value.measurements.count) measurements; \(value.observations.filter { $0.regionID != nil && $0.availability == .available }.count) crop observations. Failed stages: \(value.failures.count).
        Subject/eye/AF conclusions abstain when localization or measurement is missing.
        At most 6 claims; types: composition, exposure, visibility, detail, suggestion.
        Missing stages require abstention. Head masks do not localize eyes: no eye detail claims.
        No RAW recovery or probability/quality claims from CLIP; detail requires a crop observation or measurement.
        Suggestions are untested hypotheses. Same-model agreement is not independent confirmation.
        Detail measurements are render-dependent, uncalibrated metrics, not sharp/blur labels.
        """
        // Keep crop observations ahead of overview; disclose any omitted optional evidence.
        var selected: [String] = []
        for row in rows.reversed() {
            if (try? CombinedReviewResponse.admitted(schema + "\n" + (selected + [row]).joined(separator: "\n"), model: qwen, outputTokens: snapshot.responseTokens)) != nil {
                selected.append(row)
            } else {
                limitation("Some optional evidence was omitted to stay within the verified model context.")
            }
        }
        let included = Set(allowed.filter { ref in selected.contains { $0.contains("\"id\":\"" + ref.id + "\"") } })
        let inspected = value.observations.filter { $0.regionID != nil && $0.availability == .available }.compactMap(\.regionID)
        let missing = plan.regions.map(\.id).filter { !inspected.contains($0) } + plan.uninspected
        if included.isEmpty {
            throw ReviewRunError.invalidEvidence
        }
        let prompt = try CombinedReviewResponse.admitted(schema + "\n" + selected.joined(separator: "\n"), model: qwen, outputTokens: snapshot.responseTokens)
        let text = try await backend.respond(instruction: prompt, image: source.overview, tokens: snapshot.responseTokens)
        let report = try CombinedReviewResponse.report(text, imageID: value.file.id, allowed: included, limitations: result?.limitations ?? [], regions: inspected,
                                                       uninspected: missing, incomplete: !missing.isEmpty || !value.failures.isEmpty || value.measurements.isEmpty || value.clip.isEmpty)
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
