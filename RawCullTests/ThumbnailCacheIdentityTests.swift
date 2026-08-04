import AppKit
import Foundation
import PhotoAIContracts
@testable import RawCull
import Testing

@Suite("Thumbnail cache identity")
struct ThumbnailCacheIdentityTests {
    @Test
    func `replacing source bytes at the same path changes thumbnail identity`() throws {
        let root = try makeIdentityTestRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let sourceURL = root.appendingPathComponent("replace.ARW")

        try Data([1]).write(to: sourceURL)
        let first = try #require(ThumbnailCacheKey.resolve(
            for: sourceURL,
            purpose: .preview,
            requestedPixelSize: 1616,
        ))

        try Data(repeating: 2, count: 4096).write(to: sourceURL, options: .atomic)
        let replacement = try #require(ThumbnailCacheKey.resolve(
            for: sourceURL,
            purpose: .preview,
            requestedPixelSize: 1616,
        ))

        #expect(first.source.standardizedPath == replacement.source.standardizedPath)
        #expect(first != replacement)
        #expect(first.cacheIdentifier != replacement.cacheIdentifier)
    }

    @Test
    func `purpose and requested size identify separate representations`() throws {
        let sourceURL = URL(fileURLWithPath: "/tmp/thumbnail-representation.ARW")
        let preview = makeThumbnailCacheKey(
            sourceURL: sourceURL,
            purpose: .preview,
            requestedPixelSize: 1616,
        )
        let grid = try #require(preview.representation(
            purpose: .grid,
            requestedPixelSize: 200,
        ))
        let smallerPreview = try #require(preview.representation(
            purpose: .preview,
            requestedPixelSize: 1024,
        ))

        #expect(preview != grid)
        #expect(preview != smallerPreview)
        #expect(grid != smallerPreview)
        #expect(preview.orientationPolicy == .sourceNormalized)
        #expect(grid.orientationPolicy == .sourceNormalized)
    }

    @Test
    func `missing source metadata bypasses thumbnail reuse`() {
        let missingURL = URL(fileURLWithPath: "/nonexistent/rawcull-\(UUID().uuidString).ARW")

        #expect(ThumbnailCacheKey.resolve(
            for: missingURL,
            purpose: .preview,
            requestedPixelSize: 256,
        ) == nil)
        #expect(ThumbnailCacheKey(
            sourceURL: missingURL,
            fileSize: nil,
            modificationDate: Date(),
            purpose: .preview,
            requestedPixelSize: 256,
        ) == nil)
    }

    @Test
    func `atomic writers and cancelled save never leave a partial JPEG`() async throws {
        let root = try makeIdentityTestRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let cache = DiskCacheManager(cacheDirectory: root)
        let key = makeThumbnailCacheKey(
            sourceURL: root.appendingPathComponent("source.ARW"),
            requestedPixelSize: 512,
        )
        let first = try makeIdentityTestJPEG(width: 48, height: 32, color: .red)
        let second = try makeIdentityTestJPEG(width: 96, height: 64, color: .blue)

        await withTaskGroup(of: Void.self) { group in
            for index in 0 ..< 40 {
                group.addTask {
                    await cache.save(index.isMultiple(of: 2) ? first : second, for: key)
                }
            }
            await group.waitForAll()
        }

        let loaded = try #require(await cache.load(for: key))
        let loadedSize = (Int(loaded.size.width), Int(loaded.size.height))
        #expect(loadedSize == (48, 32) || loadedSize == (96, 64))

        let cancelledKey = try #require(key.representation(
            purpose: .preview,
            requestedPixelSize: 1024,
        ))
        await withTaskGroup(of: Void.self) { group in
            group.cancelAll()
            group.addTask {
                await cache.save(first, for: cancelledKey)
            }
            await group.waitForAll()
        }
        let cancelledFile = await cache.cacheFileURL(for: cancelledKey)
        #expect(!FileManager.default.fileExists(atPath: cancelledFile.path))
    }

    @Test
    func `corrupt JPEG becomes a miss and is removed`() async throws {
        let root = try makeIdentityTestRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let cache = DiskCacheManager(cacheDirectory: root)
        let key = makeThumbnailCacheKey(
            sourceURL: root.appendingPathComponent("corrupt-source.ARW"),
        )

        await cache.save(Data("not a JPEG".utf8), for: key)
        let cacheFile = await cache.cacheFileURL(for: key)
        #expect(FileManager.default.fileExists(atPath: cacheFile.path))

        #expect(await cache.load(for: key) == nil)
        #expect(!FileManager.default.fileExists(atPath: cacheFile.path))
    }

    @Test
    func `migration removes only legacy thumbnail JPEGs`() async throws {
        let root = try makeIdentityTestRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let thumbnailRoot = root.appendingPathComponent("Thumbnails", isDirectory: true)
        let unrelatedThumbnailState = thumbnailRoot.appendingPathComponent("UnrelatedState", isDirectory: true)
        let similarityRoot = root.appendingPathComponent("SimilarityArtifacts", isDirectory: true)
        try FileManager.default.createDirectory(at: unrelatedThumbnailState, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: similarityRoot, withIntermediateDirectories: true)

        let legacyJPEG = thumbnailRoot.appendingPathComponent("legacy-v2.jpg")
        let nestedSentinel = unrelatedThumbnailState.appendingPathComponent("keep.data")
        let similaritySentinel = similarityRoot.appendingPathComponent("typed-artifact.json")
        try Data([1]).write(to: legacyJPEG)
        try Data([2]).write(to: nestedSentinel)
        try Data([3]).write(to: similaritySentinel)

        let cache = DiskCacheManager(cacheDirectory: thumbnailRoot)
        let key = makeThumbnailCacheKey(sourceURL: root.appendingPathComponent("source.ARW"))
        let currentSchemaFile = await cache.cacheFileURL(for: key)

        #expect(!FileManager.default.fileExists(atPath: legacyJPEG.path))
        #expect(FileManager.default.fileExists(atPath: nestedSentinel.path))
        #expect(FileManager.default.fileExists(atPath: similaritySentinel.path))
        #expect(FileManager.default.fileExists(
            atPath: currentSchemaFile.deletingLastPathComponent().path,
        ))
    }

    @Test
    func `thumbnail representation changes preserve Vision CLIP and SAM identities`() throws {
        let root = try makeIdentityTestRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let sourceURL = root.appendingPathComponent("ai-source.ARW")
        try Data("stable source".utf8).write(to: sourceURL)
        let source = AIImageSource(id: UUID(), url: sourceURL, displayName: "ai-source.ARW")
        let modelIdentity = ModelIdentity(
            family: "sam3",
            name: "SAM 3",
            assetName: "sam3.mlmodelc",
            metadataVersion: "1",
        )
        let sourceIdentity = SourceFileIdentity.read(from: sourceURL)
        let sourceFingerprint = SourceFingerprint(source: source)
        let backends = [
            SimilarityBackendDescriptor(
                backend: "vision-feature-print",
                modelFingerprint: "vision-revision-2",
                representation: "feature-print",
                preprocessingVersion: "vision-preprocess-1",
                normalizationVersion: "vision-distance-1",
                configurationVersion: "vision-config-1",
            ),
            SimilarityBackendDescriptor(
                backend: "clip",
                modelFingerprint: "datacomp-model-1",
                representation: "embedding",
                preprocessingVersion: "clip-preprocess-1",
                normalizationVersion: "l2-1",
                configurationVersion: "clip-config-1",
            )
        ]
        let descriptorsBefore = backends.map {
            SimilarityArtifactDescriptor(
                backend: $0,
                dimensions: 512,
                sourceFingerprint: sourceFingerprint,
            )
        }
        let maskKeyBefore = SubjectMaskStorageKey(
            source: source,
            sourceIdentity: sourceIdentity,
            prompt: .subject,
            modelIdentity: modelIdentity,
            inputMaxSide: 4320,
        )

        let previewKey = try #require(ThumbnailCacheKey.resolve(
            for: sourceURL,
            purpose: .preview,
            requestedPixelSize: 1616,
        ))
        let gridKey = try #require(previewKey.representation(
            purpose: .grid,
            requestedPixelSize: 200,
        ))
        #expect(previewKey != gridKey)

        let descriptorsAfter = backends.map {
            SimilarityArtifactDescriptor(
                backend: $0,
                dimensions: 512,
                sourceFingerprint: SourceFingerprint(source: source),
            )
        }
        let maskKeyAfter = SubjectMaskStorageKey(
            source: source,
            sourceIdentity: SourceFileIdentity.read(from: sourceURL),
            prompt: .subject,
            modelIdentity: modelIdentity,
            inputMaxSide: 4320,
        )

        #expect(descriptorsBefore == descriptorsAfter)
        #expect(descriptorsBefore[0] != descriptorsBefore[1])
        #expect(maskKeyBefore == maskKeyAfter)
    }
}

private func makeIdentityTestRoot(_ name: String = #function) throws -> URL {
    let safeName = name
        .replacingOccurrences(of: "`", with: "")
        .replacingOccurrences(of: " ", with: "-")
        .replacingOccurrences(of: "()", with: "")
    let root = FileManager.default.temporaryDirectory
        .appendingPathComponent("RawCullVerifyTests", isDirectory: true)
        .appendingPathComponent("\(safeName)-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    return root
}

private func makeIdentityTestJPEG(
    width: Int,
    height: Int,
    color: NSColor,
) throws -> Data {
    let context = try #require(CGContext(
        data: nil,
        width: width,
        height: height,
        bitsPerComponent: 8,
        bytesPerRow: 0,
        space: CGColorSpaceCreateDeviceRGB(),
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue,
    ))
    context.setFillColor(color.cgColor)
    context.fill(CGRect(x: 0, y: 0, width: width, height: height))
    let image = try #require(context.makeImage())
    return try #require(DiskCacheManager.jpegData(from: image))
}
