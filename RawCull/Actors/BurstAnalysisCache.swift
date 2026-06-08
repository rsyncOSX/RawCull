import Foundation
import RawCullCore

struct BurstAnalysisCacheSnapshot: Codable, Equatable {
    var schemaVersion: Int
    var algorithmVersion: Int
    var catalogPath: String
    var thumbnailMaxPixelSize: Int
    var sharpnessSignature: BurstSharpnessSignature
    var files: [BurstAnalysisCacheFile]
    var embeddings: [UUID: Data]
    var sharpnessScores: [UUID: Float]
    var saliencyInfo: [UUID: SaliencyInfo]
    var groups: [BurstGroup]
    var boundaryEvidence: [BurstBoundaryEvidence]
    var results: [BurstAnalysisResult]
    var reviewStateSnapshots: [BurstReviewStateSnapshot]
}

struct SharpnessScoringSignature: Codable {
    nonisolated static let currentAlgorithmVersion = 3
    nonisolated static let currentISOScalingPolicyVersion = 1
    nonisolated static let currentApertureHintPolicyVersion = 1
    nonisolated static let stableScoringEnergyMultiplier: Float = 7.62

    var algorithmVersion: Int
    var isoScalingPolicyVersion: Int
    var apertureHintPolicyVersion: Int
    var scoringPhotoType: SharpnessPhotoType
    var scoringQuality: SharpnessScoringQuality
    var scoringSource: SharpnessScoringSource
    var thumbnailMaxPixelSize: Int
    var preBlurRadius: Float
    var borderInsetFraction: Float
    var salientWeight: Float
    var explicitSalientWeightOverride: Float?
    var subjectSizeFactor: Float
    var silhouettePenaltyStrength: Float
    var afRegionRadius: Float
    var fineDetailBlendWeight: Float
    var stableScoringEnergyMultiplier: Float

    @MainActor
    init(
        photoType: SharpnessPhotoType,
        scoringQuality: SharpnessScoringQuality,
        scoringSource: SharpnessScoringSource = .embeddedPreview,
        thumbnailMaxPixelSize: Int,
        config: FocusDetectorConfig,
    ) {
        self.algorithmVersion = Self.currentAlgorithmVersion
        self.isoScalingPolicyVersion = Self.currentISOScalingPolicyVersion
        self.apertureHintPolicyVersion = Self.currentApertureHintPolicyVersion
        self.scoringPhotoType = photoType
        self.scoringQuality = scoringQuality
        self.scoringSource = scoringSource
        self.thumbnailMaxPixelSize = thumbnailMaxPixelSize
        self.preBlurRadius = config.preBlurRadius
        self.borderInsetFraction = config.borderInsetFraction
        self.salientWeight = config.salientWeight
        self.explicitSalientWeightOverride = config.explicitSalientWeightOverride
        self.subjectSizeFactor = config.subjectSizeFactor
        self.silhouettePenaltyStrength = config.silhouettePenaltyStrength
        self.afRegionRadius = config.afRegionRadius
        self.fineDetailBlendWeight = config.fineDetailBlendWeight
        self.stableScoringEnergyMultiplier = Self.stableScoringEnergyMultiplier
    }
}

extension SharpnessScoringSignature: Equatable {
    nonisolated static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.algorithmVersion == rhs.algorithmVersion
            && lhs.isoScalingPolicyVersion == rhs.isoScalingPolicyVersion
            && lhs.apertureHintPolicyVersion == rhs.apertureHintPolicyVersion
            && lhs.scoringPhotoType.rawValue == rhs.scoringPhotoType.rawValue
            && lhs.scoringQuality.rawValue == rhs.scoringQuality.rawValue
            && lhs.scoringSource.rawValue == rhs.scoringSource.rawValue
            && lhs.thumbnailMaxPixelSize == rhs.thumbnailMaxPixelSize
            && lhs.preBlurRadius == rhs.preBlurRadius
            && lhs.borderInsetFraction == rhs.borderInsetFraction
            && lhs.salientWeight == rhs.salientWeight
            && lhs.explicitSalientWeightOverride == rhs.explicitSalientWeightOverride
            && lhs.subjectSizeFactor == rhs.subjectSizeFactor
            && lhs.silhouettePenaltyStrength == rhs.silhouettePenaltyStrength
            && lhs.afRegionRadius == rhs.afRegionRadius
            && lhs.fineDetailBlendWeight == rhs.fineDetailBlendWeight
            && lhs.stableScoringEnergyMultiplier == rhs.stableScoringEnergyMultiplier
    }
}

typealias BurstSharpnessSignature = SharpnessScoringSignature

struct BurstAnalysisCacheFile: Codable, Equatable {
    var id: UUID
    var path: String
    var size: Int64
    var modificationDate: Date
}

actor BurstAnalysisCache {
    static let shared = BurstAnalysisCache()
    nonisolated static let schemaVersion = 3

    private let cacheDirectory: URL

    init(cacheDirectory: URL? = nil) {
        if let cacheDirectory {
            self.cacheDirectory = cacheDirectory
        } else {
            let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
                ?? FileManager.default.temporaryDirectory
            self.cacheDirectory = base
                .appendingPathComponent("RawCull", isDirectory: true)
                .appendingPathComponent("BurstAnalysis", isDirectory: true)
        }
    }

    func load(
        catalog: URL,
        files: [FileItem],
        thumbnailMaxPixelSize: Int,
        sharpnessSignature: BurstSharpnessSignature,
    ) async -> BurstAnalysisCacheSnapshot? {
        let url = cacheURL(for: catalog)
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        do {
            let data = try Data(contentsOf: url)
            let snapshot = try await MainActor.run {
                try JSONDecoder().decode(BurstAnalysisCacheSnapshot.self, from: data)
            }
            guard isValid(
                snapshot,
                catalog: catalog,
                files: files,
                thumbnailMaxPixelSize: thumbnailMaxPixelSize,
                sharpnessSignature: sharpnessSignature,
            ) else {
                return nil
            }
            return snapshot
        } catch {
            return nil
        }
    }

    func save(_ snapshot: BurstAnalysisCacheSnapshot, catalog: URL) async {
        do {
            try FileManager.default.createDirectory(at: cacheDirectory, withIntermediateDirectories: true)
            let data = try await MainActor.run {
                try JSONEncoder().encode(snapshot)
            }
            try data.write(to: cacheURL(for: catalog), options: [.atomic])
        } catch {
            return
        }
    }

    func delete(catalog: URL) async {
        let url = cacheURL(for: catalog)
        guard FileManager.default.fileExists(atPath: url.path) else { return }
        do {
            try FileManager.default.removeItem(at: url)
        } catch {
            return
        }
    }

    private func isValid(
        _ snapshot: BurstAnalysisCacheSnapshot,
        catalog: URL,
        files: [FileItem],
        thumbnailMaxPixelSize: Int,
        sharpnessSignature: BurstSharpnessSignature,
    ) -> Bool {
        guard snapshot.schemaVersion == Self.schemaVersion,
              snapshot.algorithmVersion == BurstGroupingConfig.algorithmVersion,
              snapshot.catalogPath == catalog.path,
              snapshot.thumbnailMaxPixelSize == thumbnailMaxPixelSize,
              snapshot.sharpnessSignature == sharpnessSignature,
              snapshot.files.count == files.count
        else { return false }

        let cached = Dictionary(uniqueKeysWithValues: snapshot.files.map { ($0.path, $0) })
        for file in files {
            guard let item = cached[file.url.path],
                  item.size == file.size,
                  abs(item.modificationDate.timeIntervalSince(file.dateModified)) < 0.001
            else { return false }
        }
        return true
    }

    private func cacheURL(for catalog: URL) -> URL {
        cacheDirectory.appendingPathComponent(cacheFileName(for: catalog), isDirectory: false)
    }

    private nonisolated func cacheFileName(for catalog: URL) -> String {
        let safe = Data(catalog.path.utf8)
            .base64EncodedString()
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "=", with: "")
        return "\(safe).json"
    }
}
