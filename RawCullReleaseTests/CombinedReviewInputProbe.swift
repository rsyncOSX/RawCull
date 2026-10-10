// Opt-in hostless probes. Debug enables access to the pinned dependency's exact
// preprocessing function; no source copies or dependency modifications are used.
#if DEBUG
    import CoreAI
    @testable import CoreAICLIPBackend
    @testable import CoreAILanguageModels
    import CoreAIQwenBackend
    import CoreAIShared
    import CoreGraphics
    import CryptoKit
    import Foundation
    import FoundationModels
    import ImageIO
    import PhotoAIContracts
    import Testing
    import UniformTypeIdentifiers

    @Suite("Combined Review input contract")
    struct CombinedReviewInputProbe {
        @Test func `orientation fixtures preserve corner identity`() throws {
            for fixture in InputFixture.cases {
                let image = try fixture.decodedImage()
                let rotated = fixture.orientation >= 5
                try #require(image.width == (rotated ? fixture.height : fixture.width))
                try #require(image.height == (rotated ? fixture.width : fixture.height))
                let pixels = try InputFixture.rgba(image)
                // EXIF transforms, in displayed top-left, top-right, bottom-left, bottom-right order.
                let expected = [
                    [0, 1, 2, 3], [1, 0, 3, 2], [3, 2, 1, 0], [2, 3, 0, 1],
                    [0, 2, 1, 3], [2, 0, 3, 1], [3, 1, 2, 0], [1, 3, 0, 2]
                ][fixture.orientation - 1]
                let points = [(0.05, 0.05), (0.95, 0.05), (0.05, 0.95), (0.95, 0.95)]
                for (index, point) in points.enumerated() {
                    let x = min(image.width - 1, Int(point.0 * Double(image.width)))
                    let y = min(image.height - 1, Int(point.1 * Double(image.height)))
                    let color = InputFixture.colors[expected[index]]
                    for channel in 0 ..< 3 {
                        try #require(abs(Int(pixels[(y * image.width + x) * 4 + channel]) - Int(color[channel])) <= 2)
                    }
                }
            }
        }

        @Test(.enabled(if: ProcessInfo.processInfo.environment["RAWCULL_INPUT_PROBE_RUN"] == "1"))
        func `verify installed inputs`() async throws {
            let environment = ProcessInfo.processInfo.environment
            let root = try URL(fileURLWithPath: #require(environment["RAWCULL_INPUT_PROBE_MODELS"]))
            let output = try URL(fileURLWithPath: #require(environment["RAWCULL_INPUT_PROBE_OUTPUT"]))
            let repository = try URL(fileURLWithPath: #require(environment["RAWCULL_INPUT_PROBE_REPOSITORY"]))
            try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
            var report = try InputProbeReport(
                schemaVersion: 1, operatingSystem: ProcessInfo.processInfo.operatingSystemVersionString,
                hardware: "arm64",
                dependencies: JSONSerialization.jsonObject(with: Data(contentsOf: repository
                        .appendingPathComponent("RawCull.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved")))
                    as? [String: Any] ?? [:],
            )
            try report.write(to: output.appendingPathComponent("input-contract.json"))
            // Partial failures remain visible, with no successful gate decision.
            do {
                let qwenURL = root.appendingPathComponent("Qwen/qwen3_vl_2b")
                print("Input probe: inspecting Qwen")
                try await inspectQwen(at: qwenURL, output: output, report: &report)
                try report.write(to: output.appendingPathComponent("input-contract.json"))
                for name in ["CLIP-OpenAI", "CLIP-DataComp"] {
                    print("Input probe: inspecting \(name)")
                    try await inspectCLIP(at: root.appendingPathComponent(name), name: name,
                                          output: output, report: &report)
                    try report.write(to: output.appendingPathComponent("input-contract.json"))
                }
                report.status = "passed"
            } catch {
                report.status = "failed"
                report.failure = String(describing: error)
                try report.write(to: output.appendingPathComponent("input-contract.json"))
                throw error
            }
            try report.write(to: output.appendingPathComponent("input-contract.json"))
        }

        private func inspectQwen(at url: URL, output: URL, report: inout InputProbeReport) async throws {
            let provider = try CoreAIQwenProvider(modelBundleURL: url)
            let capabilities = QwenInputCapabilities.inspect(provider: provider, bundleURL: url)
            let bundle = try LanguageModelBundle(at: url)
            let vision = try #require(bundle.visionConfig)
            let metadata = try #require(JSONSerialization.jsonObject(with: Data(contentsOf:
                url.appendingPathComponent("metadata.json"))) as? [String: Any])
            let assets = try #require(metadata["assets"] as? [String: String])
            let model = try await AIModel(contentsOf: url.appendingPathComponent(#require(assets["vision"])))
            let functionName = model.functionDescriptor(for: "encode_image") != nil ? "encode_image" : "main"
            let function = try #require(model.functionDescriptor(for: functionName))
            let inputName = try #require(function.inputNames.first)
            guard case let .ndArray(inputDescriptor) = function.inputDescriptor(of: inputName) else {
                throw InputProbeError.message("Qwen vision input is not an NDArray")
            }
            let expected = [1, 3, vision.imageSize, vision.imageSize]
            try #require(inputDescriptor.shape == expected)
            try #require(inputDescriptor.scalarType == .float32)
            let preprocessor = ImagePreprocessor(
                targetSize: CGSize(width: vision.imageSize, height: vision.imageSize),
                mean: (vision.imageMean[0], vision.imageMean[1], vision.imageMean[2]),
                std: (vision.imageStd[0], vision.imageStd[1], vision.imageStd[2]),
                rescaleFactor: vision.rescaleFactor,
            )
            // Loads the exact engine used by RawCull; verifies end-to-end image encoding.
            let vlm = try await provider.makeVisionLanguageModel()
            let engine = vlm.executorConfiguration.engine
            var traces: [[String: Any]] = []
            for fixture in InputFixture.cases {
                try Task.checkCancellation()
                let image = try fixture.decodedImage()
                let values = try preprocessor.preprocessCHW(cgImage: image, strategy: vision.imageStrategy)
                try #require(values.count == 3 * vision.imageSize * vision.imageSize)
                try #require(values.allSatisfy { $0.isFinite })
                let repeated = try preprocessor.preprocessCHW(cgImage: image, strategy: vision.imageStrategy)
                try #require(values == repeated)
                let embedded = try await engine.encodeImage(cgImage: image)
                try #require(embedded.tokenCount == vision.imageTokenCount)
                try #require(embedded.embeddings.shape[1] == vision.imageTokenCount)
                // These installed assets use stretch; marker and circle assertions detect
                // accidental center cropping, channel swaps, or orientation loss.
                try #require(vision.imageStrategy == .stretch)
                try fixture.assertStretchedMarkers(values, side: vision.imageSize,
                                                   mean: vision.imageMean, std: vision.imageStd)
                let imageName = "qwen-\(fixture.name).png"
                try InputFixture.save(values: values, width: vision.imageSize, height: vision.imageSize,
                                      mean: vision.imageMean, std: vision.imageStd,
                                      rescale: vision.rescaleFactor, to: output.appendingPathComponent(imageName))
                try InputFixture.writePNG(image, to: output.appendingPathComponent("source-\(fixture.name).png"))
                var trace = fixture.trace(image: image, encoderWidth: vision.imageSize,
                                          encoderHeight: vision.imageSize, centerCrop: false)
                trace["preprocessedFloatSHA256"] = InputFixture.hash(values)
                trace["exactInputPreview"] = imageName
                trace["projectedEmbeddingShape"] = embedded.embeddings.shape
                let region = InputFixture.detailRectangle(image)
                let detail = try #require(image.cropping(to: region))
                let detailValues = try preprocessor.preprocessCHW(cgImage: detail, strategy: vision.imageStrategy)
                try #require(detailValues.allSatisfy { $0.isFinite })
                let detailEmbedding = try await engine.encodeImage(cgImage: detail)
                try #require(detailEmbedding.tokenCount == vision.imageTokenCount)
                let detailName = "qwen-detail-\(fixture.name).png"
                try InputFixture.save(values: detailValues, width: vision.imageSize, height: vision.imageSize,
                                      mean: vision.imageMean, std: vision.imageStd, rescale: vision.rescaleFactor,
                                      to: output.appendingPathComponent(detailName))
                trace["sourceRegionProbe"] = InputFixture.detailTrace(region: region, image: detail,
                                                                      encoderSide: vision.imageSize, values: detailValues, preview: detailName)
                traces.append(trace)
            }
            let image = try InputFixture.cases[2].decodedImage()
            let response = try await LanguageModelSession(model: vlm).respond(
                options: GenerationOptions(maximumResponseTokens: 16),
            ) {
                Attachment(image)
                "Describe the visible geometric shapes briefly."
            }
            try #require(!response.content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            let shortProcessedTokens = engine.processedTokenCount
            let inputTokens = response.usage.input.totalTokenCount
            let outputTokens = response.usage.output.totalTokenCount
            try #require(inputTokens >= vision.imageTokenCount)
            try #require(outputTokens > 0 && outputTokens <= 16)
            try #require(inputTokens + outputTokens <= provider.configuration.maximumContextLength)
            try #require(shortProcessedTokens > vision.imageTokenCount)
            try #require(shortProcessedTokens <= provider.configuration.maximumContextLength)
            // Native generation iterator is bounded by remaining context, not just the
            // requested output limit. Test exact-edge and exhausted-context behavior.
            let context = provider.configuration.maximumContextLength
            try #require(SequentialIterator.clampMaxTokens(requested: 4096, forcedCount: nil,
                                                           inputCount: context - 1, maxContextLength: context) == 1)
            try #require(SequentialIterator.clampMaxTokens(requested: 16, forcedCount: nil,
                                                           inputCount: context, maxContextLength: context) == 0)
            try #require(SequentialIterator.clampMaxTokens(requested: 16, forcedCount: nil,
                                                           inputCount: context + 1, maxContextLength: context) == 0)
            // Exercise the actual Foundation Models adapter with an over-context prompt.
            print("Input probe: Qwen short response passed; testing exhausted context")
            let exhaustedContextOutcome: String
            do {
                let exhausted = try await LanguageModelSession(model: vlm).respond(
                    options: GenerationOptions(maximumResponseTokens: 16),
                ) {
                    Attachment(image)
                    String(repeating: " word", count: context + 100)
                }
                try #require(exhausted.content.isEmpty)
                exhaustedContextOutcome = "empty response"
            } catch {
                // On this OS, the Foundation Models session converts zero generated
                // tokens into a no-response error. Do not accept unrelated failures.
                try #require(String(describing: error).contains("Session ended without producing a response"))
                exhaustedContextOutcome = String(describing: error)
            }
            try #require(engine.processedTokenCount == 0)
            // RawCull's own response bounds are enforced even before a model is loaded.
            let runtime = QwenInferenceRuntime()
            for invalid in [0, 4097] {
                do {
                    _ = try await runtime.respond(to: QwenVisionRequest(
                        instruction: "Describe", image: image, maximumResponseTokens: invalid,
                    ))
                    throw InputProbeError.message("Invalid response limit was accepted")
                } catch QwenModelError.invalidTokenLimit {}
            }
            try report.models.append([
                "name": "Qwen", "bundleContentSHA256": InputFixture.bundleHash(url),
                "declaredCapabilities": InputFixture.json(capabilities),
                "visionFunction": functionName, "compiledInputName": inputName,
                "compiledInputShape": inputDescriptor.shape, "compiledInputScalar": "float32",
                "tensorLayout": "NCHW", "channelOrder": "RGB", "colorSpace": "sRGB",
                "fixtures": traces, "singleImageResponse": response.content,
                "shortRequestProcessedTokens": shortProcessedTokens,
                "shortRequestInputTokens": inputTokens,
                "shortRequestImageTokens": vision.imageTokenCount,
                "shortRequestInstructionAndTemplateTokens": inputTokens - vision.imageTokenCount,
                "shortRequestOutputTokens": outputTokens,
                "exhaustedContextOutcome": exhaustedContextOutcome,
                "exhaustedContextProcessedTokens": engine.processedTokenCount,
                "contextPolicy": "native clamp: min(requested, max(0, context - expanded prompt tokens))",
                "unknowns": ["alternate encoder shapes", "compression when absent from metadata"],
                "attachmentContract": "RawCull supplies one CGImage; pinned executor selects the first image attachment"
            ])
        }

        private func inspectCLIP(at url: URL, name: String, output: URL,
                                 report: inout InputProbeReport) async throws {
            let provider = try CoreAICLIPProvider(modelBundleURL: url)
            let configuration = provider.runtimeConfiguration
            let preprocessing = configuration.preprocessing
            let metadata = try JSONDecoder().decode(ModelBundleMetadata.self,
                                                    from: Data(contentsOf: url.appendingPathComponent("metadata.json")))
            let model = try await AIModel(contentsOf: url.appendingPathComponent(#require(metadata.assets["main"])))
            let imageFunction = try #require(model.functionDescriptor(for: configuration.imageFunctionName))
            let textFunction = try #require(model.functionDescriptor(for: configuration.textFunctionName))
            guard case let .ndArray(imageDescriptor) = imageFunction.inputDescriptor(of: "pixel_values"),
                  case let .ndArray(textDescriptor) = textFunction.inputDescriptor(of: "input_ids")
            else {
                throw InputProbeError.message("CLIP input descriptors missing")
            }
            try #require(imageDescriptor.shape == [1, 3, preprocessing.height, preprocessing.width])
            try #require(textDescriptor.shape == [1, configuration.tokenizer.contextLength])
            try #require(imageDescriptor.scalarType == .float32 || imageDescriptor.scalarType == .float16)
            let imageScalar = imageDescriptor.scalarType == .float16 ? "float16" : "float32"
            try #require(textDescriptor.scalarType == .int32)
            try #require(preprocessing.resize == "shortest-side" && preprocessing.crop == "center")
            var traces: [[String: Any]] = []
            for fixture in InputFixture.cases {
                try Task.checkCancellation()
                let image = try fixture.decodedImage()
                // Call the provider's exact internal implementation through testability.
                let values = try CoreAICLIPProvider.preprocessCLIPImage(image, preprocessing: preprocessing)
                try #require(values.count == 3 * preprocessing.width * preprocessing.height)
                try #require(values.allSatisfy { $0.isFinite })
                try #require(try values == (CoreAICLIPProvider.preprocessCLIPImage(image, preprocessing: preprocessing)))
                let mean = preprocessing.mean.map(Double.init)
                let std = preprocessing.standardDeviation.map(Double.init)
                try fixture.assertCenterCrop(values, side: preprocessing.width, mean: mean, std: std)
                let imageName = "\(name)-\(fixture.name).png"
                let boundValues = imageDescriptor.scalarType == .float16 ? values.map { Float(Float16($0)) } : values
                try #require(boundValues.allSatisfy { $0.isFinite })
                try InputFixture.save(values: boundValues, width: preprocessing.width, height: preprocessing.height,
                                      mean: mean, std: std, rescale: 1, to: output.appendingPathComponent(imageName))
                let first = try await provider.embedding(for: image)
                let second = try await provider.embedding(for: image)
                try #require(first.values.count == configuration.embeddingDimensions)
                try #require(first.values.allSatisfy { $0.isFinite })
                let norm = sqrt(first.values.reduce(0.0) { $0 + Double($1) * Double($1) })
                try #require(abs(norm - 1) < 0.001)
                let maxDifference = zip(first.values, second.values).map { abs($0 - $1) }.max() ?? 0
                try #require(maxDifference < 0.0001)
                // A source-space square crop additionally verifies the detailed-input path.
                let region = InputFixture.detailRectangle(image)
                let crop = try #require(image.cropping(to: region))
                let detailValues = try CoreAICLIPProvider.preprocessCLIPImage(crop, preprocessing: preprocessing)
                try #require(detailValues.allSatisfy { $0.isFinite })
                let detailName = "\(name)-detail-\(fixture.name).png"
                let boundDetail = imageDescriptor.scalarType == .float16 ? detailValues.map { Float(Float16($0)) } : detailValues
                try InputFixture.save(values: boundDetail, width: preprocessing.width, height: preprocessing.height,
                                      mean: mean, std: std, rescale: 1, to: output.appendingPathComponent(detailName))
                let cropEmbedding = try await provider.embedding(for: crop)
                try #require(cropEmbedding.values.allSatisfy { $0.isFinite })
                try #require(cropEmbedding.values.count == first.values.count)
                var trace = fixture.trace(image: image, encoderWidth: preprocessing.width,
                                          encoderHeight: preprocessing.height, centerCrop: true)
                trace["preprocessedFloatSHA256"] = InputFixture.hash(values)
                trace["exactInputPreview"] = imageName
                trace["boundTensorScalar"] = imageScalar
                trace["boundTensorSHA256"] = imageDescriptor.scalarType == .float16
                    ? InputFixture.halfHash(values) : InputFixture.hash(values)
                trace["embeddingDimensions"] = first.values.count
                trace["embeddingL2Norm"] = norm
                trace["repeatMaximumAbsoluteDifference"] = maxDifference
                var detailTrace = InputFixture.detailTrace(region: region, image: crop,
                                                           encoderSide: preprocessing.width, values: detailValues, preview: detailName)
                detailTrace["boundTensorScalar"] = imageScalar
                detailTrace["boundTensorSHA256"] = imageDescriptor.scalarType == .float16
                    ? InputFixture.halfHash(detailValues) : InputFixture.hash(detailValues)
                trace["sourceRegionProbe"] = detailTrace
                traces.append(trace)
            }
            let longText = String(repeating: "a photo of a circle ", count: 100)
            try #require(configuration.tokenizer.type == "clip-bpe")
            let tokenizer = try CoreAIClipTokenizer(folder: url.appendingPathComponent("tokenizer"))
            let truncated = tokenizer.encode(longText, contextLength: configuration.tokenizer.contextLength)
            let full = tokenizer.encode(longText, contextLength: 4096)
            try #require(truncated.count == configuration.tokenizer.contextLength)
            try #require(truncated.first == CoreAIClipTokenizer.sotTokenId)
            try #require(truncated.last == CoreAIClipTokenizer.eotTokenId)
            try #require(Array(truncated.dropLast()) == Array(full.prefix(truncated.count - 1)))
            let text = try await provider.embedding(for: longText)
            try #require(text.values.allSatisfy { $0.isFinite })
            try #require(text.values.count == configuration.embeddingDimensions)
            try report.models.append([
                "name": name, "bundleContentSHA256": InputFixture.bundleHash(url),
                "backend": InputFixture.json(provider.backendDescriptor),
                "declaredCapabilities": InputFixture.json(RawCullCLIPInputCapabilities(provider: provider)),
                "compiledImageShape": imageDescriptor.shape, "compiledImageScalar": imageScalar,
                "preprocessorScalar": "float32; converted to compiled input scalar before binding",
                "compiledTextShape": textDescriptor.shape, "compiledTextScalar": "int32",
                "preprocessing": InputFixture.json(preprocessing),
                "tokenizer": InputFixture.json(configuration.tokenizer),
                "embeddingDimensions": configuration.embeddingDimensions ?? 0,
                "normalizationVersion": configuration.normalizationVersion,
                "tensorLayout": "NCHW", "channelOrder": "RGB", "colorSpace": "sRGB",
                "textOverflowPolicy": "prefix truncation to context length; final slot is EOT",
                "fixtures": traces, "longTextEmbeddingFinite": true,
                "unknowns": ["vision patch/token count is not exposed by the provider", "alternate encoder shapes"]
            ])
        }
    }

    private struct InputProbeReport {
        let schemaVersion: Int
        let operatingSystem: String
        let hardware: String
        let dependencies: [String: Any]
        var status = "incomplete"
        var failure: String?
        var models: [[String: Any]] = []

        func write(to url: URL) throws {
            let document: [String: Any] = [
                "schemaVersion": schemaVersion, "status": status, "failure": failure ?? NSNull() as Any,
                "operatingSystem": operatingSystem, "hardwareArchitecture": hardware,
                "processorCount": ProcessInfo.processInfo.processorCount,
                "physicalMemoryBytes": ProcessInfo.processInfo.physicalMemory,
                "dependencies": dependencies, "models": models,
                "fingerprintAlgorithm": "bundle-tree-sha256-v1: sorted relative UTF8 path + NUL + file SHA256 hex + LF",
                "scope": "installed local bundles and pinned runtime; no alternate shapes are qualified",
                "previewPolicy": "PNG previews denormalize the bound tensor into sRGB; typed tensor hashes retain numeric identity. Regenerate numeric inputs with this probe."
            ]
            try JSONSerialization.data(withJSONObject: document, options: [.prettyPrinted, .sortedKeys])
                .write(to: url, options: .atomic)
        }
    }

    private enum InputProbeError: Error { case message(String) }
#endif
