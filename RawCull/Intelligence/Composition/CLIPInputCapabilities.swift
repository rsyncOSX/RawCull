import CoreAICLIPBackend
import Foundation

/// Snapshot suitable for attaching to CLIP evidence. Provider validation alone
/// does not establish observed preprocessing geometry or alternate shape support.
nonisolated struct RawCullCLIPInputCapabilities: Encodable, Equatable, Sendable {
    let modelFingerprint: String
    let preprocessingVersion: String
    let configurationVersion: String
    let normalizationVersion: String
    let configuredWidth: Int
    let configuredHeight: Int
    let resize: String
    let crop: String
    let interpolation: String
    let mean: [Float]
    let standardDeviation: [Float]
    let configuredEmbeddingDimensions: Int?
    let tokenizerType: String
    let tokenizerVersion: String
    let tokenizerContextLength: Int
    let tokenizerPaddingTokenID: Int32?
    let tensorLayout = "NCHW"
    let channelOrder = "RGB"
    let colorSpace = "sRGB"
    let encoderGeometryVerified = false

    init(provider: CoreAICLIPProvider) {
        let backend = provider.backendDescriptor
        let configuration = provider.runtimeConfiguration
        let preprocessing = configuration.preprocessing
        modelFingerprint = backend.modelFingerprint
        preprocessingVersion = backend.preprocessingVersion
        configurationVersion = backend.configurationVersion
        normalizationVersion = backend.normalizationVersion
        configuredWidth = preprocessing.width
        configuredHeight = preprocessing.height
        resize = preprocessing.resize
        crop = preprocessing.crop
        interpolation = preprocessing.interpolation
        mean = preprocessing.mean
        standardDeviation = preprocessing.standardDeviation
        configuredEmbeddingDimensions = configuration.embeddingDimensions
        tokenizerType = configuration.tokenizer.type
        tokenizerVersion = configuration.tokenizer.version
        tokenizerContextLength = configuration.tokenizer.contextLength
        tokenizerPaddingTokenID = configuration.tokenizer.paddingTokenID
    }
}
