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

    @ObservationIgnored private let inference: any QwenInferenceServing
    @ObservationIgnored private let imageLoader: any RawImageLoading
    @ObservationIgnored private var drainingTasks: [Task<Void, Never>] = []
    @ObservationIgnored private var task: Task<Void, Never>?
    @ObservationIgnored private var generation = 0

    init(
        inference: any QwenInferenceServing,
        imageLoader: any RawImageLoading = RawParserKitImageLoader.shared,
    ) {
        self.inference = inference
        self.imageLoader = imageLoader
    }

    func sharesInferenceIdentity(with inference: any QwenInferenceServing) -> Bool {
        self.inference === inference
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
        guard !CombinedReviewLease.shared.isHeld, canRun, !criteria.isEmpty, !pendingFiles.isEmpty else { return }

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
        let access = RawCullCatalogAccess.shared.retainAccess(for: pendingFiles.map(\.url))
        let task = Task {
            defer { withExtendedLifetime(access) {} }
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
                    var response = try await feature.inference.assess(
                        criteria: criteria + "\nUse one short sentence per evidence field, preferably under 160 characters; the hard limit is 240. Keep subject, problems and strengths under 240 characters each. Do not contradict a score in its evidence or lists.",
                        image: image,
                    )
                    try Task.checkCancellation()
                    if case let .rejected(value) = response {
                        let feedback = Self.validationFeedback(value)
                        response = try await feature.inference.assess(
                            criteria: criteria + "\nThe previous assessment failed validation: " + feedback
                                + "\nRegenerate the assessment from the same image. Include every schema key with the required types. Use one short sentence per evidence field, under 160 characters. All text fields and list items must be at most 240 characters. Do not invent evidence to satisfy the schema.",
                            image: image,
                        )
                        try Task.checkCancellation()
                    }
                    let assessment: QwenPhotoAssessment?
                    let freeformResponse: String?
                    let failure: String?
                    switch response {
                    case let .structured(value):
                        assessment = value
                        freeformResponse = nil
                        failure = nil

                    case let .freeform(value):
                        assessment = nil
                        freeformResponse = value
                        failure = nil
                    case let .rejected(value):
                        assessment = nil
                        freeformResponse = value
                        failure = Self.validationFeedback(value)
                    }
                    completed.append(QwenPhotoAnalysisResult(
                        fileID: file.id,
                        fileName: file.name,
                        assessment: assessment,
                        freeformResponse: freeformResponse,
                        failure: failure,
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
        drainingTasks.removeAll { $0 == task }
    }

    // Tab-specific diagnostics: shared decoding and Combined Review are unchanged.
    private nonisolated static func validationFeedback(_ response: String) -> String {
        if let opening = response.firstIndex(of: "{"), let closing = response.lastIndex(of: "}"),
           opening <= closing,
           let object = try? JSONSerialization.jsonObject(with: Data(response[opening...closing].utf8)) as? [String: Any] {
            let oversized = object.keys.sorted().flatMap { key -> [String] in
                if let text = object[key] as? String, text.count > 240 {
                    return ["\(key) has \(text.count) characters (maximum 240)"]
                }
                if let list = object[key] as? [String] {
                    return list.enumerated().compactMap { index, text in
                        text.count > 240 ? "\(key)[\(index)] has \(text.count) characters (maximum 240)" : nil
                    }
                }
                return []
            }
            if !oversized.isEmpty { return "Invalid photo assessment: " + oversized.joined(separator: "; ") }
        }
        return QwenModelError.invalidStructuredResponse.localizedDescription
    }

    private func appendResults(_ newResults: [QwenPhotoAnalysisResult]) {
        let newIDs = Set(newResults.map(\.fileID))
        results.removeAll { newIDs.contains($0.fileID) }
        results.append(contentsOf: newResults)
    }

    func cancelAndWait() async {
        cancel()
        let draining = drainingTasks
        drainingTasks = []
        for worker in draining {
            await worker.value
        }
    }

    func cancel() {
        generation &+= 1
        if let task {
            drainingTasks.append(task); task.cancel()
        }
        task = nil
        progress = nil
        isRunning = false
    }
}
