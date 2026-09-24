import Foundation

nonisolated enum ObjectAnalysisResponseDecoder {
    static func decode(_ response: String, boardIDs: Set<String>) throws -> ObjectPhotoAssessment {
        guard let data = response.data(using: .utf8),
              let value = try? JSONDecoder().decode(ObjectPhotoAssessment.self, from: data),
              !value.imageSummary.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              value.objects.count <= 8,
              validConfidence(value.confidence),
              validList(value.relationships, cap: 8),
              validList(value.strengths, cap: 8),
              validList(value.problems, cap: 8),
              value.preferredObjectIDs.count <= 8 else {
            throw ObjectAnalysisError.invalidAssessment
        }
        let ids = value.objects.map(\.id)
        guard Set(ids).count == ids.count,
              Set(ids).isSubset(of: boardIDs),
              Set(value.preferredObjectIDs).count == value.preferredObjectIDs.count,
              Set(value.preferredObjectIDs).isSubset(of: Set(ids)),
              value.objects.allSatisfy({ object in
                  !object.id.isEmpty
                      && !object.concept.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                      && !object.description.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                      && validConfidence(object.confidence)
                      && validList(object.obstructions, cap: 8)
                      && validList(object.strengths, cap: 8)
                      && validList(object.problems, cap: 8)
              }) else {
            throw ObjectAnalysisError.invalidAssessment
        }
        return value
    }

    private static func validConfidence(_ value: Float) -> Bool {
        value.isFinite && (0 ... 1).contains(value)
    }

    private static func validList(_ values: [String], cap: Int) -> Bool {
        values.count <= cap && Set(values).count == values.count && values.allSatisfy {
            let trimmed = $0.trimmingCharacters(in: .whitespacesAndNewlines)
            return !trimmed.isEmpty && trimmed.count <= 240
        }
    }
}
