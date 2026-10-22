import AppKit
import Observation

@MainActor
@Observable
final class LoupeFocusPresentationModel {
    var isPresented = false
    private(set) var image: NSImage?
    private(set) var isLoading = false
    private var sourceURL: URL?
    private var source: ImagePreviewSource?
    @ObservationIgnored private var task: Task<Void, Never>?
    @ObservationIgnored private var generation = 0

    @discardableResult
    func request(
        url: URL,
        source: ImagePreviewSource,
        delay: Duration? = nil,
        operation: @escaping @MainActor () async -> NSImage?,
    ) -> Task<Void, Never>? {
        guard isPresented, !isLoading,
              sourceURL != url || self.source != source || image == nil
        else { return nil }
        cancel()
        let request = generation
        isLoading = true
        task = Task { [weak self] in
            if let delay {
                try? await Task.sleep(for: delay)
                guard !Task.isCancelled else { return }
            }
            let result = await operation()
            guard let self, !Task.isCancelled, self.generation == request else { return }
            self.image = result
            self.sourceURL = url
            self.source = source
            self.isLoading = false
            self.task = nil
        }
        return task
    }

    func reset() {
        cancel()
        image = nil
        sourceURL = nil
        source = nil
    }

    func cancel() {
        generation += 1
        task?.cancel()
        task = nil
        isLoading = false
    }
}
