import AppKit
import CoreGraphics
import Foundation

nonisolated struct CombinedReviewPlan: Codable, Sendable {
    var omissions: [ReviewRegionOmission]? = nil
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
            let diagnostic = await failureDiagnostic(error, item: item)
            try Task.checkCancellation()
            if manifest?.work.first(where: { $0.id == id })?.state == .running {
                try manifest?.finish(id, state: .failed, reason: diagnostic.compactReason)
            } else {
                try manifest?.skip(id, reason: diagnostic.compactReason)
            }
            if let index = manifest?.work.firstIndex(where: { $0.id == id }) {
                manifest?.work[index].diagnostic = diagnostic
            }
            result?.failures[id.rawValue] = diagnostic.compactReason
            try await store.saveManifest(currentManifest())
            return nil
        }
    }

    /// One fresh response may repair a malformed request-boundary payload. Every
    /// additional model call is charged and the original rejection is retained.
    func validatedResponse<Value>(instruction: String, image: CGImage, model: ReviewModelSnapshot,
                                  tokens: Int, backend: any CombinedReviewBackendServing,
                                  validation: (String) throws -> Value) async throws -> Value {
        let text = try await backend.respond(instruction: instruction, image: image, tokens: tokens)
        do {
            return try CombinedReviewResponse.validated(text, validation)
        } catch let rejection as ReviewResponseRejection {
            guard ([.json, .schema, .unknownID].contains(rejection.issue.code) || rejection.issue.check == "crop.supportedDomain"),
                  let file = activeFile else { throw rejection }
            let correction = """
            Previous response failed validation: \(rejection.issue.check), field \(rejection.issue.fieldPath ?? "JSON").
            Return a fresh complete JSON object. Include every required field with its exact type.
            Evidence must use supplied reference IDs, never observation text. Do not invent IDs or evidence.
            For prohibited crop text, replace ONLY that criterion with a surface/framing observation, or supported=false,text="". Never repeat anatomy. Preserve all required fields.
            """
            // Keep the full original schema and evidence; never truncate to fit a repair.
            guard let prompt = try? CombinedReviewResponse.admitted(instruction + "\n" + correction, model: model, outputTokens: tokens) else { throw rejection }
            do { try manifest?.budget.consume(.repair, imageID: file.id) } catch { throw rejection }
            if let index = manifest?.work.firstIndex(where: { $0.imageID == file.id && $0.state == .running }) {
                manifest?.work[index].attempts += 1
            }
            try await store.saveManifest(currentManifest())
            try Task.checkCancellation()
            let repaired = try await backend.respond(instruction: prompt, image: image, tokens: tokens)
            let value = try CombinedReviewResponse.validated(repaired, validation)
            if let item = manifest?.work.first(where: { $0.imageID == file.id && $0.state == .running }) {
                let diagnostic = await failureDiagnostic(rejection, item: item)
                if let index = manifest?.work.firstIndex(where: { $0.id == item.id }) {
                    manifest?.work[index].diagnostic = diagnostic
                }
            }
            return value
        }
    }

    func failureDiagnostic(_ error: any Error, item: ReviewWorkItem) async -> ReviewFailureDiagnostic {
        let issue = ReviewValidationIssue.classify(error)
        var diagnostic = ReviewFailureDiagnostic(stage: item.stage, workID: item.id, code: issue.code,
                                                 check: issue.check, fieldPath: issue.fieldPath, evidenceReference: issue.evidenceReference)
        if let rejection = error as? ReviewResponseRejection,
           let snapshot = manifest?.snapshot, snapshot.diagnosticRetention == .boundedRejectedText
        {
            let used = manifest?.retainedDiagnosticBytes ?? 0
            let cap = min(ReviewDiagnosticLimits.perResponseBytes, max(0, ReviewDiagnosticLimits.perRunBytes - used))
            let bounded = ReviewDiagnosticLimits.bounded(rejection.response, maximumBytes: cap)
            diagnostic.responseTruncated = bounded.truncated
            if !bounded.text.isEmpty {
                do {
                    diagnostic.rejectedResponseKey = try await store.retainRejectedResponse(.init(runID: snapshot.id, workID: item.id, text: bounded.text, truncated: bounded.truncated))
                    diagnostic.retainedResponseBytes = bounded.text.utf8.count
                    manifest?.retainedDiagnosticBytes = used + diagnostic.retainedResponseBytes
                } catch { diagnostic.retentionUnavailable = true }
            }
        }
        return diagnostic
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
            let text = try await backend.respond(instruction: prompt, image: source.overview, tokens: snapshot.responseTokens)
            return try CombinedReviewResponse.validated(text) { try CombinedReviewResponse.overview($0) }
        }
        result?.overview = overview
        if let overview {
            for note in overview.validationNotes ?? [] { limitation(note) }
            let origin = try provenance(overviewID, source: source, input: overviewInput)
            result?.observations.append(.init(id: .init(rawValue: file.id.rawValue + ":overview"), regionID: nil,
                                              text: overview.observations, uncertainty: overview.uncertainty, availability: .available,
                                              provenance: origin))
        } else {
            limitation("Overview/discovery unavailable; crop observations remain independent.")
        }
        return .init(snapshot: snapshot, file: file, source: source, qwen: qwen, overview: overview)
    }

    func registeredCandidates(_ candidates: [ObjectInstanceDeduplicator.Candidate], source: ReviewImageSource) throws -> [ObjectInstanceDeduplicator.Candidate] {
        try candidates.map { candidate in
            let registration = try ReviewMaskRegistration.make(mask: candidate.mask, source: source, producerBounds: candidate.normalizedBoundingBox)
            return try ObjectInstanceDeduplicator.candidate(concept: candidate.concept.query, mask: candidate.mask, score: candidate.score,
                                                            bounds: registration.normalizedBounds(width: source.image.width, height: source.image.height), id: candidate.sourceInstanceID)
        }
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
                    let retained = try ObjectInstanceDeduplicator.retain(registeredCandidates(candidates, source: source), maximumCount: 8)
                    var values: [ReviewSubjectRecord] = []
                    for candidate in retained {
                        let maskKey = await retain(candidate.mask, force: true)
                        let subjectID = ReviewSubjectID(rawValue: file.id.rawValue + ":subject:" + String(index) + ":" + candidate.descriptor.id)
                        masks[subjectID] = candidate.mask
                        try values.append(.init(maskContract: SubjectMaskContract.make(mask: candidate.mask, sourceIdentity: source.metadata.identity), registration: ReviewMaskRegistration.make(mask: candidate.mask, source: source, producerBounds: candidates.first { $0.sourceInstanceID == candidate.descriptor.sourceInstanceID }?.normalizedBoundingBox ?? candidate.descriptor.normalizedBoundingBox), id: subjectID, imageID: file.id, concept: concept,
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
        subjects = try ReviewSubjectPriority.assign(subjects, cues: overview?.primarySubjects ?? [], contextual: overview?.contextualConcepts ?? [], masks: masks, provenance: overviewID.rawValue)
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
                for candidate in try ObjectInstanceDeduplicator.retain(registeredCandidates(candidates, source: source), maximumCount: 8) {
                    let bounds = candidate.descriptor.normalizedBoundingBox
                    // Association requires a small, contained head candidate; ambiguous overlaps abstain.
                    let parents = subjects.filter { $0.normalizedBounds.contains(bounds) && bounds.width * bounds.height < $0.normalizedBounds.width * $0.normalizedBounds.height * 0.6 }
                    guard parents.count == 1, let parent = parents.first else {
                        omissions.append(.init(regionID: .init(rawValue: ReviewCompatibility.digest(headID.rawValue + ":" + candidate.descriptor.sourceInstanceID)), subjectID: nil,
                                               reason: .ambiguousAnatomy, detail: "Head-query foreground has no unique parent association; no anatomical label is qualified"))
                        continue
                    }
                    try await records.append(.init(maskContract: SubjectMaskContract.make(mask: candidate.mask, sourceIdentity: source.metadata.identity), registration: ReviewMaskRegistration.make(mask: candidate.mask, source: source, producerBounds: candidates.first { $0.sourceInstanceID == candidate.descriptor.sourceInstanceID }?.normalizedBoundingBox ?? bounds), id: parent.id, imageID: file.id, concept: "Generic candidate region within " + parent.concept,
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
                    let foreground = try SubjectMaskForeground.decode(mask, width: source.image.width, height: source.image.height)
                    support = .init(registrationVersion: ReviewMaskRegistration.version,
                                    subjectForegroundRetained: ReviewMaskRegistration.retainedFraction(foreground, in: region.sourceRect),
                                    encoderForegroundRetained: ReviewMaskRegistration.retainedFraction(foreground, in: region.encoder.retainedSourceRect),
                                    sourceEdgeContact: subjects.first { $0.id == subjectID }?.registration?.touchesSourceEdge ?? false,
                                    anatomicalSupport: "unverified; foreground retention is not semantic identity")
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
                      mask.width == technical.image.width, mask.height == technical.image.height,
                      let contract = subject.maskContract else { throw SubjectMaskDecodingError.unsafeRegistration }
                try contract.validate(mask: mask, sourceIdentity: source.metadata.identity)
                guard let measured = try await scorer.score(image: technical.image, subjectMask: mask, normalizedAFPoint: nil) else { throw ReviewValidationIssue(.maskDecoding, "measurement.availableScore", field: "subjectMask") }
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
                Inspect this crop for four separate criteria. Region ID: \(region.id.rawValue). Purpose: \(region.purpose).
                Return JSON only: {"regionID":"\(region.id.rawValue)","criteria":{"composition":{"supported":false,"text":""},"exposure":{"supported":false,"text":""},"visibility":{"supported":false,"text":""},"detail":{"supported":false,"text":""}},"uncertainty":"","insufficientEvidence":true,"targetIdentified":false}.
                Include all fields. Determine booleans from the crop; the example is not a conclusion.
                Each text: one criterion-specific sentence, max 120 characters. Unsupported means supported=false and text="". Never repeat a sentence across criteria.
                composition: placement, framing or obstructions. exposure: illumination or tonal contrast; a light-colored sky alone is not exposure evidence.
                visibility: visible extent or occlusion of the intended generic target; species/identity uncertainty is not visibility.
                detail: resolved surface texture of that target only, never background texture or anatomical detail. If unresolved, abstain.
                targetIdentified means the intended generic target is visibly present and distinguishable. It does not mean species identification, individual identity, verified anatomy or fine-detail quality. Never assume presence from Purpose alone. Purpose gives no intended target: false.
                intended generic target absent/indistinguishable: targetIdentified=false and detail.supported=false.
                insufficientEvidence=true only if all four criteria are unsupported. It cannot be true with targetIdentified=true.
                Text must stay within framing, illumination, occlusion and surface texture. Do not describe body parts, species, focus, sharpness or RAW recovery. Anatomical limitations belong in uncertainty only (max 160 characters).
                """
                return try await validatedResponse(instruction: CombinedReviewResponse.admitted(prompt, model: qwen, outputTokens: snapshot.responseTokens), image: crop, model: qwen, tokens: snapshot.responseTokens, backend: backend) { try CombinedReviewResponse.inspection($0, regionID: region.id.rawValue, requireCriteria: true) }
            }
            if let inspection {
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

    func replaceDependencies(_ id: ReviewWorkID, with parents: [ReviewWorkID]) {
        guard let index = manifest?.work.firstIndex(where: { $0.id == id }), let item = manifest?.work[index], item.state == .pending else { return }
        var replacement = ReviewWorkItem(id: item.id, imageID: item.imageID, stage: item.stage,
                                         dependencies: parents.map { .init(id: $0, allowsUnavailable: true) }, compatibility: item.compatibility)
        replacement.attempts = item.attempts
        manifest?.work[index] = replacement
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
            let evidenceText: String
            if let criteria = observation.criteria {
                evidenceText = ReviewCriterionObservations.types.compactMap { type in
                    guard let entry = criteria[type], entry.supported else { return nil }
                    return type + ": " + entry.text
                }.joined(separator: " | ")
            } else { evidenceText = observation.text }
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
        JSON only: {"claims":[]}. At most four claims: one per supported type, no duplicates.
        Claims: text (max 400), type, evidence, uncertainty (max 160), contradictions.
        Types: composition, exposure, visibility, detail. Each supported criterion has its own observation text.
        Copy only the matching criterion text from ONE supplied row; never reuse another criterion or uncertainty. Do not paraphrase, merge or invent conclusions. Legacy rows support composition/visibility only.
        evidence/contradictions: arrays of {"kind":"observation","id":"o1"} with supplied IDs. Omit subjectID/regionID. No prose or shorthand strings in arrays.
        Detail needs ONE subjectDetailSupported=true crop. Exposure needs its explicit exposure entry, not sky color. Visibility needs its visibility entry, not identity uncertainty.
        Omit unsupported types. contradictions=[] unless observations conflict. No anatomy, focus, numbers, recovery or quality scores. Same-model agreement is not independent confirmation.
        Source: \(source.metadata.fidelity.rawValue), \(source.image.width)x\(source.image.height), SDR sRGB. Failed stages: \(value.failures.count).
        """
        // Reserve 320 bytes for the concrete detail directive and 480 for validation feedback.
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
        // Nominate from admitted evidence only; ordering allocates evidence, not photographic importance.
        // A concrete reference avoids asking the model to choose and merge eligible subject rows.
        let detailRow = orderedRows.first { row in
            guard included.contains(row.reference), let stored = aliases[row.reference],
                  let support = try? grounding.support(stored) else { return false }
            return support.subjectDetailSupported && support.criteria != nil
        }
        let detailInstruction: String
        if let detailRow {
            let reference = String(decoding: try encoder.encode(detailRow.reference), as: UTF8.self)
            detailInstruction = "Detail evidence for this request: [" + reference + "]. Use this exact one-element evidence array for detail, or omit detail if its observation does not support texture. Copy only this row's detail entry; never another criterion or background."
        } else {
            detailInstruction = "No admitted subject crop supports detail. Omit the detail claim."
        }
        let prompt = try CombinedReviewResponse.admitted(schema + "\n" + selected.joined(separator: "\n") + "\n" + detailInstruction, model: qwen, outputTokens: snapshot.responseTokens)
        return try await validatedResponse(instruction: prompt, image: source.overview, model: qwen, tokens: snapshot.responseTokens, backend: backend) { text in
            let generated = try CombinedReviewResponse.report(text, imageID: value.file.id, allowed: included, limitations: result?.limitations ?? [], regions: inspected,
                                                              uninspected: missing, incomplete: !missing.isEmpty || !value.failures.isEmpty || value.measurements.isEmpty || value.clip.isEmpty) { claim in
                func resolve(_ reference: ReviewEvidenceReference) throws -> ReviewEvidenceReference {
                    guard included.contains(reference), let stored = aliases[reference] else { throw ReviewValidationIssue(.unknownID, "synthesis.aliasResolution", field: "claims.evidence") }
                    return stored
                }
                let resolved = try ReviewClaim(subjectID: claim.subjectID, regionID: claim.regionID, text: claim.text, type: claim.type, evidence: claim.evidence.map(resolve),
                                               uncertainty: claim.uncertainty, contradictions: claim.contradictions.map(resolve))
                if ["exposure", "detail"].contains(resolved.type) {
                    guard resolved.evidence.contains(where: { ref in value.observations.contains { $0.id.rawValue == ref.id && $0.criteria != nil } }) else {
                        throw ReviewValidationIssue(.grounding, "synthesis.criterionRequired", field: "claims.evidence")
                    }
                }
                return try grounding.validate(resolved)
            }
            let qualified = generated.claims
            let missingCriteria = ["composition", "exposure", "visibility", "detail"].filter { criterion in
                !qualified.contains { $0.type == criterion }
            }
            let coverage = missingCriteria.map { ReviewLimitation(id: .init(rawValue: value.file.id.rawValue + ":coverage:" + $0), reason: "No supported " + $0 + " claim; abstained because admitted observations did not establish this criterion.", relatedEvidence: []) }
            return ReviewImageReport(id: generated.id, imageID: generated.imageID, claims: qualified, limitations: generated.limitations + coverage,
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
                guard let observation else { throw ReviewValidationIssue(.grounding, "comparison.independentObservation") }
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
        guard !prompt.isEmpty else { throw ReviewValidationIssue(.responseLength, "comparison.mandatoryPromptFits") }
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
            for measurement in value.measurements where measurement.hasCurrentMaskSemantics {
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
            guard try prompt.contains(String(decoding: encoder.encode(reference), as: UTF8.self)) else { throw ReviewValidationIssue(.grounding, "comparison.referenceIncludedInPrompt", field: "claims.evidence") }
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
            var report = try CombinedReviewResponse.validated(response) { response in
                let report = try ReviewSelectionReport.decode(response)
                try report.validate(results: results)
                try Self.validatePromptReferences(report, prompt: prompt.text)
                return report
            }
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
                      leftRegion.intendedRegionRetained, rightRegion.intendedRegionRetained,
                      leftRegion.support?.qualifiesWholeSubject == true, rightRegion.support?.qualifiesWholeSubject == true else { continue }
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
                let response = try await backend.respond(instruction: prompt.text, image: board, tokens: snapshot.responseTokens)
                var value = try CombinedReviewResponse.validated(response) { response in
                    let value = try ReviewSelectionReport.decode(response)
                    try value.validate(results: [left, right]); try Self.validatePromptReferences(value, prompt: prompt.text)
                    return value
                }
                value.cells = cells; value.inputReference = await retain(board); value.contextPruned = prompt.pruned
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
