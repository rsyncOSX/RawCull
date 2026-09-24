import Foundation
import PhotoAIContracts

nonisolated enum ObjectConceptDiscovery {
    static let maximumConcepts = 6
    static let instruction = """
        Examine this photograph and return JSON only: {"concepts":[{"query":"bird","displayName":"Bird","reason":"Primary visible subject"}]}. Return zero to six concrete, visible object categories. Use short singular noun phrases that SAM 3 can ground. Prefer photographically meaningful subjects. Avoid scene adjectives, actions, relationships, abstract concepts, unseen objects, and redundant parent/child categories.
        """

    static func decode(_ response: String) throws -> [ObjectConceptSuggestion] {
        struct Payload: Decodable {
            struct Entry: Decodable {
                let query: String
                let displayName: String
                let reason: String
            }
            let concepts: [Entry]
        }
        guard let data = response.data(using: .utf8),
              let payload = try? JSONDecoder().decode(Payload.self, from: data),
              payload.concepts.count <= maximumConcepts else {
            throw ObjectAnalysisError.invalidConceptResponse
        }
        var seen: Set<String> = []
        return try payload.concepts.compactMap { entry in
            guard let concept = try? SegmentationConcept(entry.query),
                  !entry.displayName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                  !entry.reason.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                  entry.displayName.count <= 80, entry.reason.count <= 160 else {
                throw ObjectAnalysisError.invalidConceptResponse
            }
            guard seen.insert(concept.cacheIdentifier).inserted else { return nil }
            return ObjectConceptSuggestion(concept: concept,
                                           displayName: entry.displayName.trimmingCharacters(in: .whitespacesAndNewlines),
                                           reason: entry.reason.trimmingCharacters(in: .whitespacesAndNewlines))
        }
    }

    static func parseManual(_ text: String) throws -> [SegmentationConcept] {
        let parts = text.split(separator: ",", omittingEmptySubsequences: false)
        guard !parts.isEmpty, parts.count <= maximumConcepts else {
            throw ObjectAnalysisError.invalidConcept(text)
        }
        var seen: Set<String> = []
        return try parts.compactMap { part in
            let raw = String(part)
            guard let concept = try? SegmentationConcept(raw) else {
                throw ObjectAnalysisError.invalidConcept(raw)
            }
            return seen.insert(concept.cacheIdentifier).inserted ? concept : nil
        }
    }
}
