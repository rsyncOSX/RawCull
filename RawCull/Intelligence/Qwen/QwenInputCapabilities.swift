import CoreAILanguageModels
import CoreAIQwenBackend
import CryptoKit
import Foundation

/// Declared input contract, deliberately separate from observed encoder inputs.
/// Metadata inspection does not establish compiled shape support or pixel fidelity.
nonisolated struct QwenInputCapabilities: Encodable, Equatable, Sendable {
    let modelIdentifier: String
    /// Identifies configuration bytes, not model weights or tokenizer contents.
    let metadataSHA256: String?
    let modelName: String
    let compression: String?
    let maximumContextTokens: Int
    let maximumResponseTokens: Int
    let imagesPerRequest: Int
    let configuredEncoderSide: Int?
    let configuredImageTokens: Int?
    let configuredImageStrategy: String?
    let configuredPatchSize: Int?
    let imageMean: [Double]?
    let imageStandardDeviation: [Double]?
    let rescaleFactor: Double?
    let geometryInspectionFailure: String?
    let encoderGeometryVerified: Bool = false

    static func inspect(provider: CoreAIQwenProvider, bundleURL: URL) -> Self {
        let vision: VisionConfig?
        let failure: String?
        var metadataSHA256: String?
        do {
            let data = try Data(contentsOf: bundleURL.appendingPathComponent("metadata.json"))
            metadataSHA256 = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
            let metadata = try JSONDecoder().decode(
                VisionMetadata.self,
                from: data,
            )
            guard metadata.vision.imageSize > 0,
                  metadata.vision.imageTokenCount > 0,
                  metadata.vision.patchSize > 0,
                  metadata.vision.imageMean.count == 3,
                  metadata.vision.imageMean.allSatisfy(\.isFinite),
                  metadata.vision.imageStd.count == 3,
                  metadata.vision.imageStd.allSatisfy({ $0.isFinite && $0 > 0 }),
                  metadata.vision.rescaleFactor.isFinite,
                  metadata.vision.rescaleFactor > 0
            else {
                throw InspectionError.invalidGeometry
            }
            vision = metadata.vision
            failure = nil
        } catch {
            vision = nil
            failure = String(describing: error)
        }
        return Self(
            modelIdentifier: provider.modelIdentity.artifactIdentifier,
            metadataSHA256: metadataSHA256,
            modelName: provider.configuration.name,
            compression: provider.configuration.compression,
            maximumContextTokens: provider.configuration.maximumContextLength,
            maximumResponseTokens: 4096,
            imagesPerRequest: 1,
            configuredEncoderSide: vision?.imageSize,
            configuredImageTokens: vision?.imageTokenCount,
            configuredImageStrategy: vision?.imageStrategy.rawValue,
            configuredPatchSize: vision?.patchSize,
            imageMean: vision?.imageMean,
            imageStandardDeviation: vision?.imageStd,
            rescaleFactor: vision?.rescaleFactor,
            geometryInspectionFailure: failure,
        )
    }

    private struct VisionMetadata: Decodable { let vision: VisionConfig }
    private enum InspectionError: Error { case invalidGeometry }
}
