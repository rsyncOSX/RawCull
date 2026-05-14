import Foundation
@testable import RawCull

func makeIsolatedCache(
    name: String = #function,
    config: CacheConfig = .testing,
) async -> SharedMemoryCache {
    let safeName = name
        .replacingOccurrences(of: "`", with: "")
        .replacingOccurrences(of: " ", with: "-")
        .replacingOccurrences(of: "()", with: "")
    let root = FileManager.default.temporaryDirectory
        .appendingPathComponent("RawCullTests", isDirectory: true)
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
    let safeName = name
        .replacingOccurrences(of: "`", with: "")
        .replacingOccurrences(of: " ", with: "-")
        .replacingOccurrences(of: "()", with: "")
    let url = FileManager.default.temporaryDirectory
        .appendingPathComponent("RawCullTests", isDirectory: true)
        .appendingPathComponent("\(safeName)-\(UUID().uuidString)", isDirectory: true)
        .appendingPathComponent("settings.json")
    return SettingsViewModel(settingsFileURL: url, loadOnInit: false)
}
