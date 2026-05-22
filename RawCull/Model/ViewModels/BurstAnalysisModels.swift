import Foundation

struct BurstGroupingConfig: Codable, Equatable, Sendable {
    var visualDistanceThreshold: Float = 0.25
    var maxTimeGapSeconds: Double = 2.0
    var requireSameCamera: Bool = true
    var requireSimilarFocalLength: Bool = true
    var maxFocalLengthDeltaMM: Double = 3.0

    nonisolated static let algorithmVersion = 1
}

enum BurstPairKey {
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

enum BurstWinnerOverrideSource: String, Codable, Equatable, Sendable {
    case manualWinner
}

struct BurstWinnerOverride: Codable, Equatable, Identifiable, Sendable {
    var id: UUID
    var winnerFileName: String
    var winnerFileID: UUID?
    var memberFileNames: [String]
    var source: BurstWinnerOverrideSource
    var dateApplied: String?
    var rankingAlgorithmVersion: Int

    init(
        id: UUID = UUID(),
        winnerFileName: String,
        winnerFileID: UUID?,
        memberFileNames: [String],
        source: BurstWinnerOverrideSource = .manualWinner,
        dateApplied: String? = nil,
        rankingAlgorithmVersion: Int = BurstGroupingConfig.algorithmVersion,
    ) {
        self.id = id
        self.winnerFileName = winnerFileName
        self.winnerFileID = winnerFileID
        self.memberFileNames = memberFileNames
        self.source = source
        self.dateApplied = dateApplied
        self.rankingAlgorithmVersion = rankingAlgorithmVersion
    }

    enum CodingKeys: String, CodingKey {
        case id
        case winnerFileName
        case winnerFileID
        case memberFileNames
        case source
        case dateApplied
        case rankingAlgorithmVersion
    }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        id = try values.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        winnerFileName = try values.decode(String.self, forKey: .winnerFileName)
        winnerFileID = try values.decodeIfPresent(UUID.self, forKey: .winnerFileID)
        memberFileNames = try values.decodeIfPresent([String].self, forKey: .memberFileNames) ?? []
        source = try values.decodeIfPresent(BurstWinnerOverrideSource.self, forKey: .source) ?? .manualWinner
        dateApplied = try values.decodeIfPresent(String.self, forKey: .dateApplied)
        rankingAlgorithmVersion = try values.decodeIfPresent(Int.self, forKey: .rankingAlgorithmVersion) ?? 0
    }
}

enum BurstReviewState: String, Codable, Equatable, Sendable {
    case none
    case algorithmReviewed
    case manualWinnerOverride
    case decisionApplied

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let rawValue = try container.decode(String.self)
        self = Self(rawValue: rawValue) ?? .none
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }
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
    var id: Int {
        groupID
    }

    var groupID: Int
    var fileIDs: [UUID]
    var candidates: [BurstCandidateScore]
    var recommendedFileID: UUID?
    var secondBestFileID: UUID?
    var confidence: BurstDecisionConfidence
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
    var total: Int = 0

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
