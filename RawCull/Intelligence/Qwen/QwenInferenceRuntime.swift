// Qwen's actor-isolated provider and inference lifecycle.
import CoreAILanguageModels
import CoreAIQwenBackend
import CoreGraphics
import Foundation
import FoundationModels

nonisolated enum QwenModelStatus: Equatable, Sendable {
    case notConfigured
    case checking(URL)
    case available(url: URL, modelName: String)
    case missing(URL)
    case invalid(url: URL, reason: String)

    var isAvailable: Bool {
        if case .available = self {
            true
        } else {
            false
        }
    }
}

nonisolated protocol QwenInferenceServing: AnyObject, Sendable {
    func validate(url: URL) async -> QwenModelStatus
    func respond(to request: QwenVisionRequest) async throws -> String
    func assess(criteria: String, image: CGImage) async throws -> QwenModelResponse
    func clear() async
}

nonisolated struct QwenVisionRequest: Sendable {
    let instruction: String
    let image: CGImage
    let maximumResponseTokens: Int
}

actor QwenInferenceRuntime: QwenInferenceServing {
    private var provider: CoreAIQwenProvider?
    private var model: CoreAIVisionLanguageModel?
    private var modelGeneration: UInt64 = 0
    private let generationGate = QwenGenerationGate()
    private var activeGeneration: Task<String, Error>?

    func validate(url: URL) -> QwenModelStatus {
        activeGeneration?.cancel()
        modelGeneration &+= 1
        let standardizedURL = url.standardizedFileURL
        switch CoreAIQwenProvider.factory.capability(in: [standardizedURL]) {
        case let .available(resource):
            do {
                let provider = try CoreAIQwenProvider.factory.makeProvider(from: resource)
                guard provider.configuration.modality == .vision else {
                    resetModel()
                    return .invalid(
                        url: resource.bundleURL,
                        reason: QwenModelError.visionModelRequired.localizedDescription,
                    )
                }
                self.provider = provider
                model = nil
                return .available(
                    url: resource.bundleURL,
                    modelName: provider.configuration.name,
                )
            } catch {
                resetModel()
                return .invalid(url: standardizedURL, reason: Self.message(for: error))
            }

        case .missing:
            resetModel()
            return .missing(standardizedURL)

        case let .invalid(url, reason):
            resetModel()
            return .invalid(url: url, reason: reason)
        }
    }

    func assess(criteria: String, image: CGImage) async throws -> QwenModelResponse {
        let response = try await respond(to: QwenVisionRequest(
            instruction: Self.assessmentInstruction(criteria: criteria),
            image: image,
            maximumResponseTokens: 512,
        ))
        return try QwenModelResponse.decode(response)
    }

    func respond(to request: QwenVisionRequest) async throws -> String {
        guard (1 ... 4_096).contains(request.maximumResponseTokens) else {
            throw QwenModelError.invalidTokenLimit
        }
        let requestedGeneration = modelGeneration
        try await generationGate.acquire()
        do {
            try Task.checkCancellation()
            guard modelGeneration == requestedGeneration else { throw CancellationError() }
            guard let provider else { throw QwenModelError.modelUnavailable }
            let generation = modelGeneration
            let task = Task {
                try await self.generate(request: request, provider: provider, generation: generation)
            }
            activeGeneration = task
            let content = try await withTaskCancellationHandler {
                try await task.value
            } onCancel: {
                task.cancel()
            }
            activeGeneration = nil
            await generationGate.release()
            return content
        } catch {
            activeGeneration = nil
            await generationGate.release()
            throw error
        }
    }

    private func generate(
        request: QwenVisionRequest,
        provider: CoreAIQwenProvider,
        generation: UInt64,
    ) async throws -> String {
        let model: CoreAIVisionLanguageModel
        if let loadedModel = self.model {
            model = loadedModel
        } else {
            let loadedModel = try await provider.makeVisionLanguageModel()
            try Task.checkCancellation()
            guard modelGeneration == generation else { throw CancellationError() }
            self.model = loadedModel
            model = loadedModel
        }

        let session = LanguageModelSession(model: model)
        let response = try await session.respond(
            options: GenerationOptions(maximumResponseTokens: request.maximumResponseTokens),
        ) {
            Attachment(request.image)
            request.instruction
        }
        try Task.checkCancellation()
        guard modelGeneration == generation else { throw CancellationError() }
        let content = response.content.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !content.isEmpty else { throw QwenModelError.emptyResponse }
        return content
    }

    func clear() {
        activeGeneration?.cancel()
        modelGeneration &+= 1
        resetModel()
    }

    nonisolated static func assessmentInstruction(criteria: String) -> String {
        """
        Analyze this photograph and answer the user's request:
        \(criteria)

        If the request is a photo assessment, return exactly one JSON object and no
        Markdown using this schema:
        {
          "subject": "short description of the main subject",
          "compositionScore": 1-5,
          "exposureScore": 1-5,
          "subjectVisibilityScore": 1-5,
          "eyesOpen": true, false, or null,
          "problems": ["up to four short visible problems"],
          "strengths": ["up to four short visible strengths"],
          "confidence": 0.0-1.0
        }

        Base the answer only on visible evidence. If the user's request does not fit
        this assessment schema, answer it normally in plain text.
        """
    }

    private func resetModel() {
        model = nil
        provider = nil
    }

    private static func message(for error: Error) -> String {
        let description = error.localizedDescription.trimmingCharacters(in: .whitespacesAndNewlines)
        return description.isEmpty ? String(reflecting: error) : description
    }
}

nonisolated enum QwenModelError: Error, LocalizedError, Sendable {
    case modelUnavailable
    case visionModelRequired
    case imageUnavailable
    case emptyResponse
    case invalidStructuredResponse
    case invalidTokenLimit

    var errorDescription: String? {
        switch self {
        case .modelUnavailable:
            "Select and validate a Qwen model in AI Settings first."

        case .visionModelRequired:
            "The selected model is text-only. Select a Qwen vision-language bundle, such as Qwen3-VL-2B-Instruct."

        case .imageUnavailable:
            "The selected photo could not be decoded for Qwen."

        case .emptyResponse:
            "Qwen returned an empty response."

        case .invalidStructuredResponse:
            "Qwen did not return a valid structured photo assessment."

        case .invalidTokenLimit:
            "The requested Qwen response length is outside the supported range."
        }
    }
}
