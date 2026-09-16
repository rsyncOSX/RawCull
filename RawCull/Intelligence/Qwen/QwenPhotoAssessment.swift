import Foundation

nonisolated struct QwenPhotoAssessment: Codable, Equatable, Sendable {
    let subject: String
    let compositionScore: Int
    let exposureScore: Int
    let subjectVisibilityScore: Int
    let eyesOpen: Bool?
    let problems: [String]
    let strengths: [String]
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
            guard (1 ... 5).contains(decoded.compositionScore),
                  (1 ... 5).contains(decoded.exposureScore),
                  (1 ... 5).contains(decoded.subjectVisibilityScore),
                  (0 ... 1).contains(decoded.confidence)
            else {
                throw QwenModelError.invalidStructuredResponse
            }
            return decoded
        } catch let error as QwenModelError {
            throw error
        } catch {
            throw QwenModelError.invalidStructuredResponse
        }
    }
}

nonisolated struct QwenPhotoAnalysisResult: Equatable, Identifiable, Sendable {
    let fileID: UUID
    let fileName: String
    let assessment: QwenPhotoAssessment?
    let failure: String?

    var id: UUID {
        fileID
    }
}

nonisolated struct QwenBatchProgress: Equatable, Sendable {
    let completedCount: Int
    let totalCount: Int
    let currentFileName: String?
}
