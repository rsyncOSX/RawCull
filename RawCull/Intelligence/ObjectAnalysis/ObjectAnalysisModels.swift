import CoreGraphics
import Foundation
import PhotoAIContracts

nonisolated enum ObjectDiscoveryMode: String, CaseIterable, Sendable {
    case automatic
    case specificConcepts
}

nonisolated struct ObjectConceptSuggestion: Equatable, Sendable {
    let concept: SegmentationConcept
    let displayName: String
    let reason: String
}

nonisolated struct ObjectInstanceDescriptor: Equatable, Identifiable, Sendable {
    /// Board-local number, stable for the persisted result.
    let id: String
    let concept: String
    let aliases: [String]
    let score: Float
    let normalizedBoundingBox: CGRect
    let sourceInstanceID: String
}

nonisolated enum ObjectVisibility: String, Codable, Equatable, Sendable {
    case clear, partial, obscured, uncertain
}

nonisolated enum ObjectFocusQuality: String, Codable, Equatable, Sendable {
    case sharp, soft, blurred, uncertain
}

private nonisolated struct ObjectBoardID: Decodable {
    let value: String

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let text = try? container.decode(String.self) {
            value = text
        } else if let number = try? container.decode(Int.self) {
            value = String(number)
        } else {
            throw DecodingError.typeMismatch(Self.self, .init(
                codingPath: decoder.codingPath, debugDescription: "Expected a board ID string or integer",
            ))
        }
    }
}

private nonisolated struct ObjectTextList: Decodable {
    let values: [String]

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let list = try? container.decode([String].self) {
            values = list
        } else if let text = try? container.decode(String.self) {
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            values = trimmed.lowercased() == "none" ? [] : [trimmed]
        } else {
            throw DecodingError.typeMismatch(Self.self, .init(
                codingPath: decoder.codingPath, debugDescription: "Expected a string list or one string",
            ))
        }
    }
}

nonisolated struct ObjectAssessment: Codable, Equatable, Identifiable, Sendable {
    let id: String
    let concept: String
    let description: String
    let visibility: ObjectVisibility
    let focusQuality: ObjectFocusQuality
    let expression: String?
    let obstructions: [String]
    let strengths: [String]
    let problems: [String]
    let confidence: Float

    private enum CodingKeys: String, CodingKey {
        case id, concept, description, visibility, focusQuality, expression
        case obstructions, strengths, problems, confidence
    }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        id = try values.decode(ObjectBoardID.self, forKey: .id).value
        concept = try values.decode(String.self, forKey: .concept)
        description = try values.decode(String.self, forKey: .description)
        visibility = try values.decode(ObjectVisibility.self, forKey: .visibility)
        focusQuality = try values.decode(ObjectFocusQuality.self, forKey: .focusQuality)
        expression = try values.decodeIfPresent(String.self, forKey: .expression)
        obstructions = try values.decode(ObjectTextList.self, forKey: .obstructions).values
        strengths = try values.decode(ObjectTextList.self, forKey: .strengths).values
        problems = try values.decode(ObjectTextList.self, forKey: .problems).values
        confidence = try values.decode(Float.self, forKey: .confidence)
    }
}

nonisolated struct ObjectPhotoAssessment: Codable, Equatable, Sendable {
    let imageSummary: String?
    let objects: [ObjectAssessment]
    let relationships: [String]
    let strengths: [String]
    let problems: [String]
    let preferredObjectIDs: [String]
    let confidence: Float

    private enum CodingKeys: String, CodingKey {
        case imageSummary, objects, relationships, strengths, problems
        case preferredObjectIDs, confidence
    }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        imageSummary = try values.decodeIfPresent(String.self, forKey: .imageSummary)
        objects = try values.decode([ObjectAssessment].self, forKey: .objects)
        relationships = try values.decode([String].self, forKey: .relationships)
        strengths = try values.decode([String].self, forKey: .strengths)
        problems = try values.decode([String].self, forKey: .problems)
        preferredObjectIDs = try values.decode([ObjectBoardID].self, forKey: .preferredObjectIDs)
            .map(\.value)
        confidence = try values.decode(Float.self, forKey: .confidence)
    }
}

nonisolated enum ObjectAnalysisStage: Equatable, Sendable {
    case loadingImage
    case discoveringConcepts
    case segmenting(concept: String, conceptIndex: Int, conceptCount: Int)
    case preparingObjectBoard
    case analyzingObjects
    case completed
}

nonisolated struct ObjectAnalysisProgress: Equatable, Sendable {
    let currentFileName: String
    let completedCount: Int
    let totalCount: Int
    let stage: ObjectAnalysisStage
}

nonisolated struct ObjectAnalysisTimings: Equatable, Sendable {
    var conceptDiscoverySeconds: Double = 0
    var segmentationSeconds: Double = 0
    var boardRenderingSeconds: Double = 0
    var assessmentSeconds: Double = 0
}

nonisolated struct ObjectPhotoAnalysisResult: Equatable, Identifiable, Sendable {
    let fileID: UUID
    let fileName: String
    let concepts: [String]
    let discoveryMode: ObjectDiscoveryMode
    let rawInstanceCount: Int
    let instances: [ObjectInstanceDescriptor]
    let assessment: ObjectPhotoAssessment?
    let freeformResponse: String?
    let failure: String?
    let sam3ModelIdentity: String?
    let sam3Model: ModelIdentity?
    let qwenModelName: String?
    let sourceSize: Int64
    let sourceModified: Date
    let timings: ObjectAnalysisTimings
    let timestamp: Date

    var id: UUID {
        fileID
    }

    var needsAssessmentRetry: Bool {
        !instances.isEmpty && assessment == nil && failure != "Cancelled"
    }

    var isSuccessful: Bool {
        failure == nil && !needsAssessmentRetry
    }
}

nonisolated enum ObjectAnalysisError: Error, LocalizedError, Equatable, Sendable {
    case invalidConceptResponse
    case invalidConcept(String)
    case invalidAssessment
    case imageUnavailable
    case reviewBoardUnavailable
    case segmentationUnavailable
    case noConcepts

    var errorDescription: String? {
        switch self {
        case .invalidConceptResponse: "Qwen did not return valid object concepts. Enter specific concepts to retry."
        case let .invalidConcept(value): "Invalid concept: \(value)"
        case .invalidAssessment: "Qwen did not return a valid object assessment."
        case .imageUnavailable: "The selected photo could not be decoded."
        case .reviewBoardUnavailable: "A numbered object crop could not be prepared. Retry the analysis."
        case .segmentationUnavailable: "SAM 3 object segmentation is unavailable."
        case .noConcepts: "No visible object concepts were found. Enter specific concepts to retry."
        }
    }
}
