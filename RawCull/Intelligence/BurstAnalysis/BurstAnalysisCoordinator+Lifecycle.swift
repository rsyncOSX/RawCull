import Foundation

extension BurstAnalysisCoordinator {
    func beginGeneration() -> Int {
        task?.cancel()
        task = nil
        generation &+= 1
        return generation
    }

    func register(_ task: Task<Void, Never>, generation: Int) {
        guard self.generation == generation else {
            task.cancel()
            return
        }
        self.task = task
    }

    func updateProgress(_ progress: BurstAnalysisProgress) {
        self.progress = progress
    }

    func isCurrent(generation: Int) -> Bool {
        !Task.isCancelled && self.generation == generation
    }

    func finish(generation: Int) {
        guard self.generation == generation else { return }
        task = nil
        progress = BurstAnalysisProgress()
    }

    func cancel() {
        task?.cancel()
        task = nil
        generation &+= 1
        progress = BurstAnalysisProgress()
    }
}
