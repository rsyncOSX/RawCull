import CryptoKit
import Foundation
import PhotoAnalysisKit

/// The face loader owns this disposable cache. Records contain evidence only.
nonisolated struct FaceEvidenceCache: Sendable {
    let directory: URL

    init(directory: URL = URL.cachesDirectory
        .appendingPathComponent("RawCull/FaceEvidence", isDirectory: true)) {
        self.directory = directory
    }

    nonisolated struct Signature: Codable, Equatable, Sendable {
        let sourceRevision: String
        let previewMaximumDimension: Int
        let previewPipelineVersion: Int
        let algorithmVersion: Int
        let detectorRevision: Int
        let operatingSystem: String
    }

    private struct Record: Codable {
        let signature: Signature
        let evidence: FaceEvidenceResult
    }

    func load(for url: URL, signature: Signature, width: Int, height: Int) -> FaceEvidenceResult? {
        guard let data = try? Data(contentsOf: recordURL(for: url)),
              let record = try? JSONDecoder().decode(Record.self, from: data),
              record.signature == signature,
              record.evidence.algorithmVersion == signature.algorithmVersion,
              record.evidence.detectorRevision == signature.detectorRevision,
              record.evidence.previewWidth == width,
              record.evidence.previewHeight == height else { return nil }
        return record.evidence
    }

    func save(_ evidence: FaceEvidenceResult, for url: URL, signature: Signature) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let data = try JSONEncoder().encode(Record(signature: signature, evidence: evidence))
        try data.write(to: recordURL(for: url), options: .atomic)
    }

    private func recordURL(for url: URL) -> URL {
        let path = url.standardizedFileURL.absoluteString
        let key = SHA256.hash(data: Data(path.utf8)).map { String(format: "%02x", $0) }.joined()
        return directory.appendingPathComponent(key).appendingPathExtension("json")
    }
}
