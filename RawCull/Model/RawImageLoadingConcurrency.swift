import Foundation

nonisolated enum RawImageLoadingConcurrency {
    static var batchExtractionLimit: Int {
        max(1, ProcessInfo.processInfo.activeProcessorCount * 2)
    }
}
