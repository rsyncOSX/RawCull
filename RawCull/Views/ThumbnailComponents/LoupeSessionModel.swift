import AppKit
import Observation

@MainActor
@Observable
final class LoupeSessionModel {
    var thumbnailImage: NSImage?
    var embeddedJPGImage: CGImage?
    var developedRAWImage: CGImage?
    var sourceSelection = ImageSourceSelectionState()
    private(set) var isLoadingSource = false
    private(set) var showsDevelopedRAWFailure = false

    @ObservationIgnored private var sourceTask: Task<Void, Never>?
    @ObservationIgnored private var rawMessageTask: Task<Void, Never>?
    @ObservationIgnored private var sourceRequest = ImageReviewRequestTracker<ImagePreviewSource>()

    var sourcePresentation: ImageReviewSourcePresentation {
        ImageReviewSourcePresentation(
            selection: sourceSelection,
            showsDevelopedRAWFailure: showsDevelopedRAWFailure,
        )
    }

    func selectSource(_ source: ImagePreviewSource) {
        sourceSelection.select(source)
    }

    func toggleSource(_ source: ImagePreviewSource) {
        sourceSelection.toggleExtractionSource(source)
    }

    func beginSourceLoad(
        _ operation: @escaping @MainActor (_ source: ImagePreviewSource) async throws -> CGImage?,
    ) {
        sourceTask?.cancel()
        let requestedSource = sourceSelection.selected
        guard requestedSource != .thumbnail, !hasLoadedImage(for: requestedSource) else {
            isLoadingSource = false
            return
        }

        isLoadingSource = true
        let identity = sourceRequest.begin(context: requestedSource)
        sourceTask = Task { [weak self] in
            do {
                let image = try await operation(requestedSource)
                guard let self,
                      self.sourceRequest.accepts(identity, isCancelled: Task.isCancelled),
                      self.sourceSelection.selected == requestedSource
                else { return }
                if requestedSource == .embeddedJPG {
                    self.embeddedJPGImage = image
                } else {
                    self.developedRAWImage = image
                }
                self.isLoadingSource = false
            } catch is CancellationError {
                return
            } catch {
                guard let self,
                      self.sourceRequest.accepts(identity, isCancelled: Task.isCancelled),
                      requestedSource == .developedRAW
                else { return }
                self.isLoadingSource = false
                self.sourceSelection.markDevelopedRAWUnavailable()
                self.showRAWFailureMessage()
            }
        }
    }

    func hasLoadedImage(for source: ImagePreviewSource) -> Bool {
        switch source {
        case .thumbnail: thumbnailImage != nil
        case .embeddedJPG: embeddedJPGImage != nil
        case .developedRAW: developedRAWImage != nil
        }
    }

    func resetForNewImage() {
        cancelSourceLoad()
        thumbnailImage = nil
        embeddedJPGImage = nil
        developedRAWImage = nil
        sourceSelection.resetForNewImage()
        clearRAWMessage()
    }

    func cancel() {
        cancelSourceLoad()
        clearRAWMessage()
    }

    private func cancelSourceLoad() {
        sourceTask?.cancel()
        sourceTask = nil
        sourceRequest.cancel()
        isLoadingSource = false
    }

    private func showRAWFailureMessage() {
        rawMessageTask?.cancel()
        showsDevelopedRAWFailure = true
        rawMessageTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(1))
            guard !Task.isCancelled else { return }
            self?.showsDevelopedRAWFailure = false
        }
    }

    private func clearRAWMessage() {
        rawMessageTask?.cancel()
        rawMessageTask = nil
        showsDevelopedRAWFailure = false
    }
}
