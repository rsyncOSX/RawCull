import AppKit
import Observation

nonisolated struct ThumbnailRequest: Hashable, Sendable {
    let url: URL
    let targetSize: Int
    let style: ThumbnailStyle
    var fileSize: Int64?
    var modificationDate: Date?
}

@MainActor
@Observable
final class ThumbnailPresentationModel {
    private(set) var image: NSImage?
    private(set) var isLoading = false
    @ObservationIgnored private var currentRequest: ThumbnailRequest?
    @ObservationIgnored private var generation: UUID?

    func load(
        request: ThumbnailRequest,
        imageLoader: @MainActor () async -> NSImage?,
        publish: @MainActor (NSImage?) -> Void,
    ) async {
        guard !Task.isCancelled else { return }
        let token = UUID()
        generation = token
        if currentRequest?.url != request.url {
            image = nil
            publish(nil)
        }
        currentRequest = request
        isLoading = true
        defer {
            if generation == token {
                isLoading = false
            }
        }
        let result = await imageLoader()
        guard !Task.isCancelled, generation == token else { return }
        image = result
        publish(result)
    }
}
