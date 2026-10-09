import CryptoKit
import Foundation

nonisolated struct ReviewStorageEnvelopeV1<Value: Codable & Sendable>: Codable, Sendable {
    let schemaVersion: Int
    let kind: String
    let producerPipelineVersion: String
    let compatibility: ReviewCompatibility
    let value: Value
}

nonisolated struct ReviewEnvelopeHeader: Decodable {
    let schemaVersion: Int
    let kind: String
    let producerPipelineVersion: String
}

actor ReviewArtifactStore {
    nonisolated let root: URL
    let maximumInputBytes: Int

    init(root: URL? = nil, maximumInputBytes: Int = 256_000_000) {
        self.root = root ?? (FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory).appendingPathComponent("RawCull/AnalysisArtifacts/CombinedReview")
        self.maximumInputBytes = max(0, maximumInputBytes)
    }

    func saveManifest(_ manifest: CombinedReviewRunV1) throws {
        try manifest.validate()
        let envelope = ReviewStorageEnvelopeV1(schemaVersion: 1, kind: "run", producerPipelineVersion: manifest.snapshot.pipelineVersion,
                                               compatibility: ReviewCompatibility(fields: ["run": manifest.snapshot.id.uuidString]), value: manifest)
        try write(envelope, to: manifestURL(manifest.snapshot.id))
    }

    func latestManifest() throws -> CombinedReviewRunV1? {
        let directory = root.appendingPathComponent("runs")
        guard FileManager.default.fileExists(atPath: directory.path) else { return nil }
        let urls = try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: [.contentModificationDateKey])
        let ordered = try urls.map { try ($0, $0.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate ?? .distantPast) }.sorted { $0.1 > $1.1 }
        guard let url = ordered.first?.0, let id = UUID(uuidString: url.deletingPathExtension().lastPathComponent) else { return nil }
        return try loadManifest(id)
    }

    func loadManifest(_ id: UUID) throws -> CombinedReviewRunV1 {
        let data = try readHeader(at: manifestURL(id), kind: "run")
        let envelope = try JSONDecoder().decode(ReviewStorageEnvelopeV1<CombinedReviewRunV1>.self, from: data)
        guard envelope.producerPipelineVersion == envelope.value.snapshot.pipelineVersion else { throw ReviewRunError.corrupt }
        try envelope.value.validate()
        return envelope.value
    }

    /// Synchronous actor transaction: cancellation checked before the completed
    /// artifact is committed, then manifest written without a suspension point.
    func commit(_ artifact: ReviewStageArtifact, manifest: CombinedReviewRunV1) throws {
        try Task.checkCancellation()
        guard let item = manifest.work.first(where: { $0.id == artifact.workID }), item.state == .completed,
              item.compatibility == artifact.compatibility, item.artifactKey == artifactKey(artifact.workID, compatibility: artifact.compatibility)
        else {
            throw ReviewRunError.incompatible
        }
        let envelope = ReviewStorageEnvelopeV1(schemaVersion: 1, kind: "stage", producerPipelineVersion: manifest.snapshot.pipelineVersion,
                                               compatibility: artifact.compatibility, value: artifact)
        try write(envelope, to: artifactURL(item.artifactKey ?? ""))
        try saveManifest(manifest)
    }

    nonisolated func artifactKey(_ id: ReviewWorkID, compatibility: ReviewCompatibility) -> String {
        ReviewCompatibility.digest("\(id.rawValue)|\(compatibility.key)")
    }

    func loadArtifact(key: String, expected: ReviewCompatibility) throws -> ReviewStageArtifact {
        let data = try readHeader(at: artifactURL(key), kind: "stage")
        let envelope = try JSONDecoder().decode(ReviewStorageEnvelopeV1<ReviewStageArtifact>.self, from: data)
        guard envelope.compatibility == expected, envelope.value.compatibility == expected,
              expected.fields["pipeline"] == nil || expected.fields["pipeline"] == envelope.producerPipelineVersion else { throw ReviewRunError.incompatible }
        return envelope.value
    }

    func validArtifactKeys(for manifest: CombinedReviewRunV1) -> Set<String> {
        Set(manifest.work.compactMap { item in
            guard let key = item.artifactKey, let artifact = try? loadArtifact(key: key, expected: item.compatibility),
                  artifact.workID == item.id else { return nil }
            return key
        })
    }

    func retainInput(_ data: Data) throws -> String {
        guard data.count <= maximumInputBytes else { throw ReviewRunError.storageLimit }
        let key = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
        let directory = root.appendingPathComponent("inputs")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appendingPathComponent(key + ".png")
        try data.write(to: url, options: .atomic)
        try FileManager.default.setAttributes([.modificationDate: Date()], ofItemAtPath: url.path)
        try evictInputs()
        return key
    }

    func input(_ key: String) throws -> Data {
        guard isKey(key) else { throw ReviewRunError.corrupt }
        let url = root.appendingPathComponent("inputs/\(key).png")
        let data = try Data(contentsOf: url)
        guard SHA256.hash(data: data).map({ String(format: "%02x", $0) }).joined() == key else { throw ReviewRunError.corrupt }
        try FileManager.default.setAttributes([.modificationDate: Date()], ofItemAtPath: url.path)
        return data
    }

    func clearInputs() throws {
        let directory = root.appendingPathComponent("inputs")
        if FileManager.default.fileExists(atPath: directory.path) {
            try FileManager.default.removeItem(at: directory)
        }
    }

    private func evictInputs() throws {
        let urls = try FileManager.default.contentsOfDirectory(at: root.appendingPathComponent("inputs"), includingPropertiesForKeys: [.fileSizeKey, .contentModificationDateKey])
        let entries = try urls.map { url in try (url, url.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey])) }
            .sorted { ($0.1.contentModificationDate ?? .distantPast) < ($1.1.contentModificationDate ?? .distantPast) }
        var total = entries.reduce(0) { $0 + ($1.1.fileSize ?? 0) }
        for entry in entries where total > maximumInputBytes {
            try FileManager.default.removeItem(at: entry.0)
            total -= entry.1.fileSize ?? 0
        }
    }

    private func write(_ envelope: ReviewStorageEnvelopeV1<some Any>, to url: URL) throws {
        if FileManager.default.fileExists(atPath: url.path) {
            _ = try readHeader(at: url, kind: envelope.kind)
        }
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
        try encoder.encode(envelope).write(to: url, options: .atomic)
    }

    private func readHeader(at url: URL, kind: String) throws -> Data {
        let data = try Data(contentsOf: url)
        let header = try JSONDecoder().decode(ReviewEnvelopeHeader.self, from: data)
        guard header.schemaVersion == 1 else { throw ReviewRunError.unsupportedVersion(header.schemaVersion) }
        guard header.kind == kind else { throw ReviewRunError.corrupt }
        return data
    }

    private func manifestURL(_ id: UUID) -> URL {
        root.appendingPathComponent("runs/\(id.uuidString).json")
    }

    private func artifactURL(_ key: String) -> URL {
        root.appendingPathComponent("stages/\(ReviewCompatibility.digest(key)).json")
    }

    private func isKey(_ key: String) -> Bool {
        key.count == 64 && key.allSatisfy { $0.isHexDigit && !$0.isUppercase }
    }
}
