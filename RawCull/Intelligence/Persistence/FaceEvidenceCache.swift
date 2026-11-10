import CryptoKit
import Foundation
import OSLog
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

    static let previewMaximumDimension = 1600

    static func signature(sourceRevision: String) -> Signature {
        Signature(
            sourceRevision: sourceRevision,
            previewMaximumDimension: previewMaximumDimension,
            previewPipelineVersion: 1,
            algorithmVersion: FaceEvidenceAnalyzer.algorithmVersion,
            detectorRevision: FaceEvidenceAnalyzer.detectorRevision,
            operatingSystem: ProcessInfo.processInfo.operatingSystemVersionString,
        )
    }

    private struct Record: Codable {
        let signature: Signature
        let evidence: FaceEvidenceResult
    }

    func load(for url: URL, signature: Signature, width: Int? = nil, height: Int? = nil) -> FaceEvidenceResult? {
        let name = url.lastPathComponent
        let record: Record
        do {
            let data = try Data(contentsOf: recordURL(for: url))
            record = try JSONDecoder().decode(Record.self, from: data)
        } catch let error as CocoaError where error.code == .fileReadNoSuchFile {
            Logger.process.debugMessageOnly("FaceEvidenceCache: MISS \(name) (no saved record)")
            return nil
        } catch {
            Logger.process.debugMessageOnly("FaceEvidenceCache: READ FAILED \(name) (record unreadable or invalid)")
            return nil
        }
        guard record.signature == signature,
              record.evidence.algorithmVersion == signature.algorithmVersion,
              record.evidence.detectorRevision == signature.detectorRevision,
              record.evidence.previewWidth > 0,
              record.evidence.previewHeight > 0,
              width.map({ record.evidence.previewWidth == $0 }) ?? true,
              height.map({ record.evidence.previewHeight == $0 }) ?? true
        else {
            Logger.process.debugMessageOnly("FaceEvidenceCache: MISS \(name) (incompatible record)")
            return nil
        }
        Logger.process.debugMessageOnly("FaceEvidenceCache: HIT \(name) (\(record.evidence.faces.count) faces)")
        return record.evidence
    }

    func save(_ evidence: FaceEvidenceResult, for url: URL, signature: Signature) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let data = try JSONEncoder().encode(Record(signature: signature, evidence: evidence))
        try data.write(to: recordURL(for: url), options: .atomic)
    }

    /// Expire old evidence by write time. Records can be recreated from their sources.
    func pruneExpiredRecords(now: Date = .now) {
        let cutoff = now.addingTimeInterval(-30 * 24 * 60 * 60)
        let keys: Set<URLResourceKey> = [.isRegularFileKey, .contentModificationDateKey]
        guard let records = try? FileManager.default.contentsOfDirectory(
            at: directory, includingPropertiesForKeys: Array(keys), options: .skipsHiddenFiles
        ) else { return }

        for record in records where record.pathExtension == "json" {
            guard let values = try? record.resourceValues(forKeys: keys),
                  values.isRegularFile == true,
                  let modified = values.contentModificationDate, modified < cutoff
            else { continue }
            try? FileManager.default.removeItem(at: record)
        }
    }

    private func recordURL(for url: URL) -> URL {
        let path = url.standardizedFileURL.absoluteString
        let key = SHA256.hash(data: Data(path.utf8)).map { String(format: "%02x", $0) }.joined()
        return directory.appendingPathComponent(key).appendingPathExtension("json")
    }
}
