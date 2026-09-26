import AppKit
import CoreGraphics
import Foundation
import PhotoAIContracts
import PhotoAIStorage
import PhotoAIWorkflows
@testable import RawCull
import RawCullCore
import Testing

@Suite("Object analysis feature", .tags(.smoke))
struct ObjectAnalysisFeatureTests {
    @Test func `Near-identical cross-concept masks merge and retain alias`() throws {
        let mask = try makeMask()
        let bird = try SegmentationConcept("bird")
        let animal = try SegmentationConcept("animal")
        let box = CGRect(x: 0.2, y: 0.2, width: 0.5, height: 0.5)
        let retained = ObjectInstanceDeduplicator.retain([
            .init(concept: bird, mask: mask, score: 0.9, normalizedBoundingBox: box),
            .init(concept: animal, mask: mask, score: 0.8, normalizedBoundingBox: box)
        ])
        #expect(retained.count == 1)
        #expect(retained[0].descriptor.id == "1")
        #expect(retained[0].descriptor.aliases == ["animal"])
        let board = try ObjectReviewBoardRenderer.render(image: mask, objects: retained)
        #expect(board.image.width == 2048)
        #expect(board.image.height == 2048)
        #expect(board.objectIDs == ["1"])
        let edgeCrop = ObjectReviewBoardRenderer.crop(
            for: CGRect(x: 0.9, y: 0.9, width: 0.1, height: 0.1),
            width: 32, height: 32,
        )
        #expect(edgeCrop.minX >= 0 && edgeCrop.minY >= 0)
        #expect(edgeCrop.maxX <= 32 && edgeCrop.maxY <= 32)
        #expect(edgeCrop.minY == 0)
        let separate = ObjectInstanceDeduplicator.retain([
            .init(concept: bird, mask: mask, score: 0.9,
                  normalizedBoundingBox: CGRect(x: 0.05, y: 0.2, width: 0.25, height: 0.5)),
            .init(concept: bird, mask: mask, score: 0.8,
                  normalizedBoundingBox: CGRect(x: 0.7, y: 0.2, width: 0.25, height: 0.5))
        ])
        #expect(separate.map(\.descriptor.id) == ["1", "2"])
    }

    @Test func `Review board rejects an object whose numbered crop is unavailable`() throws {
        let image = try makeMask()
        let object = ObjectInstanceDeduplicator.Retained(
            descriptor: ObjectInstanceDescriptor(
                id: "1", concept: "bird", aliases: [], score: 0.9,
                normalizedBoundingBox: CGRect(x: 2, y: 0.2, width: 0.1, height: 0.1),
                sourceInstanceID: "1",
            ),
            mask: image,
        )
        #expect(throws: ObjectAnalysisError.reviewBoardUnavailable) {
            try ObjectReviewBoardRenderer.render(image: image, objects: [object])
        }
    }

    @Test func `Grayscale instance mask becomes a transparent contour`() async throws {
        let mask = try makeMask()
        let outline = try #require(await ObjectMaskOutlineRenderer.outline(from: mask))
        #expect(outline.width == mask.width)
        #expect(outline.height == mask.height)
        var pixels = [UInt8](repeating: 0, count: 32 * 32 * 4)
        let context = try #require(CGContext(
            data: &pixels, width: 32, height: 32, bitsPerComponent: 8,
            bytesPerRow: 32 * 4, space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue,
        ))
        context.draw(outline, in: CGRect(x: 0, y: 0, width: 32, height: 32))
        let centerAlpha = pixels[(16 * 32 + 16) * 4 + 3]
        let edgeAlpha = pixels[(16 * 32 + 6) * 4 + 3]
        #expect(centerAlpha < edgeAlpha)
        #expect(edgeAlpha > 0)
    }

    @MainActor
    @Test func `Model removal cancels an in-flight object result`() async throws {
        let image = try makeMask()
        let qwen = ObjectQwenStub(delayResponse: true)
        let service = try ObjectSegmentationService(
            provider: ObjectSegmenterStub(mask: image), maxSide: 4320,
        )
        let feature = RawCullObjectAnalysisFeature(
            inference: qwen, imageLoader: ObjectImageLoaderStub(image: image),
        )
        feature.install(segmentation: service, qwenStatus: .available(
            url: URL(fileURLWithPath: "/tmp/qwen"), modelName: "Qwen Test",
        ))
        feature.discoveryMode = .specificConcepts
        feature.manualConceptText = "bird"
        let file = FileItem(
            id: UUID(), url: URL(fileURLWithPath: "/tmp/removal-test.jpg"),
            name: "removal.jpg", size: 1, dateModified: .distantPast,
            exifData: nil, afFocusNormalized: nil,
        )
        let work = Task { await feature.analyze([file]) }
        await qwen.waitUntilCalled()
        feature.install(segmentation: nil, qwenStatus: .notConfigured)
        await work.value
        #expect(feature.results.isEmpty)
        #expect(feature.availability == .bothUnavailable)
    }

    @MainActor
    @Test func `Manual analysis reports no matching objects without asking Qwen for a board`() async throws {
        let image = try makeMask()
        let qwen = ObjectQwenStub()
        let service = try ObjectSegmentationService(
            provider: ObjectSegmenterStub(mask: image, empty: true), maxSide: 32,
        )
        let feature = RawCullObjectAnalysisFeature(
            inference: qwen, imageLoader: ObjectImageLoaderStub(image: image),
        )
        feature.install(segmentation: service, qwenStatus: .available(
            url: URL(fileURLWithPath: "/tmp/qwen"), modelName: "Qwen Test",
        ))
        feature.discoveryMode = .specificConcepts
        feature.manualConceptText = "bird"
        let file = FileItem(
            id: UUID(), url: URL(fileURLWithPath: "/tmp/empty-object-test.jpg"),
            name: "empty.jpg", size: 1, dateModified: .distantPast,
            exifData: nil, afFocusNormalized: nil,
        )
        await feature.analyze([file])
        #expect(feature.results.first?.instances.isEmpty == true)
        #expect(feature.results.first?.failure == nil)
        #expect(await qwen.callCount == 0)
    }

    @MainActor
    @Test func `Automatic analysis discovers, segments, and assesses one object`() async throws {
        let image = try makeMask()
        let qwen = ObjectQwenStub()
        let segmenter = ObjectSegmenterStub(mask: image)
        let store = ObjectMaskMemoryStore()
        let service = try ObjectSegmentationService(provider: segmenter,
                                                    stores: [store], maxSide: 4320)
        let feature = RawCullObjectAnalysisFeature(
            inference: qwen, imageLoader: ObjectImageLoaderStub(image: image),
            maskStores: [store],
        )
        feature.install(segmentation: service, qwenStatus: .available(
            url: URL(fileURLWithPath: "/tmp/qwen"), modelName: "Qwen Test",
        ))
        let file = FileItem(
            id: UUID(), url: URL(fileURLWithPath: "/tmp/object-test.jpg"),
            name: "object-test.jpg", size: 1, dateModified: .distantPast,
            exifData: nil, afFocusNormalized: nil,
        )
        await feature.analyze([file])
        let result = try #require(feature.results.first)
        #expect(result.failure == nil)
        #expect(result.concepts == ["bird", "animal"])
        #expect(result.instances.count == 1)
        #expect(result.instances[0].aliases == ["animal"])
        #expect(result.assessment?.objects.first?.id == "1")
        #expect(result.qwenModelName == "Qwen Test")
        #expect(await feature.cachedMasks(for: result, file: file)["1"] != nil)
        #expect(await qwen.callCount == 2)
        #expect(await segmenter.callCount == 2)
    }

    @MainActor
    @Test func `Invalid assessment stays retryable and reuses cached segmentation`() async throws {
        let image = try makeMask()
        let qwen = ObjectQwenStub(invalidFirstAssessment: true)
        let segmenter = ObjectSegmenterStub(mask: image)
        let store = ObjectMaskMemoryStore()
        let service = try ObjectSegmentationService(provider: segmenter, stores: [store], maxSide: 4320)
        let feature = RawCullObjectAnalysisFeature(
            inference: qwen, imageLoader: ObjectImageLoaderStub(image: image), maskStores: [store],
        )
        feature.install(segmentation: service, qwenStatus: .available(
            url: URL(fileURLWithPath: "/tmp/qwen"), modelName: "Qwen Test",
        ))
        feature.discoveryMode = .specificConcepts
        feature.manualConceptText = "bird"
        let file = FileItem(id: UUID(), url: URL(fileURLWithPath: "/tmp/retry-object-test.jpg"),
                            name: "retry.jpg", size: 1, dateModified: .distantPast,
                            exifData: nil, afFocusNormalized: nil)
        await feature.analyze([file])
        #expect(feature.results.first?.needsAssessmentRetry == true)
        #expect(feature.filesNeedingAnalysis(from: [file]).count == 1)
        #expect(await segmenter.callCount == 1)
        await feature.retryFailed([file])
        #expect(feature.results.first?.isSuccessful == true)
        #expect(feature.results.first?.assessment?.objects.first?.id == "1")
        #expect(await segmenter.callCount == 1)
        #expect(await qwen.callCount == 2)
    }

    private func makeMask() throws -> CGImage {
        let width = 32, height = 32
        let pixels = Data((0 ..< (width * height)).map { index in
            let x = index % width, y = index / width
            return (x >= 6 && x < 26 && y >= 6 && y < 26) ? UInt8(255) : UInt8(0)
        })
        let provider = try #require(CGDataProvider(data: pixels as CFData))
        return try #require(CGImage(
            width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 8,
            bytesPerRow: width, space: CGColorSpaceCreateDeviceGray(),
            bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.none.rawValue),
            provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent,
        ))
    }
}

private actor ObjectQwenStub: QwenInferenceServing {
    private(set) var callCount = 0
    let delayResponse: Bool
    let invalidFirstAssessment: Bool
    private var startWaiter: CheckedContinuation<Void, Never>?
    init(delayResponse: Bool = false, invalidFirstAssessment: Bool = false) {
        self.delayResponse = delayResponse
        self.invalidFirstAssessment = invalidFirstAssessment
    }

    func validate(url: URL) -> QwenModelStatus {
        .available(url: url, modelName: "Qwen Test")
    }

    func respond(to _: QwenVisionRequest) async throws -> String {
        callCount += 1
        startWaiter?.resume()
        startWaiter = nil
        if delayResponse {
            try await Task.sleep(for: .seconds(1))
        }
        if invalidFirstAssessment, callCount == 1 {
            return #"{"imageSummary":"Incomplete"}"#
        }
        if callCount == 1, !invalidFirstAssessment {
            return #"{"concepts":[{"query":"bird","displayName":"Bird","reason":"Visible"},{"query":"animal","displayName":"Animal","reason":"Visible"}]}"#
        }
        return #"{"imageSummary":"One bird","objects":[{"id":"1","concept":"bird","description":"A bird","visibility":"clear","focusQuality":"sharp","expression":null,"obstructions":[],"strengths":[],"problems":[],"confidence":0.9}],"relationships":[],"strengths":[],"problems":[],"preferredObjectIDs":["1"],"confidence":0.9}"#
    }

    func assess(criteria _: String, image _: CGImage) -> QwenModelResponse {
        .freeform("unused")
    }

    func clear() {}
    func waitUntilCalled() async {
        if callCount > 0 {
            return
        }
        await withCheckedContinuation { startWaiter = $0 }
    }
}

private actor ObjectSegmenterStub: ObjectInstanceSegmenting {
    nonisolated let modelIdentity = ModelIdentity(family: "sam3", name: "test", assetName: "test.aimodel")
    private(set) var callCount = 0
    let mask: CGImage
    let empty: Bool
    init(mask: CGImage, empty: Bool = false) {
        self.mask = mask; self.empty = empty
    }

    func segmentInstances(_ request: ObjectSegmentationRequest) -> ObjectSegmentationResult {
        callCount += 1
        let instance = ObjectMaskInstance(
            index: 0, mask: mask, score: request.concept.query == "bird" ? 0.9 : 0.8,
            normalizedBoundingBox: CGRect(x: 0.2, y: 0.2, width: 0.5, height: 0.5),
        )
        return ObjectSegmentationResult(
            sourceID: request.sourceID, requestID: request.requestID,
            concept: request.concept, instances: empty ? [] : [instance], modelIdentity: modelIdentity,
            inputSize: request.inputSize, outputSize: request.outputSize, timing: .init(),
        )
    }
}

private struct ObjectImageLoaderStub: RawImageLoading {
    let image: CGImage
    func fileMetadata(for _: URL) async -> RawImageFileMetadata? {
        nil
    }

    func thumbnailCGImage(for _: URL, maxPixelSize _: Int) async -> CGImage? {
        image
    }

    func thumbnailImage(for _: URL, maxPixelSize _: Int) async -> NSImage? {
        nil
    }

    func previewCGImage(for _: URL) async -> CGImage? {
        image
    }

    func embeddedPreviewJPEGData(
        for _: URL, matchingPixelWidth _: Int, height _: Int,
    ) async -> Data? {
        nil
    }
}
