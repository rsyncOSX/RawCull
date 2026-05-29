import Foundation

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
    var reviewStates: [Int: BurstReviewState]
}

struct BurstSharpnessSignature: Codable {
    var scoringPhotoType: SharpnessPhotoType
    var scoringQuality: SharpnessScoringQuality
    var thumbnailMaxPixelSize: Int
    var borderInsetFraction: Float
    var enableSubjectClassification: Bool
    var salientWeight: Float
    var subjectSizeFactor: Float
    var fineDetailBlendWeight: Float
    var focusMaskPreBlurRadius: Float
    var focusMaskThreshold: Float
    var focusMaskEnergyMultiplier: Float
    var focusMaskErosionRadius: Float
    var focusMaskDilationRadius: Float
    var focusMaskFeatherRadius: Float

    @MainActor
    init(
        photoType: SharpnessPhotoType,
        scoringQuality: SharpnessScoringQuality,
        thumbnailMaxPixelSize: Int,
        config: FocusDetectorConfig,
    ) {
        self.scoringPhotoType = photoType
        self.scoringQuality = scoringQuality
        self.thumbnailMaxPixelSize = thumbnailMaxPixelSize
        self.borderInsetFraction = config.borderInsetFraction
        self.enableSubjectClassification = config.enableSubjectClassification
        self.salientWeight = config.salientWeight
        self.subjectSizeFactor = config.subjectSizeFactor
        self.fineDetailBlendWeight = config.fineDetailBlendWeight
        self.focusMaskPreBlurRadius = config.preBlurRadius
        self.focusMaskThreshold = config.threshold
        self.focusMaskEnergyMultiplier = config.energyMultiplier
        self.focusMaskErosionRadius = config.erosionRadius
        self.focusMaskDilationRadius = config.dilationRadius
        self.focusMaskFeatherRadius = config.featherRadius
    }
}

extension BurstSharpnessSignature: Equatable {
    nonisolated static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.scoringPhotoType.rawValue == rhs.scoringPhotoType.rawValue
            && lhs.scoringQuality.rawValue == rhs.scoringQuality.rawValue
            && lhs.thumbnailMaxPixelSize == rhs.thumbnailMaxPixelSize
            && lhs.borderInsetFraction == rhs.borderInsetFraction
            && lhs.enableSubjectClassification == rhs.enableSubjectClassification
            && lhs.salientWeight == rhs.salientWeight
            && lhs.subjectSizeFactor == rhs.subjectSizeFactor
            && lhs.fineDetailBlendWeight == rhs.fineDetailBlendWeight
            && lhs.focusMaskPreBlurRadius == rhs.focusMaskPreBlurRadius
            && lhs.focusMaskThreshold == rhs.focusMaskThreshold
            && lhs.focusMaskEnergyMultiplier == rhs.focusMaskEnergyMultiplier
            && lhs.focusMaskErosionRadius == rhs.focusMaskErosionRadius
            && lhs.focusMaskDilationRadius == rhs.focusMaskDilationRadius
            && lhs.focusMaskFeatherRadius == rhs.focusMaskFeatherRadius
    }
}

struct BurstAnalysisCacheFile: Codable, Equatable {
    var id: UUID
    var path: String
    var size: Int64
    var modificationDate: Date
}

actor BurstAnalysisCache {
    static let shared = BurstAnalysisCache()
    nonisolated static let schemaVersion = 1

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
