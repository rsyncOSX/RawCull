import CoreAIImageSegmenter
import CoreGraphics
import Foundation
import PhotoAIContracts

// The package runtime does not yet declare these types Sendable. They never
// leave CoreAISAM3Provider's actor isolation. Recheck this when updating the
// pinned coreai-models revision and remove the conformances when upstream does.
extension ImageSegmenter: @retroactive @unchecked Sendable {}
extension CoreAISegmentationEngine: @retroactive @unchecked Sendable {}

/// Actor-owned Core AI SAM3 runtime. The host supplies the model bundle URL.
public actor CoreAISAM3Provider: SubjectSegmenting {
    public nonisolated let modelIdentity: ModelIdentity

    public nonisolated static let resourceDescriptor = ModelResourceDescriptor.sam3

    public nonisolated static var factory: ModelProviderFactory<CoreAISAM3Provider> {
        ModelProviderFactory(descriptor: resourceDescriptor) { url in
            try CoreAISAM3Provider(modelBundleURL: url)
        }
    }

    private let modelBundleURL: URL
    private let runtimeResourcesURL: URL
    private var model: LoadedSAM3Model?
    private nonisolated static let maskThreshold: Float = 0.5

    public init(modelBundleURL: URL) throws {
        let runtimeResourcesURL = try Self.resourcesURLForImageSegmenter(modelBundleURL)
        let resolver = ModelBundleResolver(descriptor: Self.resourceDescriptor.bundleDescriptor)
        guard case let .valid(_, identity) = resolver.status(at: runtimeResourcesURL) else {
            throw SAM3ProviderError.invalidModelBundle(resolver.status(at: runtimeResourcesURL))
        }
        self.modelBundleURL = modelBundleURL
        self.runtimeResourcesURL = runtimeResourcesURL
        self.modelIdentity = identity
    }

    public func segment(_ request: SubjectSegmentationRequest) async throws -> SubjectSegmentationResult {
        let totalStart = CFAbsoluteTimeGetCurrent()
        guard !Task.isCancelled else { throw SubjectSegmentationError.cancelled }
        let model = try await loadModel()

        let output: SegmentationOutput
        do {
            let tokens = model.tokenizer.encode(
                request.prompt.query,
                contextLength: model.parameters.tokenizerContextLength
            )
            output = try await model.engine.segment(
                image: request.image,
                textQuery: .tokens([tokens]),
                parameters: model.parameters
            )
        } catch is CancellationError {
            throw SubjectSegmentationError.cancelled
        } catch {
            throw SubjectSegmentationError.providerFailure(Self.message(for: error))
        }
        guard !Task.isCancelled else { throw SubjectSegmentationError.cancelled }

        let decoded = try Self.makeMaskImage(
            from: output,
            outputSize: request.inputSize,
            threshold: model.parameters.maskThreshold
        )
        let timing = SubjectSegmentationTiming(
            totalMilliseconds: (CFAbsoluteTimeGetCurrent() - totalStart) * 1_000
        )
        let outputSize = CGSize(width: decoded.mask.width, height: decoded.mask.height)
        let diagnostics = SubjectSegmentationDiagnostics(
            modelIdentity: modelIdentity,
            prompt: request.prompt,
            confidence: decoded.score,
            timing: timing,
            inputSize: request.inputSize,
            outputSize: outputSize,
            resourceName: modelBundleURL.lastPathComponent,
            assetName: modelIdentity.assetName
        )
        return SubjectSegmentationResult(
            sourceID: request.sourceID,
            requestID: request.requestID,
            prompt: request.prompt,
            mask: decoded.mask,
            confidence: decoded.score,
            modelIdentity: modelIdentity,
            inputSize: request.inputSize,
            outputSize: outputSize,
            timing: timing,
            diagnostics: diagnostics
        )
    }

    private func loadModel() async throws -> LoadedSAM3Model {
        if let model { return model }

        do {
            let assetName = ModelBundleResolver(descriptor: Self.resourceDescriptor.bundleDescriptor)
                .identity(at: runtimeResourcesURL)?.assetName ?? modelIdentity.assetName
            let tokenizer = try CLIPTokenizer(
                folder: runtimeResourcesURL.appendingPathComponent("tokenizer", isDirectory: true)
            )
            let parameters = SegmentationParameters(maskThreshold: Self.maskThreshold, maxSegments: 5)
            let engine = try await CoreAISegmentationEngine(
                parameters: parameters,
                modelURL: runtimeResourcesURL.appendingPathComponent(assetName)
            )
            let loaded = LoadedSAM3Model(engine: engine, tokenizer: tokenizer, parameters: parameters)
            model = loaded
            return loaded
        } catch {
            throw SAM3ProviderError.modelLoad(Self.message(for: error))
        }
    }

    /// Adapts a flat exporter bundle to the nested tokenizer layout required by coreai-models.
    public nonisolated static func resourcesURLForImageSegmenter(_ resourcesURL: URL) throws -> URL {
        let fileManager = FileManager.default
        let nestedTokenizerURL = resourcesURL.appendingPathComponent("tokenizer/tokenizer.json")
        if fileManager.fileExists(atPath: nestedTokenizerURL.path) { return resourcesURL }

        let flatTokenizerURL = resourcesURL.appendingPathComponent("tokenizer.json")
        guard fileManager.fileExists(atPath: flatTokenizerURL.path),
              let metadataData = try? Data(contentsOf: resourcesURL.appendingPathComponent("metadata.json")),
              let metadata = try? JSONDecoder().decode(ModelBundleMetadata.self, from: metadataData),
              let assetName = metadata.assets["main"]
        else { return resourcesURL }

        let assetURL = resourcesURL.appendingPathComponent(assetName)
        guard fileManager.fileExists(atPath: assetURL.path) else { return resourcesURL }

        let shimURL = fileManager.temporaryDirectory
            .appendingPathComponent("PhotoAIKit", isDirectory: true)
            .appendingPathComponent("CoreAISAM3Bundle-\(UUID().uuidString)", isDirectory: true)
        try fileManager.createDirectory(
            at: shimURL.appendingPathComponent("tokenizer", isDirectory: true),
            withIntermediateDirectories: true
        )
        try fileManager.copyItem(
            at: resourcesURL.appendingPathComponent("metadata.json"),
            to: shimURL.appendingPathComponent("metadata.json")
        )
        try fileManager.copyItem(
            at: flatTokenizerURL,
            to: shimURL.appendingPathComponent("tokenizer/tokenizer.json")
        )
        let configURL = resourcesURL.appendingPathComponent("tokenizer_config.json")
        if fileManager.fileExists(atPath: configURL.path) {
            try fileManager.copyItem(
                at: configURL,
                to: shimURL.appendingPathComponent("tokenizer/tokenizer_config.json")
            )
        }
        try fileManager.createSymbolicLink(
            at: shimURL.appendingPathComponent(assetName),
            withDestinationURL: assetURL
        )
        return shimURL
    }

    private nonisolated static func message(for error: Error) -> String {
        let description = error.localizedDescription.trimmingCharacters(in: .whitespacesAndNewlines)
        if !description.isEmpty,
           description != "The operation couldn’t be completed. (Swift.Error error 1.)" {
            return description
        }
        return String(reflecting: error)
    }

    private struct LoadedSAM3Model {
        let engine: CoreAISegmentationEngine
        let tokenizer: CLIPTokenizer
        let parameters: SegmentationParameters
    }

    private nonisolated struct DecodedMask {
        let mask: CGImage
        let score: Float
    }

    private nonisolated static func makeMaskImage(
        from output: SegmentationOutput,
        outputSize: CGSize,
        threshold: Float
    ) throws -> DecodedMask {
        let shape = output.masksShape
        guard shape.count >= 4 else { throw SubjectSegmentationError.noMask }
        let batchIndex = 0
        let queryCount = shape[1]
        let sourceHeight = shape[2]
        let sourceWidth = shape[3]
        let pixelsPerQuery = sourceWidth * sourceHeight
        let width = Int(outputSize.width.rounded())
        let height = Int(outputSize.height.rounded())
        guard queryCount > 0, sourceWidth > 0, sourceHeight > 0, width > 0, height > 0,
              output.predictedMasks.count >= (batchIndex + 1) * queryCount * pixelsPerQuery
        else { throw SubjectSegmentationError.decodeFailure }

        guard let bestQuery = bestQueryIndex(
            output: output,
            batchIndex: batchIndex,
            queryCount: queryCount
        ) else { throw SubjectSegmentationError.noMask }

        let maskBase = (batchIndex * queryCount + bestQuery.index) * pixelsPerQuery
        let lowResolutionMask = output.predictedMasks[maskBase ..< maskBase + pixelsPerQuery].map(sigmoid)
        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        fillBilinearMaskPixels(
            source: lowResolutionMask,
            sourceWidth: sourceWidth,
            sourceHeight: sourceHeight,
            threshold: threshold,
            pixels: &pixels,
            width: width,
            height: height
        )
        guard let provider = CGDataProvider(data: Data(pixels) as CFData),
              let image = CGImage(
                  width: width,
                  height: height,
                  bitsPerComponent: 8,
                  bitsPerPixel: 32,
                  bytesPerRow: width * 4,
                  space: CGColorSpaceCreateDeviceRGB(),
                  bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
                  provider: provider,
                  decode: nil,
                  shouldInterpolate: true,
                  intent: .defaultIntent
              )
        else { throw SubjectSegmentationError.decodeFailure }
        return DecodedMask(mask: image, score: bestQuery.score)
    }

    private nonisolated static func bestQueryIndex(
        output: SegmentationOutput,
        batchIndex: Int,
        queryCount: Int
    ) -> (index: Int, score: Float)? {
        let useDirectScores = !output.predictedScores.isEmpty
        guard useDirectScores || output.predictedLogits.count >= (batchIndex + 1) * queryCount else {
            return nil
        }
        if useDirectScores, output.predictedScores.count < (batchIndex + 1) * queryCount { return nil }
        let presenceScore = output.presenceLogits.count > batchIndex
            ? sigmoid(output.presenceLogits[batchIndex]) : 1
        var best: (index: Int, score: Float)?
        for queryIndex in 0 ..< queryCount {
            let index = batchIndex * queryCount + queryIndex
            let score = useDirectScores
                ? output.predictedScores[index]
                : sigmoid(output.predictedLogits[index]) * presenceScore
            if best == nil || score > best!.score { best = (queryIndex, score) }
        }
        return best
    }

    private nonisolated static func fillBilinearMaskPixels(
        source: [Float],
        sourceWidth: Int,
        sourceHeight: Int,
        threshold: Float,
        pixels: inout [UInt8],
        width: Int,
        height: Int
    ) {
        let scaleX = Float(sourceWidth) / Float(width)
        let scaleY = Float(sourceHeight) / Float(height)
        let feather: Float = 0.055
        let edge0 = threshold - feather
        let edge1 = threshold + feather

        pixels.withUnsafeMutableBufferPointer { buffer in
            guard let baseAddress = buffer.baseAddress else { return }
            for y in 0 ..< height {
                let sourceY = max(0, min(Float(sourceHeight - 1), (Float(y) + 0.5) * scaleY - 0.5))
                let y0 = Int(sourceY.rounded(.down))
                let y1 = min(y0 + 1, sourceHeight - 1)
                let yWeight = sourceY - Float(y0)
                for x in 0 ..< width {
                    let sourceX = max(0, min(Float(sourceWidth - 1), (Float(x) + 0.5) * scaleX - 0.5))
                    let x0 = Int(sourceX.rounded(.down))
                    let x1 = min(x0 + 1, sourceWidth - 1)
                    let xWeight = sourceX - Float(x0)
                    let top = source[y0 * sourceWidth + x0] * (1 - xWeight)
                        + source[y0 * sourceWidth + x1] * xWeight
                    let bottom = source[y1 * sourceWidth + x0] * (1 - xWeight)
                        + source[y1 * sourceWidth + x1] * xWeight
                    let probability = top * (1 - yWeight) + bottom * yWeight
                    let alpha = smoothMaskAlpha(probability, edge0: edge0, edge1: edge1)
                    guard alpha > 0 else { continue }
                    let offset = (y * width + x) * 4
                    baseAddress[offset] = 255
                    baseAddress[offset + 1] = 255
                    baseAddress[offset + 2] = 255
                    baseAddress[offset + 3] = alpha
                }
            }
        }
    }

    private nonisolated static func smoothMaskAlpha(
        _ value: Float,
        edge0: Float,
        edge1: Float
    ) -> UInt8 {
        let clamped = max(0, min(1, (value - edge0) / (edge1 - edge0)))
        let smoothed = clamped * clamped * (3 - 2 * clamped)
        return UInt8(max(0, min(255, Int((smoothed * 255).rounded()))))
    }

    private nonisolated static func sigmoid(_ value: Float) -> Float { 1 / (1 + exp(-value)) }
}

public enum SAM3ProviderError: Error, CustomStringConvertible, Sendable {
    case invalidModelBundle(ModelBundleStatus)
    case resourceSetup(String)
    case modelLoad(String)

    public var description: String {
        switch self {
        case let .invalidModelBundle(status): "Invalid SAM3 model bundle: \(status)"
        case let .resourceSetup(message): "SAM3 resource setup failed: \(message)"
        case let .modelLoad(message): "SAM3 model load failed: \(message)"
        }
    }
}

public extension ModelBundleDescriptor {
    static let sam3 = ModelBundleDescriptor(
        family: ModelResourceDescriptor.sam3.bundleDescriptor.family,
        fallbackName: ModelResourceDescriptor.sam3.bundleDescriptor.fallbackName,
        assetKey: ModelResourceDescriptor.sam3.bundleDescriptor.assetKey,
        requiredRelativePaths: ModelResourceDescriptor.sam3.bundleDescriptor.requiredRelativePaths,
        acceptedAssetExtensions: ModelResourceDescriptor.sam3.bundleDescriptor.acceptedAssetExtensions
    )
}
