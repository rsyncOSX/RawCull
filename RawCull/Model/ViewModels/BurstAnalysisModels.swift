import Foundation

struct BurstGroupingConfig: Codable, Equatable, Sendable {
    var visualDistanceThreshold: Float = 0.25
    var maxTimeGapSeconds: Double = 2.0
    var requireSameCamera: Bool = true
    var requireSimilarFocalLength: Bool = true
    var maxFocalLengthDeltaMM: Double = 3.0

    nonisolated static let algorithmVersion = 1
}

struct BurstPairKey: Codable, Equatable, Sendable {
    let previousID: UUID
    let currentID: UUID

    nonisolated var cacheKey: String {
        Self.cacheKey(previousID: previousID, currentID: currentID)
    }

    nonisolated static func cacheKey(previousID: UUID, currentID: UUID) -> String {
        "\(previousID.uuidString)|\(currentID.uuidString)"
    }
}

struct BurstBoundaryEvidence: Codable, Equatable, Sendable {
    var previousID: UUID
    var currentID: UUID
    var visualDistance: Float?
    var timeGapSeconds: Double?
    var focalLengthDelta: Double?
    var exposureChanged: Bool
    var cameraChanged: Bool
    var lensChanged: Bool
    var startsNewGroup: Bool
    var reasons: [String]
}

enum BurstDecisionConfidence: String, Codable, Equatable, Sendable {
    case high
    case medium
    case low

    var title: String {
        switch self {
        case .high: "High confidence"
        case .medium: "Medium confidence"
        case .low: "Low confidence"
        }
    }
}

enum BurstReviewState: String, Codable, Equatable, Sendable {
    case none
    case markedForReview
    case decisionApplied
}

struct BurstCandidateScore: Codable, Equatable, Sendable {
    var fileID: UUID
    var overallScore: Float
    var sharpnessComponent: Float
    var focusPointComponent: Float
    var saliencyComponent: Float
    var metadataComponent: Float
    var confidence: BurstDecisionConfidence
    var reasons: [String]
    var cautions: [String]
}

struct BurstAnalysisResult: Codable, Equatable, Identifiable, Sendable {
    var id: Int { groupID }
    var groupID: Int
    var fileIDs: [UUID]
    var candidates: [BurstCandidateScore]
    var recommendedFileID: UUID?
    var secondBestFileID: UUID?
    var confidence: BurstDecisionConfidence
    var boundaryEvidence: [BurstBoundaryEvidence]
    var reviewState: BurstReviewState
    var isSafeForOneClickCulling: Bool
    var reasons: [String]
    var cautions: [String]
}

enum BurstAnalysisStep: String, Codable, Equatable, Sendable {
    case idle
    case loadingCache
    case scoringSharpness
    case indexingSimilarity
    case grouping
    case ranking
    case savingCache
}

struct BurstAnalysisProgress: Codable, Equatable, Sendable {
    var step: BurstAnalysisStep = .idle
    var completed: Int = 0
    var total: Int = 0
    var estimatedSeconds: Int = 0

    var isRunning: Bool {
        step != .idle
    }

    var isCountBased: Bool {
        total > 0
    }

    var statusText: String {
        switch step {
        case .idle: "Ready"
        case .loadingCache: "Loading burst analysis..."
        case .scoringSharpness: "Scoring sharpness..."
        case .indexingSimilarity: "Indexing similarity..."
        case .grouping: "Grouping bursts..."
        case .ranking: "Ranking burst candidates..."
        case .savingCache: "Saving burst analysis..."
        }
    }
}

struct BurstUndoEntry: Equatable {
    let groupID: Int
    let previousRatingsByFileName: [String: Int]
}
