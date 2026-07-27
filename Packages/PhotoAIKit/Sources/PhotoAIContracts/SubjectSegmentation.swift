import CoreGraphics
import Foundation

public enum SubjectSegmentationPrompt: String, CaseIterable, Codable, Hashable, Identifiable, Sendable {
    case subject, person, bird, deer, animal, car, birdHead, animalHead, face

    public static let standardPrompts: [SubjectSegmentationPrompt] = [
        .subject, .person, .bird, .deer, .animal, .car,
    ]

    public var id: String { rawValue }

    public var query: String {
        switch self {
        case .subject: "subject"
        case .person: "person"
        case .bird: "bird"
        case .deer: "deer"
        case .animal: "animal"
        case .car: "car"
        case .birdHead: "bird head"
        case .animalHead: "animal head"
        case .face: "face"
        }
    }
}

public struct SubjectSegmentationTiming: Equatable, Sendable {
    public let preprocessMilliseconds: Double?
    public let inferenceMilliseconds: Double?
    public let postprocessMilliseconds: Double?
    public let totalMilliseconds: Double?

    public init(
        preprocessMilliseconds: Double? = nil,
        inferenceMilliseconds: Double? = nil,
        postprocessMilliseconds: Double? = nil,
        totalMilliseconds: Double? = nil
    ) {
        self.preprocessMilliseconds = preprocessMilliseconds
        self.inferenceMilliseconds = inferenceMilliseconds
        self.postprocessMilliseconds = postprocessMilliseconds
        self.totalMilliseconds = totalMilliseconds
    }
}

public struct SubjectSegmentationDiagnostics: Equatable, Sendable {
    public let modelIdentity: ModelIdentity
    public let prompt: SubjectSegmentationPrompt
    public let confidence: Float
    public let timing: SubjectSegmentationTiming
    public let inputSize: CGSize
    public let outputSize: CGSize
    public let resourceName: String?
    public let assetName: String?

    public init(
        modelIdentity: ModelIdentity,
        prompt: SubjectSegmentationPrompt,
        confidence: Float,
        timing: SubjectSegmentationTiming,
        inputSize: CGSize,
        outputSize: CGSize,
        resourceName: String? = nil,
        assetName: String? = nil
    ) {
        self.modelIdentity = modelIdentity
        self.prompt = prompt
        self.confidence = confidence
        self.timing = timing
        self.inputSize = inputSize
        self.outputSize = outputSize
        self.resourceName = resourceName
        self.assetName = assetName
    }
}

public struct SubjectSegmentationRequest: Sendable {
    public let requestID: UUID
    public let sourceID: UUID
    public let prompt: SubjectSegmentationPrompt
    public let image: CGImage
    public let inputSize: CGSize
    public let outputSize: CGSize
    public let maxSide: Int

    public init(
        requestID: UUID = UUID(),
        sourceID: UUID,
        prompt: SubjectSegmentationPrompt,
        image: CGImage,
        inputSize: CGSize,
        outputSize: CGSize,
        maxSide: Int
    ) {
        self.requestID = requestID
        self.sourceID = sourceID
        self.prompt = prompt
        self.image = image
        self.inputSize = inputSize
        self.outputSize = outputSize
        self.maxSide = maxSide
    }
}

public struct SubjectSegmentationResult: Sendable {
    public let sourceID: UUID
    public let requestID: UUID
    public let prompt: SubjectSegmentationPrompt
    public let mask: CGImage
    public let confidence: Float
    public let modelIdentity: ModelIdentity
    public let inputSize: CGSize
    public let outputSize: CGSize
    public let timing: SubjectSegmentationTiming
    public let diagnostics: SubjectSegmentationDiagnostics

    public init(
        sourceID: UUID,
        requestID: UUID,
        prompt: SubjectSegmentationPrompt,
        mask: CGImage,
        confidence: Float,
        modelIdentity: ModelIdentity,
        inputSize: CGSize,
        outputSize: CGSize,
        timing: SubjectSegmentationTiming,
        diagnostics: SubjectSegmentationDiagnostics
    ) {
        self.sourceID = sourceID
        self.requestID = requestID
        self.prompt = prompt
        self.mask = mask
        self.confidence = confidence
        self.modelIdentity = modelIdentity
        self.inputSize = inputSize
        self.outputSize = outputSize
        self.timing = timing
        self.diagnostics = diagnostics
    }
}

public enum SubjectSegmentationError: Error, Equatable, Sendable {
    case noMask
    case decodeFailure
    case cancelled
    case providerFailure(String)
}

public protocol SubjectSegmenting: Sendable {
    var modelIdentity: ModelIdentity { get }
    func segment(_ request: SubjectSegmentationRequest) async throws -> SubjectSegmentationResult
}
