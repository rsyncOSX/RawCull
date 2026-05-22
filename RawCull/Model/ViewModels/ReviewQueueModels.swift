import Foundation

enum ReviewQueueCategory: String, CaseIterable, Codable, Identifiable {
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

enum ReviewQueueSeverity: String, Codable, Comparable {
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

enum ReviewQueueResolutionState: String, Codable {
    case open
    case resolved
    case ignored
    case stale
}

enum ReviewQueueSource: String, Codable {
    case burstAnalysis
    case sharpnessScoring
    case rawDiagnostics
    case rsyncCopy
    case catalogHealth
}

struct ReviewQueueItem: Identifiable, Codable, Equatable, Hashable {
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

struct ReviewQueueItemState: Identifiable, Codable, Equatable, Hashable {
    var id: String {
        fingerprint
    }

    var fingerprint: String
    var resolutionState: ReviewQueueResolutionState
    var resolvedAt: Date?
}

enum ReviewQueueFingerprint {
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

struct RawFileDiagnosticIssue: Identifiable, Equatable, Hashable {
    var id: String {
        "\(category.rawValue)|\(fileName)|\(message)"
    }

    var fileName: String
    var category: ReviewQueueCategory
    var severity: ReviewQueueSeverity
    var message: String
    var recoveryHint: String
}
