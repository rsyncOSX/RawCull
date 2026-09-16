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

nonisolated protocol QwenModelManaging: Sendable {
    func validate(url: URL) async -> QwenModelStatus
    func assess(criteria: String, image: CGImage) async throws -> QwenPhotoAssessment
    func clear() async
}

actor QwenModelManager: QwenModelManaging {
    private var provider: CoreAIQwenProvider?
    private var model: CoreAIVisionLanguageModel?

    func validate(url: URL) -> QwenModelStatus {
        let standardizedURL = url.standardizedFileURL
        switch CoreAIQwenProvider.factory.capability(in: [standardizedURL]) {
        case let .available(resource):
            do {
                let provider = try CoreAIQwenProvider.factory.makeProvider(from: resource)
                guard provider.configuration.modality == .vision else {
                    clear()
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
                clear()
                return .invalid(url: standardizedURL, reason: Self.message(for: error))
            }

        case .missing:
            clear()
            return .missing(standardizedURL)

        case let .invalid(url, reason):
            clear()
            return .invalid(url: url, reason: reason)
        }
    }

    func assess(criteria: String, image: CGImage) async throws -> QwenPhotoAssessment {
        guard let provider else { throw QwenModelError.modelUnavailable }

        let model: CoreAIVisionLanguageModel
        if let loadedModel = self.model {
            model = loadedModel
        } else {
            let loadedModel = try await provider.makeVisionLanguageModel()
            self.model = loadedModel
            model = loadedModel
        }

        let session = LanguageModelSession(model: model)
        let response = try await session.respond(
            options: GenerationOptions(maximumResponseTokens: 512),
        ) {
            Attachment(image)
            """
            Analyze this photograph using these additional criteria:
            \(criteria)

            Return exactly one JSON object and no Markdown. Use this schema:
            {
              "subject": "short description",
              "compositionScore": 1,
              "exposureScore": 1,
              "subjectVisibilityScore": 1,
              "eyesOpen": null,
              "problems": ["short issue"],
              "strengths": ["short strength"],
              "confidence": 0.0
            }
            All three scores must be integers from 1 through 5. Confidence must be from 0 through 1.
            Use null for eyesOpen when the photograph has no clearly visible eyes.
            """
        }
        let content = response.content.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !content.isEmpty else { throw QwenModelError.emptyResponse }
        return try QwenPhotoAssessment.decodeResponse(content)
    }

    func clear() {
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
        }
    }
}
