import Foundation

nonisolated enum ObjectAnalysisResponseDecoder {
    static func decode(_ response: String, boardIDs: Set<String>, expectedConcepts: [String: String] = [:]) throws -> ObjectPhotoAssessment {
        let value = try ObjectJSONEnvelope.decode(ObjectPhotoAssessment.self, from: response)
        guard value.schemaVersion == ObjectPhotoAssessment.schemaVersion else {
            throw ObjectResponseIssue.invalidValue("schemaVersion")
        }
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
        guard value.strengths.isEmpty, value.problems.isEmpty else {
            throw ObjectResponseIssue.invalidValue("uncited photo judgments")
        }
        let ids = value.objects.map(\.id)
        for id in ids where ids.filter({ $0 == id }).count > 1 {
            throw ObjectResponseIssue.duplicateID(id)
        }
        for id in ids where !boardIDs.contains(id) {
            throw ObjectResponseIssue.unknownID(id)
        }
        for id in boardIDs.sorted() where !ids.contains(id) {
            throw ObjectResponseIssue.missingID(id)
        }
        for id in value.preferredObjectIDs where !ids.contains(id) {
            throw ObjectResponseIssue.unknownID(id)
        }
        for id in value.preferredObjectIDs where value.preferredObjectIDs.filter({ $0 == id }).count > 1 {
            throw ObjectResponseIssue.duplicateID(id)
        }
        for object in value.objects {
            guard !object.concept.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                  !object.description.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                  validConfidence(object.confidence),
                  validList(object.obstructions, cap: 8), validList(object.strengths, cap: 8),
                  validList(object.problems, cap: 8)
            else {
                throw ObjectResponseIssue.invalidValue("object \(object.id)")
            }
            if let concept = expectedConcepts[object.id],
               object.concept.lowercased().trimmingCharacters(in: .whitespacesAndNewlines) != concept.lowercased() {
                throw ObjectResponseIssue.invalidValue("object \(object.id) concept ownership")
            }
            // SAM crop ownership does not qualify facial anatomy.
            guard object.expression == nil else { throw ObjectResponseIssue.invalidValue("unverified expression") }
            func validEvidence(_ evidence: ObjectClaimEvidence) -> Bool {
                evidence.cropID == object.id && validList([evidence.observation], cap: 1)
            }
            guard object.strengthEvidence.count == object.strengths.count,
                  object.problemEvidence.count == object.problems.count,
                  object.strengthEvidence.allSatisfy(validEvidence),
                  object.problemEvidence.allSatisfy(validEvidence) else {
                throw ObjectResponseIssue.invalidValue("object \(object.id) claim evidence")
            }
            if object.focusQuality == .uncertain {
                guard object.focusEvidence == nil else { throw ObjectResponseIssue.invalidValue("uncertain focus evidence") }
            } else {
                guard let evidence = object.focusEvidence, validEvidence(evidence),
                      focusDescription(evidence.observation, supports: object.focusQuality) else {
                    throw ObjectResponseIssue.invalidValue("object \(object.id) focus evidence")
                }
            }
            if !focusClaimsAreConsistent(object) {
                throw ObjectResponseIssue.invalidValue("object \(object.id) focus consistency")
            }
        }
        return value
    }

    static func focusClaimsAreConsistent(_ object: ObjectAssessment) -> Bool {
        let prose = subjectFocusProse(([object.description] + object.strengths + object.problems).joined(separator: " "))
        return !(object.focusQuality != .sharp && mentionsSharp(prose))
            && !(object.focusQuality == .sharp && mentionsBlur(prose))
    }

    private static func subjectFocusProse(_ text: String) -> String {
        text.lowercased()
            .replacingOccurrences(of: #"\b(?:blurred|soft|sharp|crisp) background\b|\bbackground (?:is |appears )?(?:blurred|soft|sharp|crisp)\b"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: #"\b(?:not|lacks?) (?:in )?(?:sharply\s+focused|sharp(?:ly defined)?|crisp|well[- ]focused)\b"#, with: "soft", options: .regularExpression)
    }

    // Conservative wording checks catch explicit contradictions, not visual truth.
    private static func mentionsSharp(_ text: String) -> Bool {
        ["sharp", "crisp", "well-focused", "well focused"].contains { text.contains($0) }
    }

    private static func mentionsBlur(_ text: String) -> Bool {
        ["blurred", "smeared", "indistinct", "out of focus", "soft focus"].contains { text.contains($0) }
    }

    static func focusDescription(_ text: String, supports quality: ObjectFocusQuality) -> Bool {
        let text = text.lowercased()
        switch quality {
        case .sharp:
            let resolvedDetail = text.range(
                of: #"\b(?:clearly|distinctly|well) (?:resolved|defined)\b|\b(?:distinct|well-defined) edges\b"#,
                options: .regularExpression
            ) != nil
            let unsupported = text.range(
                of: #"\b(?:not|without|lack|lacks|lacking|no)\s+(?:(?:clearly|distinctly|well)\s+)?(?:sharp|crisp|resolved|defined|distinct|fine|detail)\b|\b(?:soft|unresolved)\b"#,
                options: .regularExpression
            ) != nil
            return (mentionsSharp(text) || resolvedDetail) && !mentionsBlur(text) && !unsupported
        case .soft:
            return ["soft", "lack", "not crisp", "not sharp"].contains { text.contains($0) } && !text.contains("smeared")
        case .blurred:
            return mentionsBlur(text) && !text.contains("not blurred")
        case .uncertain:
            return false
        }
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
