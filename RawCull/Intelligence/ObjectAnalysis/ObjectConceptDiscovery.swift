import Foundation
import PhotoAIContracts

nonisolated enum ObjectConceptDiscovery {
    static let maximumConcepts = 6
    static let instruction = """
        Look at this one photograph. Return one short JSON object only, for example {"concepts":[{"query":"bird","displayName":"Bird","reason":"Visible subject"}]}. Use the key concepts with zero to six entries. Each entry needs query, displayName, and reason as short strings. Query must be a concrete visible object category in a short singular noun phrase that SAM 3 can locate. Prefer the main subject. Avoid scene adjectives, actions, relationships, abstract concepts, unseen objects, and redundant parent/child categories.
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
        let payload = try ObjectJSONEnvelope.decode(Payload.self, from: response)
        guard payload.concepts.count <= maximumConcepts else {
            throw ObjectResponseIssue.tooManyItems("concepts")
        }
        var seen: Set<String> = []
        return try payload.concepts.compactMap { entry in
            guard let concept = try? SegmentationConcept(entry.query),
                  !entry.displayName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                  !entry.reason.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                  entry.displayName.count <= 80, entry.reason.count <= 160 else {
                throw ObjectResponseIssue.invalidValue("concept")
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
