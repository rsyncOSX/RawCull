import Foundation
import RawCullCore

nonisolated struct BurstGroupSignature: Codable, Hashable {
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

    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.memberKeys == rhs.memberKeys
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(memberKeys)
    }
}

nonisolated struct BurstReviewStateSnapshot: Codable, Equatable, Sendable {
    let signature: BurstGroupSignature
    let state: BurstReviewState
}

/// Immutable configuration captured when a burst-analysis pass starts.
///
/// The version fields are deliberately values rather than reads of global
/// constants so a future coordinator can make every compatibility decision from
/// one request snapshot.
nonisolated struct BurstAnalysisPipelineConfiguration: Equatable, Sendable {
    let thumbnailMaxPixelSize: Int
    let grouping: BurstGroupingConfig
    let cacheSchemaVersion: Int
    let groupingAlgorithmVersion: Int
}

/// Pure input boundary for the existing burst-analysis pipeline.
nonisolated struct BurstAnalysisPipelineRequest: Equatable, Sendable {
    let catalogIdentity: URL
    let orderedFiles: [FileItem]
    let sharpnessSignature: BurstSharpnessSignature
    let similaritySignature: BurstSimilaritySignature
    let generation: Int
    let configuration: BurstAnalysisPipelineConfiguration
}

nonisolated enum BurstAnalysisCacheOutcome: Equatable, Sendable {
    case hit
    case miss
    case rejectedArtifactSet
}

nonisolated enum BurstAnalysisDiagnostic: Equatable, Sendable {
    case legacyMigrationCandidateFound
    case reusedSharpnessScores
    case scoredMissingSharpness
    case reusedSimilarityArtifacts
    case indexedMissingSimilarityArtifacts
    case cacheSaveRequested
}

/// Pure output boundary produced by the existing view-model implementation.
/// Worker ownership remains in `RawCullViewModel` until later Phase 7 subphases.
nonisolated struct BurstAnalysisPipelineResult: Equatable, Sendable {
    let groups: [BurstGroup]
    let rankings: [BurstAnalysisResult]
    let restoredReviewStates: [Int: BurstReviewState]
    let cacheOutcome: BurstAnalysisCacheOutcome
    let diagnostics: [BurstAnalysisDiagnostic]
}

/// Cache preparation returned by `BurstAnalysisCoordinator` before any missing
/// sharpness or similarity work begins.
nonisolated struct BurstAnalysisCachePreparation: Equatable {
    let compatibleSnapshot: BurstAnalysisCacheSnapshot?
    let migrationCandidate: BurstAnalysisCacheSnapshot?
    let restoredReviewStates: [Int: BurstReviewState]
    let cacheOutcome: BurstAnalysisCacheOutcome
    let diagnostics: [BurstAnalysisDiagnostic]
}

struct CompletedBurstAnalysisContext: Equatable {
    let catalog: URL
    let orderedFileIDs: [UUID]
    let orderedFilePaths: [String]
    let similaritySignature: BurstSimilaritySignature
    let generation: Int
}

enum BurstFullReindexRequest: Equatable, Identifiable {
    case analyzeBursts
    case catalogTools

    var id: Self {
        self
    }
}

struct BurstGroupPresentation: Equatable {
    nonisolated static func recommendationBadge(
        for candidate: BurstCandidateScore,
        in result: BurstAnalysisResult,
    ) -> String? {
        guard result.recommendedFileID == candidate.fileID else { return nil }

        if result.reviewState == .manualWinnerOverride {
            return "Manual"
        }

        switch result.confidence {
        case .high:
            return "Best"

        case .medium:
            return "Suggested"

        case .low:
            return "Check frame"
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
    let previousRatingsByFileName: [String: Int?]
}
