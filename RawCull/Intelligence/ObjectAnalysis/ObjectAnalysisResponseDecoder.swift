import Foundation

nonisolated enum ObjectAnalysisResponseDecoder {
    static func decode(_ response: String, boardIDs: Set<String>) throws -> ObjectPhotoAssessment {
        let value = try ObjectJSONEnvelope.decode(ObjectPhotoAssessment.self, from: response)
        if let summary = value.imageSummary,
           summary.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            throw ObjectResponseIssue.invalidValue("imageSummary")
        }
        guard value.objects.count <= 8, value.preferredObjectIDs.count <= 8 else {
            throw ObjectResponseIssue.tooManyItems("objects")
        }
        guard validConfidence(value.confidence) else { throw ObjectResponseIssue.invalidValue("confidence") }
        guard validList(value.relationships, cap: 8), validList(value.strengths, cap: 8),
              validList(value.problems, cap: 8) else { throw ObjectResponseIssue.invalidValue("photo lists") }
        let ids = value.objects.map(\.id)
        for id in ids where ids.filter({ $0 == id }).count > 1 { throw ObjectResponseIssue.duplicateID(id) }
        for id in ids where !boardIDs.contains(id) { throw ObjectResponseIssue.unknownID(id) }
        for id in boardIDs.sorted() where !ids.contains(id) { throw ObjectResponseIssue.missingID(id) }
        for id in value.preferredObjectIDs where !ids.contains(id) { throw ObjectResponseIssue.unknownID(id) }
        for id in value.preferredObjectIDs where value.preferredObjectIDs.filter({ $0 == id }).count > 1 {
            throw ObjectResponseIssue.duplicateID(id)
        }
        for object in value.objects {
            guard !object.concept.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                  !object.description.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                  validConfidence(object.confidence),
                  validList(object.obstructions, cap: 8), validList(object.strengths, cap: 8),
                  validList(object.problems, cap: 8) else {
                throw ObjectResponseIssue.invalidValue("object \(object.id)")
            }
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
