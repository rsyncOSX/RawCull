import CoreGraphics
import Observation

@MainActor
@Observable
final class SubjectOutlinePresentationModel {
    var isPresented = false
    private(set) var image: CGImage?
    private(set) var isLoading = false
    @ObservationIgnored private var generation = 0

    func load(operation: @MainActor () async -> CGImage?) async {
        reset()
        guard isPresented else { return }
        let request = generation
        isLoading = true
        let result = await operation()
        guard !Task.isCancelled, generation == request else { return }
        image = result
        isLoading = false
    }

    func reset() {
        generation += 1
        image = nil
        isLoading = false
    }
}
