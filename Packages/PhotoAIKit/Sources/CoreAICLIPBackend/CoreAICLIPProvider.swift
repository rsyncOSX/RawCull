import CoreAI
import CoreAIImageSegmenter
import CoreGraphics
import Foundation
import PhotoAIContracts

/// Actor-owned Core AI CLIP runtime. The host supplies the model bundle URL.
public actor CoreAICLIPProvider:
    ImageEmbeddingProviding,
    ImageSimilarityArtifactProviding,
    ImageSimilarityArtifactComparing,
    TextEmbeddingProviding,
    ImageTextSimilarityComparing
{
    public nonisolated let modelIdentity: ModelIdentity

    public nonisolated static let resourceDescriptor = ModelResourceDescriptor.clip
    public nonisolated static let tokenizerVersion = "clip-bpe-tokenizer-v1"

    public nonisolated static var factory: ModelProviderFactory<CoreAICLIPProvider> {
        ModelProviderFactory(descriptor: resourceDescriptor) { url in
            try CoreAICLIPProvider(modelBundleURL: url)
        }
    }

    public nonisolated var backendDescriptor: SimilarityBackendDescriptor {
        SimilarityBackendDescriptor(
            backend: "clip",
            modelFingerprint: modelIdentity.artifactIdentifier,
            representation: "normalized-float-vector-json-v1",
            preprocessingVersion: Self.resourceDescriptor.preprocessingVersion,
            normalizationVersion: "l2-v1",
            configurationVersion: Self.resourceDescriptor.configurationVersion
        )
    }

    private let modelBundleURL: URL
    private var loadedModel: LoadedCLIPModel?

    public init(modelBundleURL: URL) throws {
        let resolver = ModelBundleResolver(descriptor: Self.resourceDescriptor.bundleDescriptor)
        guard case let .valid(_, identity) = resolver.status(at: modelBundleURL) else {
            throw CLIPProviderError.invalidModelBundle(resolver.status(at: modelBundleURL))
        }
        self.modelBundleURL = modelBundleURL
        self.modelIdentity = identity
    }

    public func embedding(for image: CGImage) async throws -> ImageEmbedding {
        let model = try await loadModel()
        let values = try await imageEmbedding(for: image, model: model)
        return ImageEmbedding(
            backend: "clip",
            modelIdentity: modelIdentity,
            values: values
        )
    }

    public func embedding(for text: String) async throws -> TextEmbedding {
        try Task.checkCancellation()
        let model = try await loadModel()
        try Task.checkCancellation()

        let sequenceLength = model.inputIDsDescriptor.shape[1]
        let queryTokens = model.tokenizer.encode(text, contextLength: sequenceLength)
        let batch = try Self.makeTextBatch(
            queryTokens: queryTokens,
            fillerTokens: model.dummyTokens[0],
            batchSize: model.inputIDsDescriptor.shape[0],
            sequenceLength: sequenceLength
        )

        try Task.checkCancellation()
        let values = try await textEmbedding(for: batch, model: model)
        try Task.checkCancellation()

        do {
            return try TextEmbedding(
                descriptor: TextEmbeddingDescriptor(
                    backend: backendDescriptor,
                    dimensions: values.count,
                    tokenizerVersion: Self.tokenizerVersion
                ),
                values: values
            )
        } catch let error as TextEmbeddingValidationError {
            throw CLIPTextInferenceError.invalidEmbedding(error)
        }
    }

    public func artifact(
        for image: CGImage,
        source: AIImageSource
    ) async throws -> SimilarityArtifact {
        let embedding = try await embedding(for: image)
        return SimilarityArtifact(
            descriptor: SimilarityArtifactDescriptor(
                backend: backendDescriptor,
                dimensions: embedding.values.count,
                sourceFingerprint: SourceFingerprint(source: source)
            ),
            payload: try JSONEncoder().encode(embedding)
        )
    }

    public nonisolated func distance(
        from left: SimilarityArtifact,
        to right: SimilarityArtifact
    ) throws -> Float? {
        guard left.descriptor.isCompatibleForDistance(with: right.descriptor),
              left.descriptor.backend == backendDescriptor.backend,
              left.descriptor.modelFingerprint == backendDescriptor.modelFingerprint
        else { return nil }
        do {
            let decoder = JSONDecoder()
            let leftEmbedding = try decoder.decode(ImageEmbedding.self, from: left.payload)
            let rightEmbedding = try decoder.decode(ImageEmbedding.self, from: right.payload)
            guard EmbeddingArtifact(
                descriptor: left.descriptor,
                embedding: leftEmbedding
            ).isInternallyConsistent,
            EmbeddingArtifact(
                descriptor: right.descriptor,
                embedding: rightEmbedding
            ).isInternallyConsistent else {
                throw CLIPSimilarityArtifactError.invalidPayload(
                    "The vector payload does not match its artifact descriptor."
                )
            }
            return leftEmbedding.cosineDistance(to: rightEmbedding)
        } catch let error as CLIPSimilarityArtifactError {
            throw error
        } catch {
            throw CLIPSimilarityArtifactError.invalidPayload(String(describing: error))
        }
    }

    public nonisolated func similarity(
        image: SimilarityArtifact,
        text: TextEmbedding
    ) throws -> Float {
        let validatedText: TextEmbedding
        do {
            validatedText = try text.validated()
        } catch let error as TextEmbeddingValidationError {
            throw ImageTextSimilarityError.invalidTextEmbedding(error)
        }

        let imageDescriptor = image.descriptor
        let textDescriptor = validatedText.descriptor
        guard imageDescriptor.backend == backendDescriptor.backend else {
            throw ImageTextSimilarityError.unsupportedImageBackend(
                expected: backendDescriptor.backend,
                actual: imageDescriptor.backend
            )
        }
        guard textDescriptor.backend.backend == backendDescriptor.backend else {
            throw ImageTextSimilarityError.unsupportedTextBackend(
                expected: backendDescriptor.backend,
                actual: textDescriptor.backend.backend
            )
        }
        guard imageDescriptor.modelFingerprint == backendDescriptor.modelFingerprint,
              textDescriptor.backend.modelFingerprint == backendDescriptor.modelFingerprint
        else {
            throw ImageTextSimilarityError.incompatibleModelFingerprint
        }
        guard imageDescriptor.dimensions == textDescriptor.dimensions else {
            throw ImageTextSimilarityError.incompatibleDimensions(
                expected: textDescriptor.dimensions,
                actual: imageDescriptor.dimensions
            )
        }
        guard imageDescriptor.representation == backendDescriptor.representation,
              textDescriptor.backend.representation == backendDescriptor.representation
        else {
            throw ImageTextSimilarityError.incompatibleRepresentation
        }
        guard imageDescriptor.preprocessingVersion == backendDescriptor.preprocessingVersion,
              textDescriptor.backend.preprocessingVersion == backendDescriptor.preprocessingVersion
        else {
            throw ImageTextSimilarityError.incompatiblePreprocessing
        }
        guard imageDescriptor.normalizationVersion == backendDescriptor.normalizationVersion,
              textDescriptor.backend.normalizationVersion == backendDescriptor.normalizationVersion
        else {
            throw ImageTextSimilarityError.incompatibleNormalization
        }
        guard imageDescriptor.configurationVersion == backendDescriptor.configurationVersion,
              textDescriptor.backend.configurationVersion == backendDescriptor.configurationVersion
        else {
            throw ImageTextSimilarityError.incompatibleConfiguration
        }
        guard textDescriptor.tokenizerVersion == Self.tokenizerVersion else {
            throw ImageTextSimilarityError.incompatibleTokenizer
        }
        guard imageDescriptor.schemaVersion == SimilarityArtifactDescriptor.currentSchemaVersion else {
            throw ImageTextSimilarityError.invalidImageSchemaVersion(imageDescriptor.schemaVersion)
        }

        let imageEmbedding: ImageEmbedding
        do {
            imageEmbedding = try JSONDecoder().decode(ImageEmbedding.self, from: image.payload)
        } catch {
            throw ImageTextSimilarityError.invalidImagePayload(String(describing: error))
        }
        guard EmbeddingArtifact(
            descriptor: imageDescriptor,
            embedding: imageEmbedding
        ).isInternallyConsistent else {
            throw ImageTextSimilarityError.invalidImagePayload(
                "The vector payload does not match its artifact descriptor."
            )
        }
        guard imageEmbedding.values.allSatisfy(\.isFinite) else {
            throw ImageTextSimilarityError.invalidImagePayload(
                "The image vector contains a non-finite value."
            )
        }
        let squaredMagnitude = imageEmbedding.values.reduce(Float.zero) {
            $0 + $1 * $1
        }
        guard squaredMagnitude.isFinite, squaredMagnitude > 0 else {
            throw ImageTextSimilarityError.invalidImagePayload(
                "The image vector has zero or invalid magnitude."
            )
        }
        let magnitude = sqrt(squaredMagnitude)
        guard abs(magnitude - 1) <= TextEmbedding.normalizationTolerance else {
            throw ImageTextSimilarityError.invalidImagePayload(
                "The image vector is not L2-normalized."
            )
        }

        let similarity = zip(imageEmbedding.values, validatedText.values)
            .reduce(Float.zero) { $0 + $1.0 * $1.1 }
        guard similarity.isFinite else {
            throw ImageTextSimilarityError.invalidImagePayload(
                "The image/text similarity is not finite."
            )
        }
        return max(-1, min(1, similarity))
    }

    private func imageEmbedding(for image: CGImage, model: LoadedCLIPModel) async throws -> [Float] {
        let imageInput = try Self.makeImageInput(image, descriptor: model.imageDescriptor)
        let tokenInput = Self.makeTokenInput(model.dummyTokens, descriptor: model.inputIDsDescriptor)
        let attentionMaskInput = Self.makeAttentionMaskInput(
            Self.attentionMasks(for: model.dummyTokens),
            descriptor: model.attentionMaskDescriptor
        )

        var outputs = try await model.function.run(inputs: [
            model.imageInputName: imageInput,
            model.inputIDsInputName: tokenInput,
            model.attentionMaskInputName: attentionMaskInput,
        ])
        guard let embeddingOutput = outputs.remove(model.imageEmbedsOutputName)?.ndArray else {
            throw CLIPProviderError.invalidModel("CLIP image embedding output is missing.")
        }
        let values = Self.flattenAsFloat(embeddingOutput)
        guard !values.isEmpty else {
            throw CLIPProviderError.invalidModel("CLIP image embedding output is empty.")
        }
        return values
    }

    private func textEmbedding(
        for batch: CLIPTextBatch,
        model: LoadedCLIPModel
    ) async throws -> [Float] {
        guard let textEmbedsOutputName = model.textEmbedsOutputName else {
            throw CLIPTextInferenceError.missingTextEmbedsOutput
        }
        let imageInput = try Self.makeZeroImageInput(descriptor: model.imageDescriptor)
        let tokenInput = Self.makeTokenInput(
            batch.tokenIDs,
            descriptor: model.inputIDsDescriptor
        )
        let attentionMaskInput = Self.makeAttentionMaskInput(
            batch.attentionMask,
            descriptor: model.attentionMaskDescriptor
        )

        try Task.checkCancellation()
        var outputs = try await model.function.run(inputs: [
            model.imageInputName: imageInput,
            model.inputIDsInputName: tokenInput,
            model.attentionMaskInputName: attentionMaskInput,
        ])
        try Task.checkCancellation()
        guard let embeddingOutput = outputs.remove(textEmbedsOutputName)?.ndArray else {
            throw CLIPTextInferenceError.missingTextEmbedsOutput
        }
        return try Self.validatedTextEmbeddingValues(
            embeddingOutput,
            expectedBatchSize: batch.tokenIDs.count
        )
    }

    private func loadModel() async throws -> LoadedCLIPModel {
        if let loadedModel { return loadedModel }

        let metadataURL = modelBundleURL.appendingPathComponent("metadata.json")
        let metadata = try JSONDecoder().decode(
            ModelBundleMetadata.self,
            from: Data(contentsOf: metadataURL)
        )
        guard let assetName = metadata.assets["main"] else {
            throw CLIPProviderError.invalidModel("metadata.json does not define assets.main.")
        }
        let modelURL = modelBundleURL.appendingPathComponent(assetName)
        let tokenizer = try CLIPTokenizer(
            folder: modelBundleURL.appendingPathComponent("tokenizer", isDirectory: true)
        )

        let model = try await AIModel(contentsOf: modelURL, options: Self.specializationOptions())
        guard let descriptor = model.functionDescriptor(for: "main") else {
            throw CLIPProviderError.invalidModel("Cannot find main function in CLIP model.")
        }
        guard let function = try model.loadFunction(named: "main") else {
            throw CLIPProviderError.invalidModel("Cannot load main function from CLIP model.")
        }

        let imageInputName = try Self.requiredName("pixel_values", kind: "input", names: descriptor.inputNames)
        let inputIDsInputName = try Self.requiredName("input_ids", kind: "input", names: descriptor.inputNames)
        let attentionMaskInputName = try Self.requiredName("attention_mask", kind: "input", names: descriptor.inputNames)
        let imageEmbedsOutputName = try Self.requiredName("image_embeds", kind: "output", names: descriptor.outputNames)
        let textEmbedsOutputName = descriptor.outputNames.contains("text_embeds")
            ? "text_embeds"
            : nil

        guard case let .ndArray(imageDescriptor) = descriptor.inputDescriptor(of: imageInputName),
              case let .ndArray(inputIDsDescriptor) = descriptor.inputDescriptor(of: inputIDsInputName),
              case let .ndArray(attentionMaskDescriptor) = descriptor.inputDescriptor(of: attentionMaskInputName)
        else {
            throw CLIPProviderError.invalidModel("CLIP inputs are not NDArrays.")
        }
        guard imageDescriptor.shape.count == 4,
              inputIDsDescriptor.shape.count == 2,
              attentionMaskDescriptor.shape.count == 2
        else {
            throw CLIPProviderError.invalidModel(
                "Unexpected CLIP input shapes: image=\(imageDescriptor.shape), input_ids=\(inputIDsDescriptor.shape), attention_mask=\(attentionMaskDescriptor.shape)."
            )
        }
        guard inputIDsDescriptor.shape == attentionMaskDescriptor.shape,
              inputIDsDescriptor.shape[0] > 0,
              inputIDsDescriptor.shape[1] > 1
        else {
            throw CLIPProviderError.invalidModel(
                "CLIP token and attention-mask inputs must have matching, non-empty shapes."
            )
        }
        guard inputIDsDescriptor.scalarType == .int32,
              attentionMaskDescriptor.scalarType == .int32
        else {
            throw CLIPProviderError.invalidModel(
                "CLIP token and attention-mask inputs must use Int32 scalars."
            )
        }

        let textBatchSize = inputIDsDescriptor.shape[0]
        let sequenceLength = inputIDsDescriptor.shape[1]
        let dummyTokens = Array(
            repeating: tokenizer.encode("a photo", contextLength: sequenceLength),
            count: textBatchSize
        )
        let loaded = LoadedCLIPModel(
            function: function,
            imageInputName: imageInputName,
            inputIDsInputName: inputIDsInputName,
            attentionMaskInputName: attentionMaskInputName,
            imageEmbedsOutputName: imageEmbedsOutputName,
            textEmbedsOutputName: textEmbedsOutputName,
            imageDescriptor: imageDescriptor,
            inputIDsDescriptor: inputIDsDescriptor,
            attentionMaskDescriptor: attentionMaskDescriptor,
            tokenizer: tokenizer,
            dummyTokens: dummyTokens
        )
        loadedModel = loaded
        return loaded
    }

    private nonisolated static func specializationOptions() -> SpecializationOptions {
        var options = SpecializationOptions(preferredComputeUnitKind: .gpu)
        options.expectFrequentReshapes = false
        return options
    }

    private nonisolated static func requiredName(
        _ preferredName: String,
        kind: String,
        names: [String]
    ) throws -> String {
        guard names.contains(preferredName) else {
            throw CLIPProviderError.invalidModel(
                "CLIP \(kind) \(preferredName) is missing. Available names: \(names)."
            )
        }
        return preferredName
    }

    private nonisolated static func makeImageInput(
        _ image: CGImage,
        descriptor: NDArrayDescriptor
    ) throws -> NDArray {
        let shape = descriptor.shape
        let batchSize = shape[0]
        let channels = shape[1]
        let height = shape[2]
        let width = shape[3]
        guard batchSize == 1, channels == 3 else {
            throw CLIPProviderError.invalidModel(
                "Expected CLIP image input shape [1, 3, H, W], got \(shape)."
            )
        }
        let pixels = try preprocessCLIPImage(image, width: width, height: height)
        var array = NDArray(descriptor: descriptor)
        if descriptor.scalarType == .float16 {
            #if !((os(macOS) || targetEnvironment(macCatalyst)) && arch(x86_64))
                fillNDArray(&array, as: Float16.self, with: pixels.map(Float16.init))
            #else
                throw CLIPProviderError.invalidModel("Float16 CLIP input is not supported on Intel macOS.")
            #endif
        } else {
            fillNDArray(&array, as: Float.self, with: pixels)
        }
        return array
    }

    private nonisolated static func makeZeroImageInput(
        descriptor: NDArrayDescriptor
    ) throws -> NDArray {
        let shape = descriptor.shape
        guard shape.count == 4, shape[0] == 1, shape[1] == 3 else {
            throw CLIPTextInferenceError.invalidImageInputShape(shape)
        }
        let count = shape.reduce(1, *)
        var array = NDArray(descriptor: descriptor)
        if descriptor.scalarType == .float16 {
            #if !((os(macOS) || targetEnvironment(macCatalyst)) && arch(x86_64))
                fillNDArray(&array, as: Float16.self, count: count) { _ in 0 }
            #else
                throw CLIPTextInferenceError.unsupportedInputScalarType
            #endif
        } else if descriptor.scalarType == .float32 {
            fillNDArray(&array, as: Float.self, count: count) { _ in 0 }
        } else {
            throw CLIPTextInferenceError.unsupportedInputScalarType
        }
        return array
    }

    private nonisolated static func makeTokenInput(
        _ tokens: [[Int32]],
        descriptor: NDArrayDescriptor
    ) -> NDArray {
        let batchSize = descriptor.shape[0]
        let sequenceLength = descriptor.shape[1]
        var array = NDArray(descriptor: descriptor)
        fillNDArray(&array, as: Int32.self, count: batchSize * sequenceLength) { index in
            let row = index / sequenceLength
            let column = index % sequenceLength
            guard row < tokens.count, column < tokens[row].count else {
                return CLIPTokenizer.eotTokenId
            }
            return tokens[row][column]
        }
        return array
    }

    private nonisolated static func makeAttentionMaskInput(
        _ masks: [[Int32]],
        descriptor: NDArrayDescriptor
    ) -> NDArray {
        let batchSize = descriptor.shape[0]
        let sequenceLength = descriptor.shape[1]
        var array = NDArray(descriptor: descriptor)
        fillNDArray(
            &array,
            as: Int32.self,
            count: batchSize * sequenceLength
        ) { index in
            let row = index / sequenceLength
            let column = index % sequenceLength
            guard row < masks.count, column < masks[row].count else { return 0 }
            return masks[row][column]
        }
        return array
    }

    static func makeTextBatch(
        queryTokens: [Int32],
        fillerTokens: [Int32],
        batchSize: Int,
        sequenceLength: Int
    ) throws -> CLIPTextBatch {
        guard batchSize > 0, sequenceLength > 1 else {
            throw CLIPTextInferenceError.invalidTokenInputShape(
                [batchSize, sequenceLength]
            )
        }
        let query = normalizedTokenRow(queryTokens, sequenceLength: sequenceLength)
        let filler = normalizedTokenRow(fillerTokens, sequenceLength: sequenceLength)
        let rows = [query] + Array(repeating: filler, count: batchSize - 1)
        return CLIPTextBatch(
            tokenIDs: rows,
            attentionMask: attentionMasks(for: rows)
        )
    }

    private nonisolated static func normalizedTokenRow(
        _ tokens: [Int32],
        sequenceLength: Int
    ) -> [Int32] {
        if tokens.count >= sequenceLength {
            var result = Array(tokens.prefix(sequenceLength))
            result[sequenceLength - 1] = CLIPTokenizer.eotTokenId
            return result
        }
        return tokens + Array(
            repeating: CLIPTokenizer.eotTokenId,
            count: sequenceLength - tokens.count
        )
    }

    static func attentionMasks(for tokenRows: [[Int32]]) -> [[Int32]] {
        tokenRows.map { row in
            let terminalIndex = row.dropFirst().firstIndex(of: CLIPTokenizer.eotTokenId)
                ?? (row.indices.last ?? 0)
            return row.indices.map { $0 <= terminalIndex ? 1 : 0 }
        }
    }

    private nonisolated static func preprocessCLIPImage(
        _ image: CGImage,
        width: Int,
        height: Int
    ) throws -> [Float] {
        let bytesPerPixel = 4
        let bytesPerRow = width * bytesPerPixel
        var rgba = [UInt8](repeating: 0, count: height * bytesPerRow)
        guard let colorSpace = CGColorSpace(name: CGColorSpace.sRGB),
              let context = CGContext(
                  data: &rgba,
                  width: width,
                  height: height,
                  bitsPerComponent: 8,
                  bytesPerRow: bytesPerRow,
                  space: colorSpace,
                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
              )
        else { throw CLIPProviderError.imagePreprocessingFailed }

        context.interpolationQuality = .high
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))

        let count = width * height
        var chw = [Float](repeating: 0, count: 3 * count)
        let mean: [Float] = [0.48145466, 0.4578275, 0.40821073]
        let standardDeviation: [Float] = [0.26862954, 0.26130258, 0.27577711]
        for pixel in 0 ..< count {
            let offset = pixel * bytesPerPixel
            let red = Float(rgba[offset]) / 255
            let green = Float(rgba[offset + 1]) / 255
            let blue = Float(rgba[offset + 2]) / 255
            chw[pixel] = (red - mean[0]) / standardDeviation[0]
            chw[count + pixel] = (green - mean[1]) / standardDeviation[1]
            chw[2 * count + pixel] = (blue - mean[2]) / standardDeviation[2]
        }
        return chw
    }

    private nonisolated static func fillNDArray<T: BitwiseCopyable>(
        _ array: inout NDArray,
        as _: T.Type,
        with elements: some Collection<T>
    ) {
        var view = array.mutableView(as: T.self)
        view.copyElements(fromContentsOf: elements)
    }

    private nonisolated static func fillNDArray<T: BitwiseCopyable>(
        _ array: inout NDArray,
        as _: T.Type,
        count: Int,
        using generator: (Int) -> T
    ) {
        let view = array.mutableView(as: T.self)
        view.withUnsafeMutablePointer { pointer, _, _ in
            for index in 0 ..< count { pointer[index] = generator(index) }
        }
    }

    private nonisolated static func flattenAsFloat(_ array: NDArray) -> [Float] {
        switch array.scalarType {
        #if !((os(macOS) || targetEnvironment(macCatalyst)) && arch(x86_64))
        case .float16:
            flattenNDArray(array, as: Float16.self)
        #endif
        case .float32:
            flattenNDArray(array, as: Float.self)
        default:
            []
        }
    }

    static func validatedTextEmbeddingValues(
        _ array: NDArray,
        expectedBatchSize: Int
    ) throws -> [Float] {
        let shape = array.shape
        guard shape.count == 2,
              shape[0] == expectedBatchSize,
              shape[1] > 0
        else {
            throw CLIPTextInferenceError.unexpectedOutputShape(
                expectedBatchSize: expectedBatchSize,
                actual: shape
            )
        }
        let values: [Float]
        switch array.scalarType {
        #if !((os(macOS) || targetEnvironment(macCatalyst)) && arch(x86_64))
        case .float16:
            values = flattenNDArray(array, as: Float16.self)
        #endif
        case .float32:
            values = flattenNDArray(array, as: Float.self)
        default:
            throw CLIPTextInferenceError.unsupportedOutputScalarType
        }
        let expectedCount = shape[0] * shape[1]
        guard values.count == expectedCount else {
            throw CLIPTextInferenceError.inconsistentOutputElementCount(
                expected: expectedCount,
                actual: values.count
            )
        }
        return Array(values.prefix(shape[1]))
    }

    private nonisolated static func flattenNDArray<T: BinaryFloatingPoint & BitwiseCopyable>(
        _ array: NDArray,
        as _: T.Type
    ) -> [Float] {
        let total = array.shape.reduce(1, *)
        var result = [Float](repeating: 0, count: total)
        array.view(as: T.self).withUnsafePointer { pointer, _, _ in
            for index in 0 ..< total { result[index] = Float(pointer[index]) }
        }
        return result
    }

    private struct LoadedCLIPModel {
        let function: InferenceFunction
        let imageInputName: String
        let inputIDsInputName: String
        let attentionMaskInputName: String
        let imageEmbedsOutputName: String
        let textEmbedsOutputName: String?
        let imageDescriptor: NDArrayDescriptor
        let inputIDsDescriptor: NDArrayDescriptor
        let attentionMaskDescriptor: NDArrayDescriptor
        let tokenizer: CLIPTokenizer
        let dummyTokens: [[Int32]]
    }
}

struct CLIPTextBatch: Equatable, Sendable {
    let tokenIDs: [[Int32]]
    let attentionMask: [[Int32]]
}

public enum CLIPProviderError: Error, CustomStringConvertible, Sendable {
    case invalidModelBundle(ModelBundleStatus)
    case invalidModel(String)
    case imagePreprocessingFailed

    public var description: String {
        switch self {
        case let .invalidModelBundle(status): "Invalid CLIP model bundle: \(status)"
        case let .invalidModel(message): message
        case .imagePreprocessingFailed: "CLIP image preprocessing failed."
        }
    }
}

public enum CLIPSimilarityArtifactError: Error, Equatable, Sendable {
    case invalidPayload(String)
}

public enum CLIPTextInferenceError: Error, Equatable, Sendable {
    case invalidTokenInputShape([Int])
    case invalidImageInputShape([Int])
    case unsupportedInputScalarType
    case missingTextEmbedsOutput
    case unexpectedOutputShape(expectedBatchSize: Int, actual: [Int])
    case unsupportedOutputScalarType
    case inconsistentOutputElementCount(expected: Int, actual: Int)
    case invalidEmbedding(TextEmbeddingValidationError)
}

public extension ModelBundleDescriptor {
    static let clip = ModelBundleDescriptor(
        family: ModelResourceDescriptor.clip.bundleDescriptor.family,
        fallbackName: ModelResourceDescriptor.clip.bundleDescriptor.fallbackName,
        assetKey: ModelResourceDescriptor.clip.bundleDescriptor.assetKey,
        requiredRelativePaths: ModelResourceDescriptor.clip.bundleDescriptor.requiredRelativePaths,
        acceptedAssetExtensions: ModelResourceDescriptor.clip.bundleDescriptor.acceptedAssetExtensions
    )
}
