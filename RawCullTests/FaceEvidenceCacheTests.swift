import Foundation
import PhotoAnalysisKit
@testable import RawCull
import Testing

struct FaceEvidenceCacheTests {
    @Test func reopensEvidenceAndInvalidatesOnlyTheChangedSource() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let first = directory.appendingPathComponent("first.CR2")
        let second = directory.appendingPathComponent("second.CR2")
        let evidence = try JSONDecoder().decode(FaceEvidenceResult.self, from: Data("""
        {"algorithmVersion":2,"detectorRevision":3,"previewWidth":120,"previewHeight":80,"faces":[]}
        """.utf8))
        func signature(_ revision: String) -> FaceEvidenceCache.Signature {
            .init(sourceRevision: revision, previewMaximumDimension: 1600, previewPipelineVersion: 1,
                  algorithmVersion: 2, detectorRevision: 3, operatingSystem: "test")
        }

        let cache = FaceEvidenceCache(directory: directory)
        try cache.save(evidence, for: first, signature: signature("first-v1"))
        try cache.save(evidence, for: second, signature: signature("second-v1"))

        let reopened = FaceEvidenceCache(directory: directory)
        #expect(reopened.load(for: first, signature: signature("first-v1"), width: 120, height: 80) == evidence)
        #expect(reopened.load(for: first, signature: signature("first-v2"), width: 120, height: 80) == nil)
        #expect(reopened.load(for: first, signature: signature("first-v1"), width: 80, height: 120) == nil)
        #expect(reopened.load(for: second, signature: signature("second-v1"), width: 120, height: 80) == evidence)

        let records = try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
        for record in records {
            try Data("corrupt".utf8).write(to: record)
        }
        #expect(reopened.load(for: second, signature: signature("second-v1"), width: 120, height: 80) == nil)
    }
}
