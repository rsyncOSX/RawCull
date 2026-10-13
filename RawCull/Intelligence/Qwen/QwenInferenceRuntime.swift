// Qwen's actor-isolated provider and inference lifecycle.
import CoreAILanguageModels
import CoreAIQwenBackend
import CoreGraphics
import Foundation
import FoundationModels
import ImageIO

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
    func inputCapabilities() async -> QwenInputCapabilities?
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
    private var capabilities: QwenInputCapabilities?
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
                capabilities = QwenInputCapabilities.inspect(provider: provider, bundleURL: resource.bundleURL)
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
        guard (1 ... 4096).contains(request.maximumResponseTokens) else {
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
        captureDiagnostic(request: request, response: content)
        guard !content.isEmpty else { throw QwenModelError.emptyResponse }
        return content
    }

    /// Opt-in retention of the request raster before backend preprocessing, not an encoder tensor.
    private func captureDiagnostic(request: QwenVisionRequest, response: String) {
        guard let path = ProcessInfo.processInfo.environment["RAWCULL_AI_CAPTURE_DIR"], !path.isEmpty else { return }
        struct Capture: Encodable {
            let instruction: String
            let response: String
            let textTruncated: Bool
            let maximumResponseTokens: Int
            let inputWidth: Int
            let inputHeight: Int
            let imageFileName: String
            let inputStage: String
            let capabilities: QwenInputCapabilities?
        }
        let directory = URL(filePath: path, directoryHint: .isDirectory)
        let stem = UUID().uuidString
        let imageName = stem + ".png"
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true,
                                                    attributes: [.posixPermissions: 0o700])
            let permissions = try FileManager.default.attributesOfItem(atPath: directory.path)[.posixPermissions] as? NSNumber
            guard let permissions, permissions.intValue & 0o077 == 0 else { return }
            let png = NSMutableData()
            guard let destination = CGImageDestinationCreateWithData(png, "public.png" as CFString, 1, nil) else { return }
            CGImageDestinationAddImage(destination, request.image, nil)
            guard CGImageDestinationFinalize(destination) else { return }
            let imageURL = directory.appendingPathComponent(imageName)
            try (png as Data).write(to: imageURL, options: .atomic)
            try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: imageURL.path)
            let capture = Capture(instruction: String(request.instruction.prefix(16384)),
                                  response: String(response.prefix(8192)),
                                  textTruncated: request.instruction.count > 16384 || response.count > 8192,
                                  maximumResponseTokens: request.maximumResponseTokens,
                                  inputWidth: request.image.width, inputHeight: request.image.height,
                                  imageFileName: imageName, inputStage: "request raster before backend preprocessing",
                                  capabilities: capabilities)
            let jsonURL = directory.appendingPathComponent(stem + ".json")
            try JSONEncoder().encode(capture).write(to: jsonURL, options: .atomic)
            try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: jsonURL.path)
        } catch {
            // Optional diagnostic capture must not change inference outcomes.
        }
    }

    func inputCapabilities() async -> QwenInputCapabilities? {
        capabilities
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
          "schemaVersion": 2,
          "subject": "short description of the main subject",
          "compositionScore": 1-5 or null,
          "compositionEvidence": "visible framing evidence" or null,
          "exposureScore": 1-5 or null,
          "exposureEvidence": "visible lighting or tonal evidence" or null,
          "subjectVisibilityScore": 1-5 or null,
          "subjectVisibilityEvidence": "visible extent or occlusion of the main subject" or null,
          "eyesOpen": null,
          "problems": ["up to four short visible problems"],
          "strengths": ["up to four short visible strengths"],
          "confidence": 0.0-1.0
        }

        Include every key. Scores and confidence are model judgments, not measurements.
        Each score needs its own criterion evidence sentence (maximum 240 characters).
        When unsupported, return null for both that score and its evidence. Do not use
        background visibility or texture as evidence of main-subject visibility or detail.
        Eyes and expression remain unknown: this path has no qualified anatomical evidence.
        Assess only the supplied preview; camera processing, resizing and model input
        resolution limit fine detail. Do not infer RAW recovery, eye detail or focus accuracy.
        Base the answer only on visible evidence. If the user's request does not fit
        this assessment schema, answer it normally in plain text.
        """
    }

    private func resetModel() {
        model = nil
        provider = nil
        capabilities = nil
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

/// Test providers and alternate backends may not expose input diagnostics.
nonisolated extension QwenInferenceServing {
    func inputCapabilities() async -> QwenInputCapabilities? {
        nil
    }
}
