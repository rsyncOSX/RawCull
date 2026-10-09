import AppKit
import CoreGraphics
import Foundation
import ImageIO
@testable import RawCull
import RawCullCore
import Testing

@Suite("Qwen feature", .tags(.smoke))
struct QwenFeatureTests {
    @Test(.enabled(if: ProcessInfo.processInfo.environment["QWEN_PHASE3_BUNDLE"] != nil &&
            ProcessInfo.processInfo.environment["QWEN_PHASE3_IMAGE"] != nil))
    func `Local Qwen model answers a general vision request`() async throws {
        let environment = ProcessInfo.processInfo.environment
        let bundlePath = try #require(environment["QWEN_PHASE3_BUNDLE"])
        let imagePath = try #require(environment["QWEN_PHASE3_IMAGE"])
        let source = try #require(CGImageSourceCreateWithURL(
            URL(fileURLWithPath: imagePath) as CFURL, nil,
        ))
        let image = try #require(CGImageSourceCreateThumbnailAtIndex(source, 0, [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: 1024,
        ] as CFDictionary))
        let runtime = QwenInferenceRuntime()
        let status = await runtime.validate(url: URL(fileURLWithPath: bundlePath))
        #expect(status.isAvailable)
        let capabilities = try #require(await runtime.inputCapabilities())
        #expect(capabilities.maximumContextTokens > 0)
        #expect(capabilities.maximumResponseTokens == 4096)
        #expect(capabilities.imagesPerRequest == 1)
        // Declared metadata must never be presented as observed geometry.
        #expect(!capabilities.encoderGeometryVerified)
        let response = try await runtime.respond(to: QwenVisionRequest(
            instruction: "Describe the main visible subject in one short sentence.",
            image: image, maximumResponseTokens: 96,
        ))
        #expect(!response.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
    }

    @Test
    func `Input capabilities are absent before validation and after clear`() async throws {
        let runtime = QwenInferenceRuntime()
        #expect(await runtime.inputCapabilities() == nil)
        await runtime.clear()
        #expect(await runtime.inputCapabilities() == nil)
        let bundle = try makeQwenBundle(kind: "vlm")
        defer { try? FileManager.default.removeItem(at: bundle) }
        let metadataURL = bundle.appendingPathComponent("metadata.json")
        let original = try Data(contentsOf: metadataURL)
        let document = try #require(JSONSerialization.jsonObject(with: original) as? [String: Any])
        for invalidVision in [
            ["image_size": 0, "patch_size": 14, "image_token_count": 256, "image_token_id": 151_655],
            ["image_size": 448, "patch_size": 14, "image_token_count": 256,
             "image_token_id": 151_655, "image_std": [0, 1, 1]],
            ["image_size": 448, "patch_size": 14, "image_token_count": 256,
             "image_token_id": 151_655, "image_mean": [0, 1]],
        ] as [[String: Any]] {
            var invalid = document
            invalid["vision"] = invalidVision
            try JSONSerialization.data(withJSONObject: invalid).write(to: metadataURL)
            #expect(await runtime.validate(url: bundle).isAvailable)
            let capabilities = try #require(await runtime.inputCapabilities())
            #expect(capabilities.configuredEncoderSide == nil)
            #expect(capabilities.geometryInspectionFailure != nil)
        }
        try original.write(to: metadataURL)
        #expect(await runtime.validate(url: bundle).isAvailable)
        #expect(await runtime.inputCapabilities()?.configuredEncoderSide == 448)
        await runtime.clear()
        #expect(await runtime.inputCapabilities() == nil)
        _ = await runtime.validate(url: URL(fileURLWithPath: "/nonexistent/rawcull-qwen"))
        #expect(await runtime.inputCapabilities() == nil)
    }

    @Test
    func `Qwen generation gate serializes and cancels queued work`() async throws {
        let gate = QwenGenerationGate()
        try await gate.acquire()
        let probe = GateProbe()
        let second = Task {
            try await gate.acquire()
            await probe.markEntered()
            await gate.release()
        }
        try await Task.sleep(for: .milliseconds(40))
        #expect(await !(probe.entered))
        await gate.release()
        try await second.value
        #expect(await probe.entered)

        try await gate.acquire()
        let queued = Task { try await gate.acquire() }
        queued.cancel()
        await #expect(throws: CancellationError.self) { try await queued.value }
        await gate.release()
        try await gate.acquire()
        await gate.release()
    }

    @Test
    func `Assessment instruction keeps the existing schema`() {
        let instruction = QwenInferenceRuntime.assessmentInstruction(criteria: "Is the bird sharp?")
        #expect(instruction.contains("Analyze this photograph and answer the user's request:"))
        #expect(instruction.contains("Is the bird sharp?"))
        #expect(instruction.contains("\"compositionScore\": 1-5"))
        #expect(instruction.contains("\"subjectVisibilityScore\": 1-5"))
        #expect(instruction.contains("answer it normally in plain text"))
    }

    @Test
    func `General Qwen request rejects an invalid token cap`() async throws {
        let image = try #require(CGContext(
            data: nil, width: 1, height: 1, bitsPerComponent: 8,
            bytesPerRow: 4, space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue,
        )?.makeImage())
        let runtime = QwenInferenceRuntime()
        await #expect(throws: QwenModelError.self) {
            try await runtime.respond(to: QwenVisionRequest(
                instruction: "Describe the bird", image: image, maximumResponseTokens: 0,
            ))
        }
    }

    @Test
    func `Structured assessment decodes JSON wrapped in model prose`() throws {
        let response = """
        ```json
        {
          "subject": "bird on a branch",
          "compositionScore": 4,
          "exposureScore": 5,
          "subjectVisibilityScore": 3,
          "eyesOpen": true,
          "problems": ["branch crosses tail"],
          "strengths": ["clean background"],
          "confidence": 0.8
        }
        ```
        """

        let assessment = try QwenPhotoAssessment.decodeResponse(response)

        #expect(assessment.subject == "bird on a branch")
        #expect(assessment.compositionScore == 4)
        #expect(assessment.eyesOpen == true)
        #expect(assessment.overallScore > 0.7)
    }

    @Test
    func `Structured assessment rejects scores outside the schema`() {
        let response = #"{"subject":"bird","compositionScore":7,"exposureScore":5,"subjectVisibilityScore":3,"eyesOpen":null,"problems":[],"strengths":[],"confidence":0.8}"#

        #expect(throws: QwenModelError.self) {
            try QwenPhotoAssessment.decodeResponse(response)
        }
    }

    @Test
    func `Free-form Qwen response counts as a successful result`() {
        let result = QwenPhotoAnalysisResult(
            fileID: UUID(),
            fileName: "photo.ARW",
            assessment: nil,
            freeformResponse: "The bird appears to be a black grouse.",
            failure: nil,
        )

        #expect(result.isSuccessful)
    }

    @Test
    func `Response decoder preserves nonempty Qwen prose`() throws {
        let response = try QwenModelResponse.decode(
            "  The image is sharp and the subject is clearly visible.  ",
        )

        #expect(response == .freeform("The image is sharp and the subject is clearly visible."))
    }

    @Test
    func `Response decoder uses structured assessment when valid`() throws {
        let content = #"{"subject":"bird","compositionScore":4,"exposureScore":5,"subjectVisibilityScore":3,"eyesOpen":null,"problems":[],"strengths":["clean background"],"confidence":0.8}"#

        let response = try QwenModelResponse.decode(content)

        guard case let .structured(assessment) = response else {
            Issue.record("Expected a structured assessment")
            return
        }
        #expect(assessment.subject == "bird")
        #expect(assessment.compositionScore == 4)
    }

    @Test
    func `Response decoder preserves invalid structured output as freeform`() throws {
        let content = #"{"subject":"bird","compositionScore":7}"#

        let response = try QwenModelResponse.decode(content)

        #expect(response == .freeform(content))
    }

    @Test
    func `Response decoder rejects an empty Qwen response`() {
        #expect(throws: QwenModelError.self) {
            try QwenModelResponse.decode("  \n  ")
        }
    }

    @Test
    func `Qwen inference runtime validates a compatible Core AI bundle`() async throws {
        let bundle = try makeQwenBundle(kind: "vlm")
        defer { try? FileManager.default.removeItem(at: bundle) }

        let runtime = QwenInferenceRuntime()
        let status = await runtime.validate(url: bundle)
        let serving: any QwenInferenceServing = runtime
        let capabilities = try #require(await serving.inputCapabilities())
        #expect(await runtime.inputCapabilities() == capabilities)
        #expect(capabilities.configuredEncoderSide == 448)
        #expect(capabilities.configuredImageStrategy == "stretch")
        #expect(capabilities.configuredImageTokens == 256)
        #expect(capabilities.maximumContextTokens == 40960)
        #expect(capabilities.metadataSHA256?.count == 64)
        #expect(capabilities.imageMean?.count == 3)
        #expect(capabilities.geometryInspectionFailure == nil)
        #expect(!capabilities.encoderGeometryVerified)

        guard case let .available(url, modelName) = status else {
            Issue.record("Expected the Qwen model bundle to validate, got \(status)")
            return
        }
        #expect(url.standardizedFileURL == bundle.standardizedFileURL)
        #expect(modelName == "qwen3_4b_test")
    }

    @Test
    func `Qwen inference runtime rejects a text-only Qwen model`() async throws {
        let bundle = try makeQwenBundle()
        defer { try? FileManager.default.removeItem(at: bundle) }

        let status = await QwenInferenceRuntime().validate(url: bundle)

        guard case let .invalid(_, reason) = status else {
            Issue.record("Expected the text-only Qwen model to be rejected, got \(status)")
            return
        }
        #expect(reason.contains("text-only"))
    }

    @MainActor
    @Test
    func `Analysis keeps prior results and only processes newly selected files`() async {
        let inference = QwenInferenceStub()
        let feature = RawCullQwenAnalysisFeature(
            inference: inference,
            imageLoader: QwenImageLoaderStub(),
        )
        feature.updateModelStatus(.available(
            url: URL(fileURLWithPath: "/tmp/qwen"),
            modelName: "Qwen Test",
        ))
        let first = makeFile(name: "first.ARW")
        let second = makeFile(name: "second.ARW")

        await feature.analyze([first])
        await feature.analyze([first, second])

        #expect(feature.results.map(\.fileID) == [first.id, second.id])
        #expect(feature.filesNeedingAnalysis(from: [first, second]).isEmpty)
        #expect(await inference.assessmentCount() == 2)
    }

    @MainActor
    @Test
    func `Batch retains catalog access for later files after navigation`() async {
        let model = makeRawCullViewModel()
        let folder = "qwen-grant-" + UUID().uuidString
        let root = URL(filePath: "/tmp/" + folder).standardizedFileURL
        let started = CatalogTestGate()
        let release = CatalogTestGate()
        var stops: [URL] = []
        var reads = 0
        model.startSecurityScopedResource = { _ in true }
        model.stopSecurityScopedResource = { stops.append($0) }
        #expect(model.startSecurityScopedAccess(for: root))
        let feature = RawCullQwenAnalysisFeature(
            inference: QwenInferenceStub(),
            imageLoader: QwenImageLoaderStub(beforeRead: { url in
                await MainActor.run {
                    #expect(stops.isEmpty)
                    #expect(RawCullCatalogAccess.shared.retainAccess(for: [url]).count == 1)
                    reads += 1
                    started.open()
                }
                await release.wait()
            }),
        )
        feature.updateModelStatus(.available(url: URL(filePath: "/tmp/qwen"), modelName: "Test"))
        let files = [makeFile(name: folder + "/first.ARW"), makeFile(name: folder + "/second.ARW")]
        let task = Task { await feature.analyze(files) }
        await started.wait()
        model.stopActiveSecurityScopedAccess()
        #expect(stops.isEmpty)
        #expect(!model.hasActiveSecurityScopedAccess(for: root))
        release.open()
        await task.value
        #expect(reads == 2)
        #expect(feature.results.allSatisfy { $0.isSuccessful })
        #expect(stops == [root])
        #expect(RawCullCatalogAccess.shared.retainAccess(for: [root]).isEmpty)
    }

    private func makeQwenBundle(
        tokenizer: String = "Qwen/Qwen3-4B",
        kind: String = "llm",
    ) throws -> URL {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("RawCullQwenTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(
            at: root.appendingPathComponent("tokenizer", isDirectory: true),
            withIntermediateDirectories: true,
        )
        try Data().write(to: root.appendingPathComponent("qwen.aimodelc"))
        if kind == "vlm" {
            try Data().write(to: root.appendingPathComponent("embedding.aimodelc"))
            try Data().write(to: root.appendingPathComponent("vision.aimodelc"))
        }
        try Data("{}".utf8).write(to: root.appendingPathComponent("tokenizer/tokenizer.json"))
        try Data("{}".utf8).write(to: root.appendingPathComponent("tokenizer/tokenizer_config.json"))
        let metadata = """
        {
          "metadata_version": "0.2",
          "kind": "\(kind)",
          "name": "qwen3_4b_test",
          "assets": {
            "main": "qwen.aimodelc",
            "embedding": "embedding.aimodelc",
            "vision": "vision.aimodelc"
          },
          "vision": {
            "image_size": 448,
            "patch_size": 14,
            "image_token_count": 256,
            "image_token_id": 151655
          },
          "language": {
            "tokenizer": "\(tokenizer)",
            "vocab_size": 151936,
            "max_context_length": 40960,
            "embedded_tokenizer": true,
            "function_map": { "main": ["main"] }
          },
          "source": { "hf_model_id": "\(tokenizer)" }
        }
        """
        try Data(metadata.utf8).write(to: root.appendingPathComponent("metadata.json"))
        return root
    }

    @Test @MainActor
    func `arbitration waits for workers cancelled before the combined run`() async throws {
        let gate = QwenDrainProbe()
        let feature = RawCullQwenAnalysisFeature(inference: QwenInferenceStub(), imageLoader: QwenImageLoaderStub(beforeRead: { _ in await gate.park() }))
        feature.updateModelStatus(.available(url: URL(fileURLWithPath: "/tmp/model"), modelName: "Test"))
        let analysis = Task { await feature.analyze([makeFile(name: "draining.jpg")]) }
        for _ in 0 ..< 200 {
            if await gate.entered {
                break
            }
            try await Task.sleep(for: .milliseconds(10))
        }
        try #require(await gate.entered)
        feature.cancel()
        var finished = false
        let drain = Task { await feature.cancelAndWait(); finished = true }
        try await Task.sleep(for: .milliseconds(20))
        #expect(!finished)
        await gate.release()
        await drain.value; await analysis.value
        #expect(finished)
    }

    private func makeFile(name: String) -> FileItem {
        FileItem(
            id: UUID(),
            url: URL(fileURLWithPath: "/tmp/\(name)"),
            name: name,
            size: 1,
            dateModified: .distantPast,
            exifData: nil,
            afFocusNormalized: nil,
        )
    }
}

private actor GateProbe {
    private(set) var entered = false
    func markEntered() {
        entered = true
    }
}

private actor QwenInferenceStub: QwenInferenceServing {
    private var count = 0

    func validate(url: URL) -> QwenModelStatus {
        .available(url: url, modelName: "Qwen Test")
    }

    func assess(criteria _: String, image _: CGImage) -> QwenModelResponse {
        count += 1
        return .freeform("Completed")
    }

    func respond(to _: QwenVisionRequest) -> String {
        "Completed"
    }

    func clear() {}

    func assessmentCount() -> Int {
        count
    }
}

private struct QwenImageLoaderStub: RawImageLoading {
    var beforeRead: @Sendable (URL) async -> Void = { _ in }
    func fileMetadata(for _: URL) async -> RawImageFileMetadata? {
        nil
    }

    func thumbnailCGImage(for url: URL, maxPixelSize _: Int) async -> CGImage? {
        await beforeRead(url)
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        return CGContext(
            data: nil,
            width: 1,
            height: 1,
            bitsPerComponent: 8,
            bytesPerRow: 4,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue,
        )?.makeImage()
    }

    func thumbnailImage(for _: URL, maxPixelSize _: Int) async -> NSImage? {
        nil
    }

    func previewCGImage(for _: URL) async -> CGImage? {
        nil
    }

    func embeddedPreviewJPEGData(
        for _: URL,
        matchingPixelWidth _: Int,
        height _: Int,
    ) async -> Data? {
        nil
    }
}

private actor QwenDrainProbe {
    var entered = false
    private var continuation: CheckedContinuation<Void, Never>?
    func park() async {
        await withCheckedContinuation { entered = true; continuation = $0 }
    }

    func release() {
        continuation?.resume(); continuation = nil
    }
}
