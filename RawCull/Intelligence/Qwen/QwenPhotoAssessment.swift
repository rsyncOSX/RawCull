import Foundation
import FoundationModels

@Generable(description: "A concise technical and aesthetic assessment of one photograph.")
nonisolated struct QwenPhotoAssessment: Codable, Equatable, Sendable {
    @Guide(description: "A short description of the main subject.")
    let subject: String

    @Guide(description: "Composition quality from 1 (poor) through 5 (excellent).", .range(1 ... 5))
    let compositionScore: Int

    @Guide(description: "Exposure quality from 1 (poor) through 5 (excellent).", .range(1 ... 5))
    let exposureScore: Int

    @Guide(description: "Main-subject visibility from 1 (poor) through 5 (excellent).", .range(1 ... 5))
    let subjectVisibilityScore: Int

    @Guide(description: "Whether clearly visible eyes are open, or nil when no eyes are clearly visible.")
    let eyesOpen: Bool?

    @Guide(description: "A short list of visible technical or compositional problems.", .maximumCount(4))
    let problems: [String]

    @Guide(description: "A short list of visible technical or compositional strengths.", .maximumCount(4))
    let strengths: [String]

    @Guide(description: "Confidence in the assessment from 0 (uncertain) through 1 (certain).", .range(0 ... 1))
    let confidence: Float

    var overallScore: Double {
        let composition = Double(compositionScore) / 5
        let exposure = Double(exposureScore) / 5
        let visibility = Double(subjectVisibilityScore) / 5
        return composition * 0.50 + exposure * 0.20 + visibility * 0.30
    }

    static func decodeResponse(_ response: String) throws -> Self {
        let trimmed = response.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let opening = trimmed.firstIndex(of: "{"),
              let closing = trimmed.lastIndex(of: "}"),
              opening <= closing
        else {
            throw QwenModelError.invalidStructuredResponse
        }

        do {
            let decoded = try JSONDecoder().decode(
                Self.self,
                from: Data(trimmed[opening ... closing].utf8),
            )
            return try decoded.validated()
        } catch let error as QwenModelError {
            throw error
        } catch {
            throw QwenModelError.invalidStructuredResponse
        }
    }

    func validated() throws -> Self {
        guard (1 ... 5).contains(compositionScore),
              (1 ... 5).contains(exposureScore),
              (1 ... 5).contains(subjectVisibilityScore),
              (0 ... 1).contains(confidence)
        else {
            throw QwenModelError.invalidStructuredResponse
        }
        return self
    }
}

nonisolated enum QwenModelResponse: Equatable, Sendable {
    case structured(QwenPhotoAssessment)
    case freeform(String)

    static func fallback(from rawContent: String) throws -> Self {
        let content = rawContent.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !content.isEmpty else { throw QwenModelError.emptyResponse }
        return .freeform(content)
    }
}

nonisolated struct QwenPhotoAnalysisResult: Equatable, Identifiable, Sendable {
    let fileID: UUID
    let fileName: String
    let assessment: QwenPhotoAssessment?
    let freeformResponse: String?
    let failure: String?

    var id: UUID {
        fileID
    }

    var isSuccessful: Bool {
        assessment != nil || freeformResponse != nil
    }
}

nonisolated struct QwenBatchProgress: Equatable, Sendable {
    let completedCount: Int
    let totalCount: Int
    let currentFileName: String?
}
