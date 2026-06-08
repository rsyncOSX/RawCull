import Foundation
import RawCullCore

struct BurstGroupSignature: Codable, Hashable {
    let memberKeys: [String]

    init(memberKeys: [String]) {
        self.memberKeys = memberKeys
            .filter { !$0.isEmpty }
            .sorted { $0.localizedStandardCompare($1) == .orderedAscending }
    }

    init?(files: [FileItem], catalog: URL?) {
        let keys = files.map { Self.memberKey(for: $0, catalog: catalog) }
        guard !keys.isEmpty else { return nil }
        self.init(memberKeys: keys)
    }

    static func memberKey(for file: FileItem, catalog: URL?) -> String {
        guard let catalog else { return file.name }

        let catalogPath = catalog.standardizedFileURL.path
        let filePath = file.url.standardizedFileURL.path
        let prefix = catalogPath.hasSuffix("/") ? catalogPath : catalogPath + "/"

        guard filePath.hasPrefix(prefix) else { return file.name }
        let relativePath = String(filePath.dropFirst(prefix.count))
        return relativePath.isEmpty ? file.name : relativePath
    }
}

struct BurstReviewStateSnapshot: Codable, Equatable {
    let signature: BurstGroupSignature
    let state: BurstReviewState
}

enum BurstGroupPrimaryAction: Equatable {
    case keepBest
    case compare
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
                decision: "Manual: \(frameText ?? "selected frame")",
                explanation: explanation(for: result, confidence: result.confidence),
                confidenceLabel: "Manual",
                primaryActionTitle: "Open burst",
                primaryAction: .compare,
                recommendedBadge: "Manual",
                showsAppliedStatus: applied,
            )
        }

        switch result.confidence {
        case .high:
            return BurstGroupPresentation(
                title: title,
                decision: "Best: \(frameText ?? "selected frame")",
                explanation: explanation(for: result, confidence: .high),
                confidenceLabel: BurstDecisionConfidence.high.title,
                primaryActionTitle: "Keep best",
                primaryAction: .keepBest,
                recommendedBadge: result.recommendedFileID == nil ? nil : "Best",
                showsAppliedStatus: applied,
            )

        case .medium:
            return BurstGroupPresentation(
                title: title,
                decision: "Suggested: \(frameText ?? "selected frame")",
                explanation: explanation(for: result, confidence: .medium),
                confidenceLabel: BurstDecisionConfidence.medium.title,
                primaryActionTitle: "Open burst",
                primaryAction: .compare,
                recommendedBadge: result.recommendedFileID == nil ? nil : "Suggested",
                showsAppliedStatus: applied,
            )

        case .low:
            return BurstGroupPresentation(
                title: title,
                decision: "Review needed",
                explanation: explanation(for: result, confidence: .low),
                confidenceLabel: BurstDecisionConfidence.low.title,
                primaryActionTitle: "Open burst",
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
