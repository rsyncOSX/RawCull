import Foundation

nonisolated enum ReviewQueueCategory: String, CaseIterable, Codable, Identifiable, Sendable {
    case burst
    case sharpness
    case parser
    case metadata
    case copy
    case catalog
    case cache

    var id: String {
        rawValue
    }

    var title: String {
        switch self {
        case .burst: "Burst"
        case .sharpness: "Sharpness"
        case .parser: "Parser"
        case .metadata: "Metadata"
        case .copy: "Copy"
        case .catalog: "Catalog"
        case .cache: "Cache"
        }
    }
}

nonisolated enum ReviewQueueSeverity: String, Codable, Comparable, Sendable {
    case info
    case warning
    case blocking

    private var sortRank: Int {
        switch self {
        case .info: 0
        case .warning: 1
        case .blocking: 2
        }
    }

    static func < (lhs: ReviewQueueSeverity, rhs: ReviewQueueSeverity) -> Bool {
        lhs.sortRank < rhs.sortRank
    }
}

nonisolated enum ReviewQueueResolutionState: String, Codable, Sendable {
    case open
    case resolved
    case ignored
    case stale
}

nonisolated enum ReviewQueueSource: String, Codable, Sendable {
    case burstAnalysis
    case sharpnessScoring
    case rawDiagnostics
    case rsyncCopy
    case catalogHealth
}

nonisolated struct ReviewQueueItem: Identifiable, Codable, Equatable, Hashable, Sendable {
    var id: String {
        fingerprint
    }

    var category: ReviewQueueCategory
    var severity: ReviewQueueSeverity
    var resolutionState: ReviewQueueResolutionState
    var fileName: String?
    var fileID: UUID?
    var groupID: Int?
    var relatedFileNames: [String]
    var title: String
    var detail: String
    var recommendedAction: String
    var source: ReviewQueueSource
    var createdAt: Date
    var resolvedAt: Date?
    var fingerprint: String

    var isOpenAttentionItem: Bool {
        resolutionState == .open && severity != .info
    }
}

nonisolated struct ReviewQueueItemState: Identifiable, Codable, Equatable, Hashable, Sendable {
    var id: String {
        fingerprint
    }

    var fingerprint: String
    var resolutionState: ReviewQueueResolutionState
    var resolvedAt: Date?
}

nonisolated enum ReviewQueueFingerprint {
    static func make(
        catalog: URL?,
        category: ReviewQueueCategory,
        subject: String,
        reason: String,
    ) -> String {
        [
            catalog?.standardizedFileURL.path ?? "no-catalog",
            category.rawValue,
            subject,
            reason
        ]
        .map(normalize)
        .joined(separator: "|")
    }

    private static func normalize(_ value: String) -> String {
        value
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
    }
}

nonisolated struct RawFileDiagnosticIssue: Identifiable, Equatable, Hashable, Sendable {
    var id: String {
        "\(category.rawValue)|\(fileName)|\(message)"
    }

    var fileName: String
    var category: ReviewQueueCategory
    var severity: ReviewQueueSeverity
    var message: String
    var recoveryHint: String
}
