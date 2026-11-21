import Foundation
import PhotoAIContracts
@testable import RawCull
import RawCullCore
import Testing

/// `JSONEncoder` throws on NaN and infinite floating-point values. A cache key
/// that falls back to hashing empty data on that failure maps every such input
/// to one shared key, so these tests pin that a NaN never produces a shared key.
@Suite("Cache keys never collapse when encoding fails")
struct CacheKeyEncodingFailureTests {
    private static let backend = SimilarityBackendDescriptor(
        backend: "nan-test",
        modelFingerprint: "nan-test",
        representation: "float32",
        preprocessingVersion: "v1",
        normalizationVersion: "v1",
        configurationVersion: "v1",
    )

    private static func file(_ name: String) -> FileItem {
        FileItem(
            id: UUID(),
            url: URL(filePath: "/tmp/\(name)"),
            name: name,
            size: 1,
            dateModified: .distantPast,
            exifData: nil,
            afFocusNormalized: nil,
        )
    }

    private static func artifact(path: String, modificationDate: Date?) -> SimilarityArtifact {
        SimilarityArtifact(
            descriptor: SimilarityArtifactDescriptor(
                backend: backend,
                dimensions: 1,
                sourceFingerprint: SourceFingerprint(
                    standardizedPath: path,
                    fileSize: 1,
                    modificationDate: modificationDate,
                ),
            ),
            payload: Data([1]),
        )
    }

    private static let nanDate = Date(timeIntervalSinceReferenceDate: .nan)

    @Test
    func `NaN artifact set digests are never shared`() {
        let first = Self.file("a.ARW")
        let second = Self.file("b.ARW")
        let firstDigest = BurstAnalysisCache.artifactSetDigest(
            files: [first],
            artifacts: [first.id: Self.artifact(path: first.url.path, modificationDate: Self.nanDate)],
        )
        let secondDigest = BurstAnalysisCache.artifactSetDigest(
            files: [second],
            artifacts: [second.id: Self.artifact(path: second.url.path, modificationDate: Self.nanDate)],
        )
        let repeatedDigest = BurstAnalysisCache.artifactSetDigest(
            files: [first],
            artifacts: [first.id: Self.artifact(path: first.url.path, modificationDate: Self.nanDate)],
        )
        let emptyDataDigest = BurstAnalysisCache.artifactSetDigest(files: [], artifacts: [:])

        #expect(firstDigest != secondDigest)
        // An unencodable set must not match even itself, so a snapshot saved
        // with it can never be accepted.
        #expect(firstDigest != repeatedDigest)
        #expect(firstDigest != emptyDataDigest)
    }

    @Test
    func `encodable artifact set digests stay stable`() {
        let file = Self.file("a.ARW")
        let artifacts = [file.id: Self.artifact(path: file.url.path, modificationDate: .distantPast)]
        #expect(
            BurstAnalysisCache.artifactSetDigest(files: [file], artifacts: artifacts)
                == BurstAnalysisCache.artifactSetDigest(files: [file], artifacts: artifacts),
        )
    }

    @Test
    func `NaN record identity has no cache key`() {
        let nanFingerprint = SourceFingerprint(
            standardizedPath: "/tmp/a.ARW",
            fileSize: 1,
            modificationDate: Self.nanDate,
        )
        let otherNaNFingerprint = SourceFingerprint(
            standardizedPath: "/tmp/b.ARW",
            fileSize: 1,
            modificationDate: Self.nanDate,
        )
        #expect(throws: (any Error).self) {
            try PerFileAnalysisArtifactStore.cacheKey(for: nanFingerprint)
        }
        #expect(throws: (any Error).self) {
            try PerFileAnalysisArtifactStore.cacheKey(for: otherNaNFingerprint)
        }
    }

    @Test
    func `distinct record identities have distinct cache keys`() throws {
        let first = SourceFingerprint(standardizedPath: "/tmp/a.ARW", fileSize: 1, modificationDate: .distantPast)
        let second = SourceFingerprint(standardizedPath: "/tmp/b.ARW", fileSize: 1, modificationDate: .distantPast)
        #expect(
            try PerFileAnalysisArtifactStore.cacheKey(for: first)
                != PerFileAnalysisArtifactStore.cacheKey(for: second),
        )
    }
}
