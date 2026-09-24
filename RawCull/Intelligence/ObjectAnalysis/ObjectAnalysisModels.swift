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
}

nonisolated struct ObjectPhotoAssessment: Codable, Equatable, Sendable {
    let imageSummary: String
    let objects: [ObjectAssessment]
    let relationships: [String]
    let strengths: [String]
    let problems: [String]
    let preferredObjectIDs: [String]
    let confidence: Float
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

nonisolated struct ObjectPhotoAnalysisResult: Equatable, Identifiable, Sendable {
    let fileID: UUID
    let fileName: String
    let concepts: [String]
    let discoveryMode: ObjectDiscoveryMode
    let instances: [ObjectInstanceDescriptor]
    let assessment: ObjectPhotoAssessment?
    let freeformResponse: String?
    let failure: String?
    let sam3ModelIdentity: String?
    let sam3Model: ModelIdentity?
    let qwenModelName: String?
    let sourceSize: Int64
    let sourceModified: Date
    let timestamp: Date

    var id: UUID { fileID }
    var needsAssessmentRetry: Bool { !instances.isEmpty && assessment == nil && failure != "Cancelled" }
    var isSuccessful: Bool { failure == nil && !needsAssessmentRetry }
}

nonisolated enum ObjectAnalysisError: Error, LocalizedError, Equatable, Sendable {
    case invalidConceptResponse
    case invalidConcept(String)
    case invalidAssessment
    case imageUnavailable
    case segmentationUnavailable
    case noConcepts

    var errorDescription: String? {
        switch self {
        case .invalidConceptResponse: "Qwen did not return valid object concepts. Enter specific concepts to retry."
        case let .invalidConcept(value): "Invalid concept: \(value)"
        case .invalidAssessment: "Qwen did not return a valid object assessment."
        case .imageUnavailable: "The selected photo could not be decoded."
        case .segmentationUnavailable: "SAM 3 object segmentation is unavailable."
        case .noConcepts: "No visible object concepts were found. Enter specific concepts to retry."
        }
    }
}
