import CoreGraphics
import Foundation
import PhotoAIContracts
import PhotoAIStorage
import PhotoAIWorkflows
@testable import RawCull
import RawCullCore
import Testing

@Suite("Deep AI Review", .tags(.smoke))
struct DeepAIReviewFeatureTests {
    @MainActor
    @Test
    func `Feature publishes a typed completed result`() async throws {
        let request = makeRequest(candidateCount: 2)
        let feature = DeepAIReviewFeature(
            availability: .available(location: nil),
            service: ImmediateDeepReviewService(),
        )

        await feature.start(request)

        let result = try #require(feature.result(for: request.groupSignature))
        #expect(feature.state == .completed(result))
        #expect(result.recommendedFileID == request.candidates.first?.fileID)
        #expect(result.reasons == [.strongestSubjectDetail])
    }

    @MainActor
    @Test
    func `Cancelling Deep Review cancels the owned in-process task`() async {
        let request = makeRequest(candidateCount: 2)
        let service = CancellableDeepReviewService()
        let feature = DeepAIReviewFeature(
            availability: .available(location: nil),
            service: service,
        )

        let run = Task {
            await feature.start(request)
        }
        await service.waitUntilStarted()
        #expect(feature.state.isRunning)

        feature.cancel()
        await run.value

        #expect(feature.state == .cancelled(groupID: request.groupID))
        #expect(await service.observedCancellation())
    }

    @MainActor
    @Test
    func `Controller owns availability and request construction`() async throws {
        let feature = DeepAIReviewFeature(
            availability: .available(location: nil),
            service: ImmediateDeepReviewService(),
        )
        let controller = DeepAIReviewController(feature: feature)
        let applicationContext = DeepReviewApplicationContextStub()
        controller.bindApplicationContext(applicationContext)
        controller.preset = .headFace
        let file = FileItem(
            id: UUID(),
            url: URL(fileURLWithPath: "/tmp/controller.ARW"),
            name: "controller.ARW",
            size: 1,
            dateModified: Date(timeIntervalSince1970: 0),
            exifData: nil,
            afFocusNormalized: nil,
        )

        await controller.start(for: [file])

        let context = applicationContext.context
        let result = try #require(controller.result(for: context.groupSignature))
        #expect(result.preset == .headFace)
        #expect(result.recommendedFileID == file.id)
        #expect(controller.presentationState(
            groupID: context.groupID,
            groupSignature: context.groupSignature,
        ) == .completed(result))
    }

    @MainActor
    @Test
    func `Controller represents checking unavailable and cancelled states`() async {
        let expectedLocation = URL(fileURLWithPath: "/tmp/SAM3")
        let feature = DeepAIReviewFeature(
            availability: .checking(expectedLocations: [expectedLocation]),
        )
        let controller = DeepAIReviewController(feature: feature)
        let signature = BurstGroupSignature(memberKeys: ["frame.ARW"])

        #expect(controller.presentationState(
            groupID: 7,
            groupSignature: signature,
        ) == .checking(expectedLocations: [expectedLocation]))

        feature.install(
            service: nil,
            maskLoader: nil,
            availability: .missing(expectedLocations: [expectedLocation]),
        )
        #expect(controller.presentationState(
            groupID: 7,
            groupSignature: signature,
        ) == .unavailable(
            reason: "Install the selected segmentation model at /tmp/SAM3.",
        ))

        feature.install(
            service: CancellableDeepReviewService(),
            maskLoader: nil,
            availability: .available(location: expectedLocation),
        )
        let request = makeRequest(candidateCount: 1)
        let run = Task { await feature.start(request) }
        while !feature.isRunning {
            await Task.yield()
        }
        controller.cancel()
        await run.value
        #expect(controller.presentationState(
            groupID: request.groupID,
            groupSignature: request.groupSignature,
        ) == .cancelled(groupID: request.groupID))
    }

    @Test
    func `Prompt policy and candidate limit match burst Deep Review`() {
        #expect(RawCullDeepAIReviewPipeline.promptAttempts(
            preset: .auto,
            subjectLabel: "Bird of prey",
        ) == [.birdHead, .bird, .subject])
        #expect(RawCullDeepAIReviewPipeline.promptAttempts(
            preset: .headFace,
            subjectLabel: "person",
        ) == [.face, .person, .subject])
        #expect(RawCullDeepAIReviewPipeline.promptAttempts(
            preset: .fullSubject,
            subjectLabel: "bird",
        ) == [.subject])
        #expect(RawCullDeepAIReviewPipeline.selectedCandidateCount(from: 12) == 12)
        #expect(RawCullDeepAIReviewPipeline.selectedCandidateCount(from: 13) == 8)
    }

    @Test
    func `Deep Review preview loads the selected prompt from disk only`() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("DeepReviewDiskMaskLoader-\(UUID().uuidString)", isDirectory: true)
        let sourceURL = root.appendingPathComponent("frame.ARW")
        let maskDirectory = root.appendingPathComponent("Masks", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try Data([1, 2, 3]).write(to: sourceURL, options: .atomic)
        defer { try? FileManager.default.removeItem(at: root) }

        let modelIdentity = ModelIdentity(
            family: "efficient-sam",
            name: "preview-test",
            assetName: "preview-test.aimodel",
        )
        let configuration = SubjectMaskRepositoryConfiguration(
            modelIdentity: modelIdentity,
            inputMaxSide: 1_024,
        )
        let memoryStore = SubjectMaskMemoryStore()
        let diskStore = try SubjectMaskDiskStore(cacheDirectory: maskDirectory)
        let repository = SubjectMaskRepository(
            configuration: configuration,
            stores: [memoryStore, diskStore],
        )
        let source = AIImageSource(
            id: UUID(),
            url: sourceURL,
            displayName: "frame.ARW",
        )
        let mask = try #require(makeCenteredMask(width: 32, height: 24))
        let result = makeSegmentationResult(
            sourceID: source.id,
            prompt: .bird,
            mask: mask,
            modelIdentity: modelIdentity,
        )

        let birdKey = await repository.storageKey(for: source, prompt: .bird)
        try await diskStore.save(result, for: birdKey)

        let subjectKey = await repository.storageKey(for: source, prompt: .subject)
        await memoryStore.save(
            makeSegmentationResult(
                sourceID: source.id,
                prompt: .subject,
                mask: mask,
                modelIdentity: modelIdentity,
            ),
            for: subjectKey,
        )

        let loader = DeepAIReviewDiskMaskLoader(
            repository: repository,
            diskStore: diskStore,
        )
        let loaded = await loader.mask(for: source, prompt: .bird)

        #expect(loaded?.width == 32)
        #expect(loaded?.height == 24)
        #expect(await loader.mask(for: source, prompt: .subject) == nil)
    }

    @Test
    func `Subject-mask scorer measures detail only inside the mask`() async throws {
        let image = try #require(makeStripedImage(width: 128, height: 128))
        let backgroundDetailImage = try #require(makeBackgroundStripedImage(width: 128, height: 128))
        let mask = try #require(makeCenteredMask(width: 128, height: 128))

        let evidence = try #require(try await SubjectMaskFocusScorer().score(
            image: image,
            subjectMask: mask,
            normalizedAFPoint: CGPoint(x: 0.5, y: 0.5),
        ))
        let backgroundEvidence = try #require(try await SubjectMaskFocusScorer().score(
            image: backgroundDetailImage,
            subjectMask: mask,
            normalizedAFPoint: CGPoint(x: 0.1, y: 0.5),
        ))

        #expect(evidence.finalScore > 0, "score: \(evidence.finalScore)")
        #expect(evidence.finalScore > backgroundEvidence.finalScore)
        #expect(evidence.maskCoverage > 0.20, "coverage: \(evidence.maskCoverage)")
        #expect(evidence.maskCoverage < 0.30, "coverage: \(evidence.maskCoverage)")
        #expect(evidence.autofocusInsideMask == true, "AF: \(String(describing: evidence.autofocusInsideMask))")
        #expect(backgroundEvidence.autofocusInsideMask == false)
        #expect(evidence.usableLocalPatch, "local score: \(String(describing: evidence.localDetailScore))")
    }

    @MainActor
    private func makeRequest(candidateCount: Int) -> DeepAIReviewRequest {
        let signature = BurstGroupSignature(
            memberKeys: (0 ..< candidateCount).map { "frame-\($0).ARW" },
        )
        return DeepAIReviewRequest(
            groupID: 7,
            groupSignature: signature,
            candidates: (0 ..< candidateCount).map { index in
                DeepAIReviewInputCandidate(
                    fileID: UUID(),
                    fileName: "frame-\(index).ARW",
                    url: URL(fileURLWithPath: "/tmp/frame-\(index).ARW"),
                    burstRank: index + 1,
                    normalSharpnessScore: Float(candidateCount - index),
                    subjectLabel: "bird",
                    normalizedAFPoint: CGPoint(x: 0.5, y: 0.5),
                )
            },
            preset: .auto,
            scoringSource: .embeddedPreview,
        )
    }

    private func makeStripedImage(width: Int, height: Int) -> CGImage? {
        guard let context = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue,
        ) else { return nil }
        context.setFillColor(CGColor(gray: 0.5, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        for x in stride(from: width / 4, to: width * 3 / 4, by: 2) {
            context.setFillColor(CGColor(gray: x.isMultiple(of: 4) ? 0 : 1, alpha: 1))
            context.fill(CGRect(x: x, y: height / 4, width: 2, height: height / 2))
        }
        return context.makeImage()
    }

    private func makeBackgroundStripedImage(width: Int, height: Int) -> CGImage? {
        guard let context = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue,
        ) else { return nil }
        context.setFillColor(CGColor(gray: 0.5, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        for x in stride(from: 0, to: width / 5, by: 2) {
            context.setFillColor(CGColor(gray: x.isMultiple(of: 4) ? 0 : 1, alpha: 1))
            context.fill(CGRect(x: x, y: 0, width: 2, height: height))
            context.fill(CGRect(x: width - x - 2, y: 0, width: 2, height: height))
        }
        return context.makeImage()
    }

    private func makeCenteredMask(width: Int, height: Int) -> CGImage? {
        guard let context = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue,
        ) else { return nil }
        context.clear(CGRect(x: 0, y: 0, width: width, height: height))
        context.setFillColor(CGColor(gray: 1, alpha: 1))
        context.fill(CGRect(
            x: width / 4,
            y: height / 4,
            width: width / 2,
            height: height / 2,
        ))
        return context.makeImage()
    }

    private func makeSegmentationResult(
        sourceID: UUID,
        prompt: SubjectSegmentationPrompt,
        mask: CGImage,
        modelIdentity: ModelIdentity,
    ) -> SubjectSegmentationResult {
        let size = CGSize(width: mask.width, height: mask.height)
        let timing = SubjectSegmentationTiming(totalMilliseconds: 1)
        let diagnostics = SubjectSegmentationDiagnostics(
            modelIdentity: modelIdentity,
            prompt: prompt,
            confidence: 0.9,
            timing: timing,
            inputSize: size,
            outputSize: size,
        )
        return SubjectSegmentationResult(
            sourceID: sourceID,
            requestID: UUID(),
            prompt: prompt,
            mask: mask,
            confidence: 0.9,
            modelIdentity: modelIdentity,
            inputSize: size,
            outputSize: size,
            timing: timing,
            diagnostics: diagnostics,
        )
    }
}

@MainActor
private final class DeepReviewApplicationContextStub: DeepAIReviewApplicationContext {
    var isDeepAIReviewBlockedByOtherWork = false
    let context = DeepAIReviewGroupContext(
        groupID: 7,
        groupSignature: BurstGroupSignature(memberKeys: ["controller.ARW"]),
        candidates: [
            DeepAIReviewSourceCandidate(
                fileID: UUID(),
                fileName: "controller.ARW",
                url: URL(fileURLWithPath: "/tmp/controller.ARW"),
                burstRank: 1,
                normalSharpnessScore: 0.8,
                subjectLabel: "bird",
                normalizedAFPoint: CGPoint(x: 0.5, y: 0.5),
            )
        ],
        scoringSource: .embeddedPreview,
    )

    func deepAIReviewContext(for groupFiles: [FileItem]) -> DeepAIReviewGroupContext? {
        guard let file = groupFiles.first else { return nil }
        return DeepAIReviewGroupContext(
            groupID: context.groupID,
            groupSignature: context.groupSignature,
            candidates: context.candidates.map { candidate in
                DeepAIReviewSourceCandidate(
                    fileID: file.id,
                    fileName: file.name,
                    url: file.url,
                    burstRank: candidate.burstRank,
                    normalSharpnessScore: candidate.normalSharpnessScore,
                    subjectLabel: candidate.subjectLabel,
                    normalizedAFPoint: candidate.normalizedAFPoint,
                )
            },
            scoringSource: context.scoringSource,
        )
    }
}

private nonisolated struct ImmediateDeepReviewService: DeepAIReviewServicing, Sendable {
    func review(
        _ request: DeepAIReviewRequest,
        progress: @escaping @Sendable (DeepAIReviewProgress) async -> Void,
    ) async throws -> DeepAIReviewResult {
        let candidates = request.candidates.enumerated().map { index, input in
            DeepAIReviewCandidate(
                fileID: input.fileID,
                fileName: input.fileName,
                rank: input.burstRank,
                isCompleted: true,
                deepScore: Float(request.candidates.count - index),
                normalSharpnessScore: input.normalSharpnessScore,
                broadSubjectScore: 1,
                localDetailScore: 1,
                fineDetailScore: 1,
                maskPromptUsed: .birdHead,
                maskConfidence: 0.9,
                maskCoverage: 0.25,
                autofocusInsideMask: true,
                promptVerified: true,
                usedFallbackMask: false,
                issues: [],
            )
        }
        await progress(DeepAIReviewProgress(
            groupID: request.groupID,
            completedCount: candidates.count,
            totalCount: candidates.count,
            currentFileName: nil,
            candidates: candidates,
        ))
        return DeepAIReviewResult(
            groupID: request.groupID,
            groupSignature: request.groupSignature,
            preset: request.preset,
            candidates: candidates,
            recommendedFileID: candidates.first?.fileID,
            confidence: .high,
            reasons: [.strongestSubjectDetail],
            cautions: [],
            timestamp: Date(),
        )
    }
}

private actor CancellableDeepReviewService: DeepAIReviewServicing {
    private var started = false
    private var didObserveCancellation = false

    func review(
        _ request: DeepAIReviewRequest,
        progress: @escaping @Sendable (DeepAIReviewProgress) async -> Void,
    ) async throws -> DeepAIReviewResult {
        started = true
        await progress(DeepAIReviewProgress(
            groupID: request.groupID,
            completedCount: 0,
            totalCount: request.candidates.count,
            currentFileName: request.candidates.first?.fileName,
            candidates: [],
        ))
        do {
            try await Task.sleep(for: .seconds(30))
        } catch is CancellationError {
            didObserveCancellation = true
            throw CancellationError()
        }
        throw DeepAIReviewFailure.pipelineFailed("Unexpected test completion")
    }

    func waitUntilStarted() async {
        while !started {
            await Task.yield()
        }
    }

    func observedCancellation() -> Bool {
        didObserveCancellation
    }
}
