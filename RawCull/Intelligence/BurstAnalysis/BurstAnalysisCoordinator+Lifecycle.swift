import Foundation
import OSLog

extension BurstAnalysisCoordinator {
    func beginGeneration() -> Int {
        Logger.process.debugMessageOnly("BurstAnalysisCoordinator.beginGeneration()")
        cancelTask?()
        cancelTask = nil
        generation &+= 1
        return generation
    }

    func register<Success>(_ task: Task<Success, Never>, generation: Int) {
        Logger.process.debugMessageOnly("BurstAnalysisCoordinator.register()")
        guard self.generation == generation else {
            task.cancel()
            return
        }
        cancelTask = { task.cancel() }
    }

    func updateProgress(_ progress: BurstAnalysisProgress) {
        Logger.process.debugMessageOnly("BurstAnalysisCoordinator.updateProgress()")
        self.progress = progress
    }

    func isCurrent(generation: Int) -> Bool {
        !Task.isCancelled && self.generation == generation
    }

    func finish(generation: Int) {
        Logger.process.debugMessageOnly("BurstAnalysisCoordinator.finish()")
        guard self.generation == generation else { return }
        cancelTask = nil
        progress = BurstAnalysisProgress()
    }

    func cancel() {
        Logger.process.debugMessageOnly("BurstAnalysisCoordinator.cancel()")
        cancelTask?()
        cancelTask = nil
        generation &+= 1
        progress = BurstAnalysisProgress()
    }
}
