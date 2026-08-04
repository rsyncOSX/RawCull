import Foundation
@testable import RawCull

func makeThumbnailCacheKey(
    sourceURL: URL,
    purpose: ThumbnailCacheKey.Purpose = .preview,
    requestedPixelSize: Int = 256,
    fileSize: Int64 = 1,
    modificationDate: Date = Date(timeIntervalSinceReferenceDate: 1),
) -> ThumbnailCacheKey {
    guard let key = ThumbnailCacheKey(
        sourceURL: sourceURL,
        fileSize: fileSize,
        modificationDate: modificationDate,
        purpose: purpose,
        requestedPixelSize: requestedPixelSize,
    ) else {
        preconditionFailure("Test thumbnail key inputs must be valid")
    }
    return key
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
