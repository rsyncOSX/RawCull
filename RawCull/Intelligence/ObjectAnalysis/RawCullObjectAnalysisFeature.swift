import CoreGraphics
import Foundation
import Observation
import PhotoAIContracts
import PhotoAIWorkflows

nonisolated enum ObjectAnalysisAvailability: Equatable, Sendable {
    case checking
    case ready
    case sam3Unavailable
    case qwenUnavailable
    case bothUnavailable
}

@Observable @MainActor
final class RawCullObjectAnalysisFeature {
    var discoveryMode: ObjectDiscoveryMode = .automatic
    var manualConceptText = ""
    var criteria = "Describe visibility, focus, expression, obstructions, and photographic strengths."

    private(set) var availability: ObjectAnalysisAvailability = .checking
    private(set) var progress: ObjectAnalysisProgress?
    private(set) var results: [ObjectPhotoAnalysisResult] = []
    private(set) var failureMessage: String?
    private(set) var isRunning = false

    @ObservationIgnored private let inference: any QwenInferenceServing
    @ObservationIgnored private let imageLoader: any RawImageLoading
    @ObservationIgnored private var segmentation: ObjectSegmentationService?
    @ObservationIgnored private var qwenStatus: QwenModelStatus = .notConfigured
    @ObservationIgnored private var drainingTasks: [Task<Void, Never>] = []
    @ObservationIgnored private var task: Task<Void, Never>?
    @ObservationIgnored private var generation = 0
    @ObservationIgnored private let maskStores: [any ObjectMaskStoring]

    init(inference: any QwenInferenceServing,
         imageLoader: any RawImageLoading = RawParserKitImageLoader.shared,
         maskStores: [any ObjectMaskStoring] = []) {
        self.inference = inference
        self.imageLoader = imageLoader
        self.maskStores = maskStores
    }

    func sharesInferenceIdentity(with inference: any QwenInferenceServing) -> Bool {
        self.inference === inference
    }

    func cachedMasks(for result: ObjectPhotoAnalysisResult,
                     file: FileItem) async -> [String: CGImage] {
        guard let model = result.sam3Model else { return [:] }
        let source = AIImageSource(id: file.id, url: file.url, displayName: file.name)
        let identity = await Task { @concurrent in
            SourceFileIdentity.read(from: source.url)
        }.value
        var masks: [String: CGImage] = [:]
        for query in Set(result.instances.map(\.concept)) {
            guard let concept = try? SegmentationConcept(query) else { continue }
            let key = ObjectMaskStorageKey(
                source: source, sourceIdentity: identity, concept: concept,
                modelIdentity: model, inputMaxSide: 4320, maximumInstanceCount: 8,
            )
            for store in maskStores {
                if let cached = await store.load(for: key) {
                    for descriptor in result.instances where descriptor.concept == query {
                        if let instance = cached.instances.first(where: { $0.id == descriptor.sourceInstanceID }) {
                            masks[descriptor.id] = instance.mask
                        }
                    }
                    break
                }
            }
        }
        return masks
    }

    func install(segmentation: ObjectSegmentationService?, qwenStatus: QwenModelStatus) {
        let changed = self.segmentation !== segmentation || self.qwenStatus != qwenStatus
        if changed, isRunning {
            cancel()
        }
        self.segmentation = segmentation
        self.qwenStatus = qwenStatus
        availability = switch (segmentation != nil, qwenStatus.isAvailable) {
        case (true, true): .ready
        case (false, false): .bothUnavailable
        case (false, true): .sam3Unavailable
        case (true, false): .qwenUnavailable
        }
    }

    var canRun: Bool {
        availability == .ready && !isRunning
            && (discoveryMode == .automatic || !manualConceptText.isEmpty)
    }

    func filesNeedingAnalysis(from files: [FileItem]) -> [FileItem] {
        let completed = Set(results.filter(\.isSuccessful).map(\.fileID))
        return files.filter { !completed.contains($0.id) }
    }

    func analyze(_ files: [FileItem]) async {
        guard !CombinedReviewLease.shared.isHeld, canRun, let segmentation else { return }
        let pending = filesNeedingAnalysis(from: files)
        guard !pending.isEmpty else { return }
        let mode = discoveryMode
        let manualText = manualConceptText
        let criteria = criteria.trimmingCharacters(in: .whitespacesAndNewlines)
        let manualConcepts: [SegmentationConcept]
        do {
            manualConcepts = mode == .specificConcepts
                ? try ObjectConceptDiscovery.parseManual(manualText) : []
        } catch {
            failureMessage = error.localizedDescription
            return
        }
        generation &+= 1
        let runGeneration = generation
        isRunning = true
        failureMessage = nil
        let feature = self
        let access = RawCullCatalogAccess.shared.retainAccess(for: pending.map(\.url))
        let task = Task {
            defer { withExtendedLifetime(access) {} }
            for (index, file) in pending.enumerated() {
                guard !Task.isCancelled, feature.generation == runGeneration else { break }
                feature.progress = ObjectAnalysisProgress(
                    currentFileName: file.name, completedCount: index,
                    totalCount: pending.count, stage: .loadingImage,
                )
                let result = await feature.analyzeOne(
                    file, mode: mode, manualConcepts: manualConcepts,
                    criteria: criteria, segmentation: segmentation,
                    completedCount: index, totalCount: pending.count,
                )
                guard !Task.isCancelled, feature.generation == runGeneration else { break }
                feature.replace(result)
            }
            guard feature.generation == runGeneration else { return }
            feature.isRunning = false
            feature.progress = nil
            feature.task = nil
        }
        self.task = task
        await withTaskCancellationHandler {
            await task.value
        } onCancel: {
            task.cancel()
        }
        drainingTasks.removeAll { $0 == task }
    }

    func retryFailed(_ files: [FileItem]) async {
        let failed = Set(results.filter { !$0.isSuccessful }.map(\.fileID))
        await analyze(files.filter { failed.contains($0.id) })
    }

    func clearResults() {
        guard !isRunning else { return }
        results.removeAll()
        failureMessage = nil
    }

    func cancelAndWait() async {
        cancel()
        let draining = drainingTasks
        drainingTasks = []
        for worker in draining {
            await worker.value
        }
    }

    func cancel() {
        generation &+= 1
        if let task {
            drainingTasks.append(task); task.cancel()
        }
        task = nil
        progress = nil
        isRunning = false
    }

    private func replace(_ result: ObjectPhotoAnalysisResult) {
        results.removeAll { $0.fileID == result.fileID }
        results.append(result)
    }

    private func setStage(_ stage: ObjectAnalysisStage) {
        guard let progress else { return }
        self.progress = ObjectAnalysisProgress(
            currentFileName: progress.currentFileName,
            completedCount: progress.completedCount,
            totalCount: progress.totalCount, stage: stage,
        )
    }

    private func analyzeOne(
        _ file: FileItem, mode: ObjectDiscoveryMode,
        manualConcepts: [SegmentationConcept], criteria: String,
        segmentation: ObjectSegmentationService,
        completedCount _: Int, totalCount _: Int,
    ) async -> ObjectPhotoAnalysisResult {
        var concepts: [SegmentationConcept] = []
        var descriptors: [ObjectInstanceDescriptor] = []
        var rawInstanceCount = 0
        var modelIdentity: ModelIdentity?
        var failureStage: String?
        var timings = ObjectAnalysisTimings()
        do {
            guard let image = await imageLoader.thumbnailCGImage(
                for: file.url, maxPixelSize: 4320,
            ) else { throw ObjectAnalysisError.imageUnavailable }
            try Task.checkCancellation()
            let previous = results.first { $0.fileID == file.id }
            let currentQwenName: String? = if case let .available(_, name) = qwenStatus {
                name
            } else {
                nil
            }
            let reusable = previous.flatMap { result -> ObjectPhotoAnalysisResult? in
                guard result.needsAssessmentRetry, result.discoveryMode == mode,
                      mode == .automatic || result.concepts == manualConcepts.map(\.query),
                      result.sourceSize == file.size,
                      result.sourceModified == file.dateModified,
                      result.qwenModelName == currentQwenName,
                      !result.instances.isEmpty else { return nil }
                return result
            }
            let cached = if let reusable {
                await cachedMasks(for: reusable, file: file)
            } else {
                [String: CGImage]()
            }
            let reuse = reusable != nil && cached.count == reusable?.instances.count
            var retained: [ObjectInstanceDeduplicator.Retained] = []
            if reuse, let reusable {
                concepts = reusable.concepts.compactMap { try? SegmentationConcept($0) }
                descriptors = reusable.instances
                rawInstanceCount = reusable.rawInstanceCount
                modelIdentity = reusable.sam3Model
                retained = descriptors.compactMap { descriptor in
                    cached[descriptor.id].map { .init(descriptor: descriptor, mask: $0) }
                }
            } else if mode == .automatic {
                setStage(.discoveringConcepts)
                failureStage = "Concept discovery"
                let discoveryStart = Date()
                let response = try await inference.respond(to: QwenVisionRequest(
                    instruction: ObjectConceptDiscovery.instruction,
                    image: image, maximumResponseTokens: 384,
                ))
                captureDiagnostic(response, file: file, stage: "discovery", tokenLimit: 384)
                concepts = try ObjectConceptDiscovery.decode(response).map(\.concept)
                timings.conceptDiscoverySeconds = Date().timeIntervalSince(discoveryStart)
            } else {
                concepts = manualConcepts
            }
            guard !concepts.isEmpty else { throw ObjectAnalysisError.noConcepts }
            failureStage = nil
            if !reuse {
                let segmentationStart = Date()
                var candidates: [ObjectInstanceDeduplicator.Candidate] = []
                let source = AIImageSource(id: file.id, url: file.url, displayName: file.name)
                for (index, concept) in concepts.enumerated() {
                    try Task.checkCancellation()
                    setStage(.segmenting(concept: concept.query, conceptIndex: index + 1,
                                         conceptCount: concepts.count))
                    let result = try await segmentation.segment(image: image, source: source,
                                                                concept: concept)
                    modelIdentity = result.modelIdentity
                    rawInstanceCount += result.instances.count
                    candidates += result.instances.map {
                        ObjectInstanceDeduplicator.Candidate(
                            concept: concept, mask: $0.mask, score: $0.score,
                            normalizedBoundingBox: $0.normalizedBoundingBox,
                            sourceInstanceID: $0.id,
                        )
                    }
                }
                retained = await Task { @concurrent in ObjectInstanceDeduplicator.retain(candidates) }.value
                descriptors = retained.map(\.descriptor)
                timings.segmentationSeconds = Date().timeIntervalSince(segmentationStart)
            }
            setStage(.preparingObjectBoard)
            if retained.isEmpty {
                return makeResult(file, mode: mode, concepts: concepts, descriptors: [],
                                  assessment: nil, freeform: nil, failure: nil,
                                  modelIdentity: modelIdentity, rawInstanceCount: rawInstanceCount,
                                  timings: timings)
            }
            let boardStart = Date()
            let board = try await Task { @concurrent in
                try ObjectReviewBoardRenderer.render(image: image, objects: retained)
            }.value
            timings.boardRenderingSeconds = Date().timeIntervalSince(boardStart)
            try Task.checkCancellation()
            setStage(.analyzingObjects)
            failureStage = "Object assessment"
            let assessmentStart = Date()
            let instruction = Self.analysisInstruction(ids: board.objectIDs, concepts: descriptors, criteria: criteria)
            var feedback = ""
            for attempt in 0..<2 {
                try Task.checkCancellation()
                let response = try await inference.respond(to: QwenVisionRequest(
                    instruction: instruction + feedback,
                    image: board.image, maximumResponseTokens: 1024,
                ))
                captureDiagnostic(response, file: file, stage: attempt == 0 ? "assessment" : "assessment-retry", tokenLimit: 1024)
                timings.assessmentSeconds = Date().timeIntervalSince(assessmentStart)
                try Task.checkCancellation()
                do {
                    let assessment = try ObjectAnalysisResponseDecoder.decode(response, boardIDs: Set(board.objectIDs),
                        expectedConcepts: Dictionary(uniqueKeysWithValues: descriptors.map { ($0.id, $0.concept) }))
                    return makeResult(file, mode: mode, concepts: concepts,
                                      descriptors: descriptors, assessment: assessment,
                                      freeform: nil, failure: nil, modelIdentity: modelIdentity,
                                      rawInstanceCount: rawInstanceCount, timings: timings)
                } catch {
                    let details = Self.assessmentValidationFeedback(response, fallback: error.localizedDescription)
                    if attempt == 0 {
                        feedback = "\nThe previous response failed validation: \(details)\nRegenerate from this same board using the exact JSON types in the example. IDs and cropIDs are strings. All lists are arrays, never null. Each claim needs its own matching evidence object. Global strengths and problems must be []. Do not invent observations or copy example judgments."
                        continue
                    }
                    return makeResult(file, mode: mode, concepts: concepts,
                                      descriptors: descriptors, assessment: nil,
                                      freeform: String(response.prefix(8192)),
                                      failure: "Object assessment after two attempts: \(details)",
                                      modelIdentity: modelIdentity, rawInstanceCount: rawInstanceCount,
                                      timings: timings)
                }
            }
            preconditionFailure("Assessment loop must return or throw")
        } catch is CancellationError {
            return makeResult(file, mode: mode, concepts: concepts,
                              descriptors: descriptors, assessment: nil,
                              freeform: nil, failure: "Cancelled",
                              modelIdentity: modelIdentity, rawInstanceCount: rawInstanceCount,
                              timings: timings)
        } catch {
            return makeResult(file, mode: mode, concepts: concepts,
                              descriptors: descriptors, assessment: nil,
                              freeform: nil,
                              failure: failureStage.map { "\($0): \(error.localizedDescription)" }
                                  ?? error.localizedDescription,
                              modelIdentity: modelIdentity, rawInstanceCount: rawInstanceCount,
                              timings: timings)
        }
    }

    private func makeResult(
        _ file: FileItem, mode: ObjectDiscoveryMode,
        concepts: [SegmentationConcept], descriptors: [ObjectInstanceDescriptor],
        assessment: ObjectPhotoAssessment?, freeform: String?, failure: String?,
        modelIdentity: ModelIdentity?, rawInstanceCount: Int,
        timings: ObjectAnalysisTimings,
    ) -> ObjectPhotoAnalysisResult {
        let qwenName: String? = if case let .available(_, name) = qwenStatus {
            name
        } else {
            nil
        }
        return ObjectPhotoAnalysisResult(
            fileID: file.id, fileName: file.name, concepts: concepts.map(\.query),
            discoveryMode: mode, rawInstanceCount: rawInstanceCount, instances: descriptors,
            assessment: assessment, freeformResponse: freeform, failure: failure,
            sam3ModelIdentity: modelIdentity?.artifactIdentifier,
            sam3Model: modelIdentity, qwenModelName: qwenName,
            sourceSize: file.size, sourceModified: file.dateModified,
            timings: timings, timestamp: Date(),
        )
    }

    // Objects-only feedback supplements strict validation without repairing model claims.
    nonisolated static func assessmentValidationFeedback(_ response: String, fallback: String) -> String {
        var issues: [String] = []
        // Inspect enum values before typed decoding, which rejects unknown values.
        if let data = try? ObjectJSONEnvelope.data(in: response),
           let document = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let objects = document["objects"] as? [[String: Any]] {
            for (index, object) in objects.enumerated() {
                if let visibility = object["visibility"] as? String, ObjectVisibility(rawValue: visibility) == nil {
                    issues.append("objects[\(index)].visibility is invalid. Use exactly clear, partial, obscured, or uncertain. Visible is not an allowed value; choose from the permitted values using the subject's visible extent and occlusion.")
                }
            }
        }
        guard let assessment = try? ObjectJSONEnvelope.decode(ObjectPhotoAssessment.self, from: response) else {
            return issues.isEmpty ? fallback : issues.joined(separator: "\n")
        }
        if !assessment.strengths.isEmpty || !assessment.problems.isEmpty {
            issues.append("Global strengths and problems must both be []; supported claims belong only on their numbered objects with matching evidence.")
        }
        for object in assessment.objects {
            let prefix = "Object \(object.id)"
            for (claims, evidence, claimField, evidenceField) in [
                (object.strengths, object.strengthEvidence, "strengths", "strengthEvidence"),
                (object.problems, object.problemEvidence, "problems", "problemEvidence")
            ] {
                if claims.count != evidence.count {
                    issues.append("\(prefix): \(claimField) has \(claims.count) items but \(evidenceField) has \(evidence.count). These counts must match exactly. Regenerate with at most ONE supported claim and ONE matching evidence object, or [] for both; do not return two claims with one evidence entry. If \(claimField) is [], \(evidenceField) must also be []. Omit unsupported claims and their evidence together.")
                }
                for (index, item) in evidence.enumerated() {
                    if item.cropID != object.id {
                        issues.append("\(prefix): \(evidenceField)[\(index)].cropID must be the string \(object.id).")
                    }
                }
            }
            if object.focusQuality != .uncertain && object.focusEvidence == nil {
                issues.append("\(prefix): focusQuality is \(object.focusQuality.rawValue), so focusEvidence cannot be null. Supply {\"cropID\":\"\(object.id)\",\"observation\":\"short visible focus evidence from this crop\"}. If focus cannot be judged, set focusQuality to uncertain and focusEvidence to null; do not invent evidence.")
            } else if object.focusQuality == .uncertain && object.focusEvidence != nil {
                issues.append("\(prefix): uncertain focusQuality requires focusEvidence to be null.")
            } else if let evidence = object.focusEvidence, evidence.cropID != object.id {
                issues.append("\(prefix): focusEvidence.cropID must be the string \(object.id).")
            } else if let evidence = object.focusEvidence,
                      !ObjectAnalysisResponseDecoder.focusDescription(evidence.observation, supports: object.focusQuality) {
                issues.append("\(prefix): focusEvidence.observation does not support focusQuality=\(object.focusQuality.rawValue). Being visible or 'in focus' alone does not demonstrate resolved detail. Describe actual subject texture or edges: crisp/distinctly resolved for sharp, lacking crisp detail for soft, smeared/indistinct for blurred. Exclude grass, fence and background texture. If this crop cannot support a focus judgment, use uncertain with null evidence and omit unsupported sharpness claims. Do not invent detail or simply insert a keyword.")
            }
        }
        return issues.isEmpty ? fallback : issues.joined(separator: "\n")
    }

    private nonisolated static func analysisInstruction(ids: [String], concepts: [ObjectInstanceDescriptor], criteria: String) -> String {
        """
        This board shows one photograph: the top overview and the numbered crops below are repeated views of the same photo, not separate photographs. Analyze only the numbered objects. Use visible evidence only.
        The crops are enlargements from this SAME exposure and SAME camera viewpoint. They are not different angles, poses, moments, or separate photographs. Describe the original scene once; do not describe the board layout in imageSummary.
        Object IDs: \(ids.joined(separator: ", ")).
        Registered concepts (copy the concept exactly for each ID): \(concepts.map { "\($0.id)=\($0.concept)" }.joined(separator: "; ")).
        The numbered crops at the bottom are ordered left to right: \(ids.map { "crop \($0) is object \($0)" }.joined(separator: "; ")). Match each description to that crop's large number, not to its order of mention in the overview.
        Additional criteria: \(criteria)
        JSON template only: replace every angle-bracket placeholder with an observation from this board. Never copy placeholder text as evidence. Choose focusQuality from the permitted values; for uncertain focus replace focusEvidence with null. Repeat one object per registered ID:
        {"schemaVersion":2,"imageSummary":"Short scene description","objects":[{"id":"1","concept":"registered concept","description":"Short visible description","visibility":"uncertain","focusQuality":"<sharp, soft, blurred, or uncertain>","focusEvidence":{"cropID":"1","observation":"<describe visible texture or edges on this numbered subject>"},"expression":null,"obstructions":[],"strengths":[],"strengthEvidence":[],"problems":[],"problemEvidence":[],"confidence":0.5}],"relationships":[],"strengths":[],"problems":[],"preferredObjectIDs":[],"confidence":0.5}
        For a supported focus judgment, focusEvidence is an object such as {"cropID":"1","observation":"<describe visible texture or edges on this numbered subject>"}, never a string. A supported strength/problem uses the same object shape in its evidence array, one per claim. IDs, cropIDs and preferredObjectIDs entries MUST be quoted strings. Never return null for list fields.
        Return exactly one JSON object and no Markdown with these keys:
        schemaVersion (2), imageSummary (short string), objects (array of {id, concept, description, visibility,
        focusQuality, focusEvidence, expression, obstructions, strengths, strengthEvidence, problems, problemEvidence, confidence}),
        relationships (strings), strengths (strings), problems (strings),
        preferredObjectIDs (array of board IDs), confidence (0 to 1).
        focusEvidence is null only for uncertain focus; otherwise {"cropID":"the matching object ID","observation":"visible texture/edge evidence and whether it is crisp, soft, or smeared"}.
        strengthEvidence and problemEvidence are arrays with one evidence object per respective strength/problem, in matching order, using the same cropID and observation schema. Never cite another crop or background detail. Empty claims require empty evidence arrays. Evidence sentences maximum 240 characters. Do not contradict focusQuality in description, strengths or problems.
        Before returning JSON, check each object independently: strengths.count == strengthEvidence.count and problems.count == problemEvidence.count. Never leave evidence entries after removing their claims. A sharp, soft or blurred focusQuality always requires its own focusEvidence object; only uncertain uses null.
        Claim pair template only: "strengths":["<one supported strength>"], "strengthEvidence":[{"cropID":"1","observation":"<the visible observation supporting that exact strength>"}]. Empty pair: "strengths":[], "strengthEvidence":[]. Use the identical pairing rule for problems/problemEvidence. Replace the example with this crop's visible evidence, or return both arrays empty.
        Confidence and focus classifications are model judgments; the preview, resizing and model input resolution limit detail. No RAW recovery or eye-detail claims. Global strengths/problems must be empty; put supported judgments with their crop evidence on each object.
        visibility must be exactly clear, partial, obscured, or uncertain; never use visible.
        focusQuality must be sharp, soft, blurred, or uncertain. Decide independently for each subject. Visibility, recognizable anatomy, and being in focus are insufficient evidence of sharpness; identify actual resolved subject texture or edges. Do not use surrounding grass or fence texture. Use uncertain when the preview cannot resolve enough detail, and omit unsupported sharpness strengths.
        Judge focus separately for each numbered subject using visible detail on that subject, not the flower, background, outline, or another crop. Use sharp only when fine texture or edges on the subject are distinctly resolved. Use soft when subject detail is visible but lacks crisp edges, blurred when subject detail is smeared or indistinct, and uncertain when the crop is too small or obscured to tell. Do not describe a subject as well-focused or list sharpness as a strength unless its own crop supports sharp.
        The objects array must contain exactly \(ids.count) entries: one per listed ID, with no repeated IDs. Each numbered ID marks a different physical subject in the one photograph. The overview and crops repeat those subjects, so do not list a new object for each view. expression must be null because these SAM regions do not independently verify facial anatomy; all list fields must be arrays, using [] when empty. Use at most two short sentences per description. For each object, return at most ONE strength and at most ONE problem, each with exactly ONE matching evidence entry. When no claim is supported, return [] for both its claim list and evidence list. Other lists may contain at most two short items. Each object's description must use visible evidence from its matching numbered crop. imageSummary must describe the scene without calling separate IDs the same subject or different photographs. Describe relationships only when supported by the overview; never call different IDs the same subject. Do not invent extra objects, issues, or relationships.
        """
    }

    private func captureDiagnostic(_ response: String, file: FileItem, stage: String, tokenLimit: Int) {
        guard let path = ProcessInfo.processInfo.environment["RAWCULL_OBJECT_CAPTURE_DIR"],
              !path.isEmpty else { return }
        let directory = URL(fileURLWithPath: path, isDirectory: true)
        let model = if case let .available(_, name) = qwenStatus {
            name
        } else {
            "unknown"
        }
        let header = "file: \(file.name)\nfile ID: \(file.id)\nstage: \(stage)\nmodel: \(model)\nrequested token limit: \(tokenLimit)\nresponse characters: \(response.count)\n\n"
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true,
                                                    attributes: [.posixPermissions: 0o700])
            let permissions = try FileManager.default.attributesOfItem(atPath: directory.path)[.posixPermissions] as? NSNumber
            guard let permissions, permissions.intValue & 0o077 == 0 else { return }
            let file = directory.appendingPathComponent("object-\(stage)-\(UUID().uuidString).txt")
            try (header + response).write(to: file, atomically: true, encoding: .utf8)
            try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: file.path)
        } catch {
            // Diagnostic capture is optional and must not affect analysis.
        }
    }
}
