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
                modelIdentity: model, inputMaxSide: 4_320, maximumInstanceCount: 8,
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
        if changed && isRunning { cancel() }
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
        guard canRun, let segmentation else { return }
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
        let task = Task {
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
    }

    func retryFailed(_ files: [FileItem]) async {
        let failed = Set(results.filter { $0.failure != nil }.map(\.fileID))
        await analyze(files.filter { failed.contains($0.id) })
    }

    func clearResults() {
        guard !isRunning else { return }
        results.removeAll()
        failureMessage = nil
    }

    func cancel() {
        generation &+= 1
        task?.cancel()
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
        completedCount: Int, totalCount: Int,
    ) async -> ObjectPhotoAnalysisResult {
        var concepts: [SegmentationConcept] = []
        var descriptors: [ObjectInstanceDescriptor] = []
        var modelIdentity: ModelIdentity?
        do {
            guard let image = await imageLoader.thumbnailCGImage(
                for: file.url, maxPixelSize: 4_320,
            ) else { throw ObjectAnalysisError.imageUnavailable }
            try Task.checkCancellation()
            if mode == .automatic {
                setStage(.discoveringConcepts)
                let response = try await inference.respond(to: QwenVisionRequest(
                    instruction: ObjectConceptDiscovery.instruction,
                    image: image, maximumResponseTokens: 384,
                ))
                concepts = try ObjectConceptDiscovery.decode(response).map(\.concept)
            } else {
                concepts = manualConcepts
            }
            guard !concepts.isEmpty else { throw ObjectAnalysisError.noConcepts }
            var candidates: [ObjectInstanceDeduplicator.Candidate] = []
            let source = AIImageSource(id: file.id, url: file.url, displayName: file.name)
            for (index, concept) in concepts.enumerated() {
                try Task.checkCancellation()
                setStage(.segmenting(concept: concept.query, conceptIndex: index + 1,
                                      conceptCount: concepts.count))
                let result = try await segmentation.segment(image: image, source: source,
                                                            concept: concept)
                modelIdentity = result.modelIdentity
                candidates += result.instances.map {
                    ObjectInstanceDeduplicator.Candidate(
                        concept: concept, mask: $0.mask, score: $0.score,
                        normalizedBoundingBox: $0.normalizedBoundingBox,
                        sourceInstanceID: $0.id,
                    )
                }
            }
            setStage(.preparingObjectBoard)
            let retained = await Task { @concurrent in
                ObjectInstanceDeduplicator.retain(candidates)
            }.value
            descriptors = retained.map(\.descriptor)
            if retained.isEmpty {
                return makeResult(file, mode: mode, concepts: concepts, descriptors: [],
                                  assessment: nil, freeform: nil, failure: nil,
                                  modelIdentity: modelIdentity)
            }
            let board = try await Task { @concurrent in
                try ObjectReviewBoardRenderer.render(image: image, objects: retained)
            }.value
            try Task.checkCancellation()
            setStage(.analyzingObjects)
            let response = try await inference.respond(to: QwenVisionRequest(
                instruction: Self.analysisInstruction(ids: board.objectIDs, criteria: criteria),
                image: board.image, maximumResponseTokens: 1_024,
            ))
            try Task.checkCancellation()
            let assessment = try? ObjectAnalysisResponseDecoder.decode(
                response, boardIDs: Set(board.objectIDs),
            )
            return makeResult(file, mode: mode, concepts: concepts,
                              descriptors: descriptors, assessment: assessment,
                              freeform: assessment == nil ? response : nil, failure: nil,
                              modelIdentity: modelIdentity)
        } catch is CancellationError {
            return makeResult(file, mode: mode, concepts: concepts,
                              descriptors: descriptors, assessment: nil,
                              freeform: nil, failure: "Cancelled",
                              modelIdentity: modelIdentity)
        } catch {
            return makeResult(file, mode: mode, concepts: concepts,
                              descriptors: descriptors, assessment: nil,
                              freeform: nil, failure: error.localizedDescription,
                              modelIdentity: modelIdentity)
        }
    }

    private func makeResult(
        _ file: FileItem, mode: ObjectDiscoveryMode,
        concepts: [SegmentationConcept], descriptors: [ObjectInstanceDescriptor],
        assessment: ObjectPhotoAssessment?, freeform: String?, failure: String?,
        modelIdentity: ModelIdentity?,
    ) -> ObjectPhotoAnalysisResult {
        let qwenName: String? = if case let .available(_, name) = qwenStatus { name } else { nil }
        return ObjectPhotoAnalysisResult(
            fileID: file.id, fileName: file.name, concepts: concepts.map(\.query),
            discoveryMode: mode, instances: descriptors,
            assessment: assessment, freeformResponse: freeform, failure: failure,
            sam3ModelIdentity: modelIdentity?.artifactIdentifier,
            sam3Model: modelIdentity, qwenModelName: qwenName, timestamp: Date(),
        )
    }

    private nonisolated static func analysisInstruction(ids: [String], criteria: String) -> String {
        """
        Analyze only the numbered objects on this review board. Use visible evidence only.
        Object IDs: \(ids.joined(separator: ", ")).
        Additional criteria: \(criteria)
        Return exactly one JSON object and no Markdown with these keys:
        imageSummary (string), objects (array of {id, concept, description, visibility,
        focusQuality, expression, obstructions, strengths, problems, confidence}),
        relationships (strings), strengths (strings), problems (strings),
        preferredObjectIDs (array of board IDs), confidence (0 to 1).
        visibility must be clear, partial, obscured, or uncertain.
        focusQuality must be sharp, soft, blurred, or uncertain.
        Do not create objects that are not numbered on the board.
        """
    }
}
