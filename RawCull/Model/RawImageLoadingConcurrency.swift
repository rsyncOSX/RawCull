import Foundation

nonisolated enum RawImageLoadingConcurrency {
    static var batchExtractionLimit: Int {
        max(1, ProcessInfo.processInfo.activeProcessorCount * 2)
    }

    /// Thumbnail preload is lower priority than interactive grid work and AI
    /// inference. Keep it bounded independently from explicit JPEG export.
    static var thumbnailPreloadLimit: Int {
        min(4, max(1, ProcessInfo.processInfo.activeProcessorCount / 2))
    }
}
