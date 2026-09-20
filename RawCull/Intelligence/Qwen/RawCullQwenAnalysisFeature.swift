import Foundation
import Observation

@Observable @MainActor
final class RawCullQwenAnalysisFeature {
    static let defaultPrompt = "Evaluate the composition, exposure, subject visibility, expression, and obstructions."

    var prompt = defaultPrompt
    private(set) var results: [QwenPhotoAnalysisResult] = []
    private(set) var progress: QwenBatchProgress?
    private(set) var failureMessage: String?
    private(set) var isRunning = false
    private(set) var modelStatus: QwenModelStatus = .notConfigured

    @ObservationIgnored private let modelManager: any QwenModelManaging
    @ObservationIgnored private let imageLoader: any RawImageLoading
    @ObservationIgnored private var task: Task<Void, Never>?
    @ObservationIgnored private var generation = 0

    init(
        modelManager: any QwenModelManaging,
        imageLoader: any RawImageLoading = RawParserKitImageLoader.shared,
    ) {
        self.modelManager = modelManager
        self.imageLoader = imageLoader
    }

    func sharesModelManagerIdentity(with modelManager: any QwenModelManaging) -> Bool {
        self.modelManager === modelManager
    }

    var canRun: Bool {
        modelStatus.isAvailable
            && !isRunning
            && !prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    func filesNeedingAnalysis(from files: [FileItem]) -> [FileItem] {
        let analyzedIDs = Set(results.map(\.fileID))
        return files.filter { !analyzedIDs.contains($0.id) }
    }

    func updateModelStatus(_ status: QwenModelStatus) {
        modelStatus = status
        if !status.isAvailable, isRunning {
            cancel()
        }
    }

    func analyze(_ files: [FileItem]) async {
        let criteria = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        let pendingFiles = filesNeedingAnalysis(from: files)
        guard canRun, !criteria.isEmpty, !pendingFiles.isEmpty else { return }

        generation &+= 1
        let runGeneration = generation
        failureMessage = nil
        progress = QwenBatchProgress(
            completedCount: 0,
            totalCount: pendingFiles.count,
            currentFileName: pendingFiles.first?.name,
        )
        isRunning = true

        let feature = self
        let task = Task {
            var completed: [QwenPhotoAnalysisResult] = []
            for (index, file) in pendingFiles.enumerated() {
                guard !Task.isCancelled, feature.generation == runGeneration else { break }
                feature.progress = QwenBatchProgress(
                    completedCount: completed.count,
                    totalCount: pendingFiles.count,
                    currentFileName: file.name,
                )
                do {
                    guard let image = await feature.imageLoader.thumbnailCGImage(
                        for: file.url,
                        maxPixelSize: 2048,
                    ) else {
                        throw QwenModelError.imageUnavailable
                    }
                    try Task.checkCancellation()
                    let response = try await feature.modelManager.assess(
                        criteria: criteria,
                        image: image,
                    )
                    try Task.checkCancellation()
                    let assessment: QwenPhotoAssessment?
                    let freeformResponse: String?
                    switch response {
                    case let .structured(value):
                        assessment = value
                        freeformResponse = nil

                    case let .freeform(value):
                        assessment = nil
                        freeformResponse = value
                    }
                    completed.append(QwenPhotoAnalysisResult(
                        fileID: file.id,
                        fileName: file.name,
                        assessment: assessment,
                        freeformResponse: freeformResponse,
                        failure: nil,
                    ))
                } catch is CancellationError {
                    break
                } catch {
                    completed.append(QwenPhotoAnalysisResult(
                        fileID: file.id,
                        fileName: file.name,
                        assessment: nil,
                        freeformResponse: nil,
                        failure: error.localizedDescription,
                    ))
                }

                guard feature.generation == runGeneration else { return }
                feature.appendResults(completed)
                let nextName = pendingFiles.indices.contains(index + 1) ? pendingFiles[index + 1].name : nil
                feature.progress = QwenBatchProgress(
                    completedCount: completed.count,
                    totalCount: pendingFiles.count,
                    currentFileName: nextName,
                )
            }

            guard feature.generation == runGeneration else { return }
            feature.appendResults(completed)
            feature.progress = nil
            feature.isRunning = false
            feature.task = nil
            if !completed.isEmpty, completed.allSatisfy({ !$0.isSuccessful }) {
                feature.failureMessage = "Qwen could not analyze any of the selected photos."
            }
        }
        self.task = task
        await withTaskCancellationHandler {
            await task.value
        } onCancel: {
            task.cancel()
        }
    }

    private func appendResults(_ newResults: [QwenPhotoAnalysisResult]) {
        let newIDs = Set(newResults.map(\.fileID))
        results.removeAll { newIDs.contains($0.fileID) }
        results.append(contentsOf: newResults)
    }

    func cancel() {
        generation &+= 1
        task?.cancel()
        task = nil
        progress = nil
        isRunning = false
    }
}
