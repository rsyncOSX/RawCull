import Foundation

nonisolated struct QwenPhotoAssessment: Codable, Equatable, Sendable {
    static let schemaVersion = 2
    let schemaVersion: Int
    let subject: String
    let compositionEvidence: String?
    let exposureEvidence: String?
    let subjectVisibilityEvidence: String?

    let compositionScore: Int?

    let exposureScore: Int?

    let subjectVisibilityScore: Int?

    let eyesOpen: Bool?

    let problems: [String]

    let strengths: [String]

    let confidence: Float

    var overallScore: Double? {
        guard let compositionScore, let exposureScore, let subjectVisibilityScore else { return nil }
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
            let data = Data(trimmed[opening ... closing].utf8)
            guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                  ["schemaVersion", "subject", "compositionScore", "exposureScore", "subjectVisibilityScore",
                   "compositionEvidence", "exposureEvidence", "subjectVisibilityEvidence", "eyesOpen",
                   "problems", "strengths", "confidence"].allSatisfy({ object.keys.contains($0) })
            else {
                throw QwenModelError.invalidStructuredResponse
            }
            let decoded = try JSONDecoder().decode(
                Self.self,
                from: data,
            )
            return try decoded.validated()
        } catch let error as QwenModelError {
            throw error
        } catch {
            throw QwenModelError.invalidStructuredResponse
        }
    }

    func validated() throws -> Self {
        func supported(_ score: Int?, by evidence: String?) -> Bool {
            guard let score else { return evidence == nil }
            guard let evidence else { return false }
            return (1 ... 5).contains(score) && validText(evidence, limit: 240)
        }
        guard schemaVersion == Self.schemaVersion,
              validText(subject, limit: 240),
              supported(compositionScore, by: compositionEvidence),
              supported(exposureScore, by: exposureEvidence),
              supported(subjectVisibilityScore, by: subjectVisibilityEvidence),
              eyesOpen == nil, // This whole-image path supplies no qualified anatomical evidence.
              confidence.isFinite, (0 ... 1).contains(confidence),
              [problems, strengths].allSatisfy({ list in
                  list.count <= 4 && Set(list).count == list.count && list.allSatisfy { validText($0, limit: 240) }
              })
        else {
            throw QwenModelError.invalidStructuredResponse
        }
        return self
    }

    private func validText(_ text: String, limit: Int) -> Bool {
        !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && text.count <= limit
    }
}

nonisolated enum QwenModelResponse: Equatable, Sendable {
    case structured(QwenPhotoAssessment)
    case freeform(String)
    case rejected(String)

    static func decode(_ rawContent: String) throws -> Self {
        let content = rawContent.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !content.isEmpty else { throw QwenModelError.emptyResponse }

        if let assessment = try? QwenPhotoAssessment.decodeResponse(content) {
            return .structured(assessment)
        }

        // A broken assessment must not silently become a successful prose response.
        if content.contains("{") || content.contains("}") || content.hasPrefix("[") || content.hasPrefix("```json") {
            return .rejected(String(content.prefix(8192)))
        }
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
        failure == nil && (assessment != nil || freeformResponse != nil)
    }
}

nonisolated struct QwenBatchProgress: Equatable, Sendable {
    let completedCount: Int
    let totalCount: Int
    let currentFileName: String?
}
