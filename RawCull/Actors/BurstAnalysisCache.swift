import Foundation

struct BurstAnalysisCacheSnapshot: Codable, Equatable {
    var schemaVersion: Int
    var algorithmVersion: Int
    var catalogPath: String
    var thumbnailMaxPixelSize: Int
    var files: [BurstAnalysisCacheFile]
    var embeddings: [UUID: Data]
    var sharpnessScores: [UUID: Float]
    var saliencyInfo: [UUID: SaliencyInfo]
    var groups: [BurstGroup]
    var boundaryEvidence: [BurstBoundaryEvidence]
    var results: [BurstAnalysisResult]
    var reviewStates: [Int: BurstReviewState]
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

    func load(catalog: URL, files: [FileItem], thumbnailMaxPixelSize: Int) async -> BurstAnalysisCacheSnapshot? {
        let url = cacheURL(for: catalog)
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        do {
            let data = try Data(contentsOf: url)
            let snapshot = try await MainActor.run {
                try JSONDecoder().decode(BurstAnalysisCacheSnapshot.self, from: data)
            }
            guard isValid(snapshot, catalog: catalog, files: files, thumbnailMaxPixelSize: thumbnailMaxPixelSize) else {
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

    private func isValid(
        _ snapshot: BurstAnalysisCacheSnapshot,
        catalog: URL,
        files: [FileItem],
        thumbnailMaxPixelSize: Int,
    ) -> Bool {
        guard snapshot.schemaVersion == Self.schemaVersion,
              snapshot.algorithmVersion == BurstGroupingConfig.algorithmVersion,
              snapshot.catalogPath == catalog.path,
              snapshot.thumbnailMaxPixelSize == thumbnailMaxPixelSize,
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
