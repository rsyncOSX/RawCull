import CryptoKit
import Foundation

nonisolated struct ReviewID<Kind: Sendable>: RawRepresentable, Codable, Hashable, Sendable {
    let rawValue: String
}

nonisolated enum ReviewImageKind: Sendable {}
nonisolated enum ReviewSubjectKind: Sendable {}
nonisolated enum ReviewRegionKind: Sendable {}
nonisolated enum ReviewObservationKind: Sendable {}
nonisolated enum ReviewMeasurementKind: Sendable {}
nonisolated enum ReviewLimitationKind: Sendable {}
nonisolated enum ReviewReportKind: Sendable {}
nonisolated enum ReviewWorkKind: Sendable {}

typealias ReviewImageID = ReviewID<ReviewImageKind>
typealias ReviewSubjectID = ReviewID<ReviewSubjectKind>
typealias ReviewRegionID = ReviewID<ReviewRegionKind>
typealias ReviewObservationID = ReviewID<ReviewObservationKind>
typealias ReviewMeasurementID = ReviewID<ReviewMeasurementKind>
typealias ReviewLimitationID = ReviewID<ReviewLimitationKind>
typealias ReviewReportID = ReviewID<ReviewReportKind>
typealias ReviewWorkID = ReviewID<ReviewWorkKind>

nonisolated enum ReviewDepth: String, Codable, CaseIterable, Sendable {
    case standard, deep, exhaustive
    var cropsPerImage: Int {
        switch self { case .standard: 3
        case .deep: 8
        case .exhaustive: 16 }
    }

    var selectionCrops: Int {
        switch self { case .standard: 16
        case .deep: 32
        case .exhaustive: 64 }
    }

    var followupsPerImage: Int {
        switch self { case .standard: 0
        case .deep: 2
        case .exhaustive: 4 }
    }

    var selectionFollowups: Int {
        switch self { case .standard: 0
        case .deep: 8
        case .exhaustive: 16 }
    }

    var pairCap: Int {
        switch self { case .standard: 0
        case .deep: 2
        case .exhaustive: 4 }
    }
}

nonisolated struct ReviewFileSnapshot: Codable, Equatable, Sendable {
    let id: ReviewImageID
    let fileID: UUID
    let url: URL
    let displayName: String
    let fingerprint: String

    static func fingerprint(_ url: URL) throws -> String {
        let values = try url.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey, .fileResourceIdentifierKey])
        guard values.fileSize != nil else { throw ReviewRunError.sourceUnavailable }
        return ReviewCompatibility.digest("\(url.standardizedFileURL.path)|\(values.fileSize ?? -1)|\(values.contentModificationDate?.timeIntervalSince1970 ?? -1)|\(String(describing: values.fileResourceIdentifier))")
    }
}

nonisolated struct ReviewModelSnapshot: Codable, Equatable, Sendable {
    let identity: String
    let runtimeVersion: String
    let preprocessing: String
    let encoderWidth: Int
    let encoderHeight: Int
    let contextTokens: Int?
    let imageTokens: Int?
}

nonisolated enum ReviewInputRetentionPolicy: String, Codable, Sendable {
    case compact, exactInputs
}

nonisolated struct ReviewUserRegion: Codable, Equatable, Sendable {
    let imageID: ReviewImageID
    let normalizedRect: CGRect
    let purpose: String
}

/// A pipeline contract may intentionally retain unchanged stage schemas.
nonisolated enum ReviewPipelineContract {
    static let version = "combined-v2"
    static let renderVersion = "review-srgb-v1"
    static let stageVersions = Dictionary(uniqueKeysWithValues: ReviewStage.allCases.map {
        ($0, [.cropObservation, .reconciliation, .report].contains($0) ? "combined-v2" : "combined-v1")
    })

    static func validate(_ snapshot: ReviewRunSnapshot) throws {
        guard snapshot.pipelineVersion == version, snapshot.renderVersion == renderVersion,
              snapshot.stageVersions == stageVersions else { throw ReviewRunError.incompatible }
    }
}

nonisolated struct ReviewRunSnapshot: Codable, Equatable, Sendable {
    let id: UUID
    let files: [ReviewFileSnapshot]
    let criteria: String
    let depth: ReviewDepth
    let sourcePreference: String
    let retentionPolicy: ReviewInputRetentionPolicy
    let renderVersion: String
    let models: [String: ReviewModelSnapshot]
    let stageVersions: [ReviewStage: String]
    let responseTokens: Int
    let pipelineVersion: String
    let created: Date
    let expandedSelectionPlan: String?
    var userRegions: [ReviewUserRegion]?

    func validate() throws {
        for region in userRegions ?? [] {
            guard files.contains(where: { $0.id == region.imageID }), region.normalizedRect.isFiniteReviewRect,
                  CGRect(x: 0, y: 0, width: 1, height: 1).contains(region.normalizedRect), !region.purpose.isEmpty else { throw ReviewRunError.invalidSnapshot }
        }
        guard !files.isEmpty, files.count <= 8 || !(expandedSelectionPlan?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true),
              Set(files.map(\.id)).count == files.count,
              Set(files.map(\.fileID)).count == files.count,
              !criteria.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              ReviewSourcePreference(rawValue: sourcePreference) != nil,
              (1 ... 4096).contains(responseTokens) else { throw ReviewRunError.invalidSnapshot }
    }
}

nonisolated enum ReviewStage: String, Codable, CaseIterable, Sendable {
    case source, overview, segmentation, identity, measurement, clip, cropObservation, reconciliation, report, comparison
    var goalDependent: Bool {
        self == .clip || self == .cropObservation || self == .reconciliation || self == .report || self == .comparison
    }

    var modelKey: String? {
        switch self {
        case .overview, .cropObservation, .reconciliation, .report, .comparison: "qwen"
        case .segmentation: "sam"
        case .clip: "clip"
        default: nil
        }
    }
}

nonisolated struct ReviewCompatibility: Codable, Equatable, Sendable {
    let fields: [String: String]
    var key: String {
        Self.digest(fields.keys.sorted().map { "\($0)=\(fields[$0] ?? "")" }.joined(separator: "\n"))
    }

    static func make(snapshot: ReviewRunSnapshot, image: ReviewFileSnapshot, stage: ReviewStage,
                     sourceRender: String = "", region: String = "") throws -> Self
    {
        var fields = ["file": image.fingerprint, "render": snapshot.renderVersion,
                      "sourcePreference": snapshot.sourcePreference, "sourceRender": sourceRender,
                      "pipeline": snapshot.pipelineVersion, "stage": stage.rawValue,
                      "stageVersion": snapshot.stageVersions[stage] ?? "unversioned", "region": region]
        if stage == .comparison {
            fields["selection"] = snapshot.files.sorted { $0.id.rawValue < $1.id.rawValue }.map { $0.id.rawValue + ":" + $0.fingerprint }.joined(separator: "|")
        }
        if stage.goalDependent {
            fields["criteria"] = snapshot.criteria
        }
        if let key = stage.modelKey {
            guard let model = snapshot.models[key] else { throw ReviewRunError.modelUnavailable }
            fields["model"] = model.identity
            fields["runtime"] = model.runtimeVersion
            fields["preprocessing"] = model.preprocessing
            fields["encoder"] = "\(model.encoderWidth)x\(model.encoderHeight)"
            if key == "qwen" {
                fields["responseTokens"] = String(snapshot.responseTokens)
            }
        }
        if stage == .identity || stage.goalDependent {
            let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
            fields["userRegions"] = try Self.digest(String(decoding: encoder.encode(snapshot.userRegions), as: UTF8.self))
            fields["depth"] = snapshot.depth.rawValue
        }
        return Self(fields: fields)
    }

    static func digest(_ text: String) -> String {
        SHA256.hash(data: Data(text.utf8)).map { String(format: "%02x", $0) }.joined()
    }
}

nonisolated enum ReviewRunError: Error {
    case invalidSnapshot, sourceUnavailable, modelUnavailable, invalidDependency, invalidTransition, budgetExhausted
    case incompatible, corrupt, unsupportedVersion(Int), storageLimit, invalidEvidence
}
