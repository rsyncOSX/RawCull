import Foundation

struct BurstGroupingConfig: Codable, Equatable {
    var visualDistanceThreshold: Float = 0.25
    var maxTimeGapSeconds: Double = 2.0
    var requireSameCamera: Bool = true
    var requireSimilarFocalLength: Bool = true
    var maxFocalLengthDeltaMM: Double = 3.0

    nonisolated static let algorithmVersion = 2
}

enum BurstPairKey {
    nonisolated static func cacheKey(previousID: UUID, currentID: UUID) -> String {
        "\(previousID.uuidString)|\(currentID.uuidString)"
    }
}

struct BurstBoundaryEvidence: Codable, Equatable {
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

enum BurstDecisionConfidence: String, Codable, Equatable {
    case high
    case medium
    case low

    nonisolated var title: String {
        switch self {
        case .high: "Best frame found"
        case .medium: "Compare first"
        case .low: "Needs manual review"
        }
    }
}

enum BurstGroupPrimaryAction: Equatable {
    case keepBest
    case compare
}

struct BurstLabelDescription: Equatable, Identifiable {
    var label: String
    var description: String

    var id: String {
        label
    }
}

struct BurstGroupPresentation: Equatable {
    var title: String
    var decision: String
    var explanation: String
    var confidenceLabel: String
    var primaryActionTitle: String
    var primaryAction: BurstGroupPrimaryAction
    var recommendedBadge: String?
    var showsAppliedStatus: Bool

    nonisolated static let labelDescriptions: [BurstLabelDescription] = [
        BurstLabelDescription(
            label: BurstDecisionConfidence.high.title,
            description: "Clear best frame; Keep Best can be applied directly.",
        ),
        BurstLabelDescription(
            label: BurstDecisionConfidence.medium.title,
            description: "A likely best frame exists, but compare the top frames.",
        ),
        BurstLabelDescription(
            label: BurstDecisionConfidence.low.title,
            description: "The app cannot pick safely; open the burst and review manually.",
        ),
        BurstLabelDescription(
            label: "Manual",
            description: "You selected the winner for this burst.",
        ),
        BurstLabelDescription(
            label: "Applied",
            description: "A burst action has already rated/rejected the group.",
        ),
        BurstLabelDescription(
            label: "Suggested best",
            description: "The recommended frame in a burst group.",
        ),
        BurstLabelDescription(
            label: "Check frame",
            description: "A frame marked for manual inspection in a low-confidence burst.",
        )
    ]

    nonisolated static func make(
        result: BurstAnalysisResult,
        files: [FileItem],
    ) -> BurstGroupPresentation {
        let recommendedFrameIndex: Int? = if let recommendedFileID = result.recommendedFileID {
            frameIndex(for: recommendedFileID, in: result.fileIDs)
        } else {
            nil
        }
        let frameText = recommendedFrameIndex.map { "frame \($0)" }
        let title = title(files: files)
        let applied = result.reviewState == .decisionApplied

        if result.reviewState == .manualWinnerOverride {
            return BurstGroupPresentation(
                title: title,
                decision: "Manual winner: \(frameText ?? "selected frame")",
                explanation: explanation(for: result, confidence: result.confidence),
                confidenceLabel: "Manual",
                primaryActionTitle: "Review burst",
                primaryAction: .compare,
                recommendedBadge: "Manual",
                showsAppliedStatus: applied,
            )
        }

        switch result.confidence {
        case .high:
            return BurstGroupPresentation(
                title: title,
                decision: "Best frame found",
                explanation: explanation(for: result, confidence: .high),
                confidenceLabel: BurstDecisionConfidence.high.title,
                primaryActionTitle: "Keep best",
                primaryAction: .keepBest,
                recommendedBadge: result.recommendedFileID == nil ? nil : "Suggested best",
                showsAppliedStatus: applied,
            )

        case .medium:
            return BurstGroupPresentation(
                title: title,
                decision: "Compare before deleting",
                explanation: explanation(for: result, confidence: .medium),
                confidenceLabel: BurstDecisionConfidence.medium.title,
                primaryActionTitle: "Compare top 2",
                primaryAction: .compare,
                recommendedBadge: result.recommendedFileID == nil ? nil : "Suggested best",
                showsAppliedStatus: applied,
            )

        case .low:
            return BurstGroupPresentation(
                title: title,
                decision: "Needs manual review",
                explanation: explanation(for: result, confidence: .low),
                confidenceLabel: BurstDecisionConfidence.low.title,
                primaryActionTitle: "Review burst",
                primaryAction: .compare,
                recommendedBadge: result.recommendedFileID == nil ? nil : "Check frame",
                showsAppliedStatus: applied,
            )
        }
    }

    nonisolated static func recommendationBadge(
        for candidate: BurstCandidateScore,
        in result: BurstAnalysisResult,
    ) -> String? {
        guard result.recommendedFileID == candidate.fileID else { return nil }
        return make(result: result, files: []).recommendedBadge
    }

    private nonisolated static func frameIndex(for fileID: UUID, in fileIDs: [UUID]) -> Int? {
        guard let index = fileIDs.firstIndex(of: fileID) else { return nil }
        return index + 1
    }

    private nonisolated static func title(files: [FileItem]) -> String {
        var parts = ["Burst of \(files.count) photos"]
        if let first = files.first {
            parts.append(captureLabel(for: first.dateModified))
            if let camera = sharedCamera(in: files) {
                parts.append(camera)
            }
        }
        return parts.joined(separator: " · ")
    }

    private nonisolated static func captureLabel(for date: Date) -> String {
        if Calendar.current.isDateInToday(date) {
            return date.formatted(date: .omitted, time: .shortened)
        }
        if Calendar.current.isDateInYesterday(date) {
            return "Yesterday"
        }
        return date.formatted(date: .abbreviated, time: .omitted)
    }

    private nonisolated static func sharedCamera(in files: [FileItem]) -> String? {
        let cameras = Set(files.compactMap(\.exifData?.camera).filter { !$0.isEmpty })
        return cameras.count == 1 ? cameras.first : nil
    }

    private nonisolated static func explanation(
        for result: BurstAnalysisResult,
        confidence: BurstDecisionConfidence,
    ) -> String {
        let items: [String] = switch confidence {
        case .high:
            humanReasons(result.reasons)

        case .medium:
            humanReasons(result.reasons) + Array(humanCautions(result.cautions).prefix(1))

        case .low:
            humanCautions(result.cautions)
        }

        let uniqueItems = items.reduce(into: [String]()) { partial, item in
            if !partial.contains(item) {
                partial.append(item)
            }
        }
        let capped = Array(uniqueItems.prefix(3))
        return capped.isEmpty ? "Recommendation uncertain" : capped.joined(separator: " · ")
    }

    private nonisolated static func humanReasons(_ reasons: [String]) -> [String] {
        reasons.compactMap { reason in
            switch reason {
            case "Sharpest candidate leads": "Sharpest frame"
            case "Exposure stable": "stable exposure"
            case "Subject stable": "same subject"
            case "Best is clearly ahead": "clear winner"
            case "AF evidence available": "autofocus evidence available"
            default: nil
            }
        }
    }

    private nonisolated static func humanCautions(_ cautions: [String]) -> [String] {
        cautions.compactMap { caution in
            switch caution {
            case "Sharpness scores missing", "Sharpness missing": "sharpness unavailable"
            case "Exposure or metadata changed": "exposure changed"
            case "Similarity spread is wider": "wider variation across frames"
            case "Top two are close": "top frames are close"
            case "AF evidence missing": "autofocus unavailable"
            case "Metadata changed": "camera settings changed"
            default: nil
            }
        }
    }
}

struct BurstWinnerOverride: Codable, Equatable, Identifiable {
    var id: UUID
    var winnerFileName: String
    var memberFileNames: [String]

    init(
        id: UUID = UUID(),
        winnerFileName: String,
        memberFileNames: [String],
    ) {
        self.id = id
        self.winnerFileName = winnerFileName
        self.memberFileNames = memberFileNames
    }

    enum CodingKeys: String, CodingKey {
        case id
        case winnerFileName
        case memberFileNames
    }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        id = try values.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        winnerFileName = try values.decode(String.self, forKey: .winnerFileName)
        memberFileNames = try values.decodeIfPresent([String].self, forKey: .memberFileNames) ?? []
    }
}

enum BurstReviewState: String, Codable, Equatable {
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

struct BurstCandidateScore: Codable, Equatable {
    var fileID: UUID
    var overallScore: Float
    var sharpnessComponent: Float
    var burstRelativeSharpnessComponent: Float?
    var focusPointComponent: Float
    var saliencyComponent: Float
    var metadataComponent: Float
    var confidence: BurstDecisionConfidence
    var reasons: [String]
    var cautions: [String]
}

struct BurstAnalysisResult: Codable, Equatable, Identifiable {
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

    nonisolated func canApplyOneClickCulling(hasSharpnessScores: Bool) -> Bool {
        isSafeForOneClickCulling && hasSharpnessScores
    }
}

enum BurstAnalysisStep: String, Codable, Equatable {
    case idle
    case loadingCache
    case scoringSharpness
    case indexingSimilarity
    case grouping
    case ranking
    case savingCache
}

struct BurstAnalysisProgress: Codable, Equatable {
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
