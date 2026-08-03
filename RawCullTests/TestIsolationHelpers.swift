import Foundation
@testable import RawCull

func makeThumbnailRequestKey(
    url: URL,
    fileSize: Int64 = 1,
    modificationDate: Date = Date(timeIntervalSince1970: 1_000),
    purpose: ThumbnailPurpose = .preview,
    requestedMaxPixelSize: Int = 256,
    schemaVersion: Int = ThumbnailSourceFingerprint.currentCacheSchemaVersion,
) -> ThumbnailRequestKey {
    ThumbnailRequestKey(
        source: ThumbnailSourceFingerprint(
            url: url,
            fileSize: fileSize,
            modificationDate: modificationDate,
            cacheSchemaVersion: schemaVersion,
        ),
        purpose: purpose,
        requestedMaxPixelSize: requestedMaxPixelSize,
    )
}

func makeIsolatedCache(
    name: String = #function,
    config: CacheConfig = .testing,
) async -> SharedMemoryCache {
    let safeName = name
        .replacingOccurrences(of: "`", with: "")
        .replacingOccurrences(of: " ", with: "-")
        .replacingOccurrences(of: "()", with: "")
    let root = FileManager.default.temporaryDirectory
        .appendingPathComponent("RawCullVerifyTests", isDirectory: true)
        .appendingPathComponent("\(safeName)-\(UUID().uuidString)", isDirectory: true)
    let thumbnailDirectory = root.appendingPathComponent("Thumbnails", isDirectory: true)
    let fullSizeDirectory = root.appendingPathComponent("FullSizeJPGs", isDirectory: true)

    let cache = SharedMemoryCache(
        diskCache: DiskCacheManager(cacheDirectory: thumbnailDirectory),
        fullSizeJPGCache: FullSizeJPGDiskCache(cacheDirectory: fullSizeDirectory),
        tracksEvictions: false,
    )
    await cache.resetForTesting(config: config)
    return cache
}

func makeIsolatedThumbnailProvider(
    name: String = #function,
    config: CacheConfig = .testing,
) async -> (RequestThumbnail, SharedMemoryCache) {
    let cache = await makeIsolatedCache(name: name, config: config)
    let provider = RequestThumbnail(memoryCache: cache)
    return (provider, cache)
}

@MainActor
func makeIsolatedSettingsViewModel(name: String = #function) -> SettingsViewModel {
    SettingsViewModel(settingsFileURL: makeIsolatedSettingsURL(name: name), loadOnInit: false)
}

func makeIsolatedSettingsURL(name: String = #function) -> URL {
    let safeName = name
        .replacingOccurrences(of: "`", with: "")
        .replacingOccurrences(of: " ", with: "-")
        .replacingOccurrences(of: "()", with: "")
    return FileManager.default.temporaryDirectory
        .appendingPathComponent("RawCullVerifyTests", isDirectory: true)
        .appendingPathComponent("\(safeName)-\(UUID().uuidString)", isDirectory: true)
        .appendingPathComponent("settings.json")
}

func makeIsolatedSavedFilesURL(name: String = #function) -> URL {
    let safeName = name
        .replacingOccurrences(of: "`", with: "")
        .replacingOccurrences(of: " ", with: "-")
        .replacingOccurrences(of: "()", with: "")
    return FileManager.default.temporaryDirectory
        .appendingPathComponent("RawCullVerifyTests", isDirectory: true)
        .appendingPathComponent("\(safeName)-\(UUID().uuidString)", isDirectory: true)
        .appendingPathComponent("Application Support", isDirectory: true)
        .appendingPathComponent("RawCullVerify", isDirectory: true)
        .appendingPathComponent("savedfiles.json")
}

func makeIsolatedSimilarityArtifactStore(
    name: String = #function,
) -> PerFileAnalysisArtifactStore {
    let safeName = name
        .replacingOccurrences(of: "`", with: "")
        .replacingOccurrences(of: " ", with: "-")
        .replacingOccurrences(of: "()", with: "")
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent("RawCullVerifyTests", isDirectory: true)
        .appendingPathComponent(
            "\(safeName)-\(UUID().uuidString)",
            isDirectory: true,
        )
        .appendingPathComponent("SimilarityArtifacts", isDirectory: true)
    return PerFileAnalysisArtifactStore(storageDirectory: directory)
}
