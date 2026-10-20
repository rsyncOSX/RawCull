import Foundation

nonisolated enum ObjectAnalysisResponseDecoder {
    static func decode(_ response: String, boardIDs: Set<String>, expectedConcepts: [String: String] = [:]) throws -> ObjectPhotoAssessment {
        try decode(response, boardIDs: boardIDs, expectedConcepts: expectedConcepts, allowUnsupportedFocus: false)
    }

    private static func decode(_ response: String, boardIDs: Set<String>, expectedConcepts: [String: String], allowUnsupportedFocus: Bool) throws -> ObjectPhotoAssessment {
        let value = try ObjectJSONEnvelope.decode(ObjectPhotoAssessment.self, from: response)
        return try validate(value, boardIDs: boardIDs, expectedConcepts: expectedConcepts, allowUnsupportedFocus: allowUnsupportedFocus)
    }

    private static func validate(_ value: ObjectPhotoAssessment, boardIDs: Set<String>, expectedConcepts: [String: String], allowUnsupportedFocus: Bool = false) throws -> ObjectPhotoAssessment {
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
                  object.problemEvidence.allSatisfy(validEvidence)
            else {
                throw ObjectResponseIssue.invalidValue("object \(object.id) claim evidence")
            }
            if object.focusQuality == .uncertain {
                guard object.focusEvidence == nil else { throw ObjectResponseIssue.invalidValue("uncertain focus evidence") }
            } else {
                if let evidence = object.focusEvidence {
                    guard validEvidence(evidence),
                          allowUnsupportedFocus || focusDescription(evidence.observation, supports: object.focusQuality)
                    else {
                        throw ObjectResponseIssue.invalidValue("object \(object.id) focus evidence")
                    }
                } else if !allowUnsupportedFocus {
                    throw ObjectResponseIssue.invalidValue("object \(object.id) focus evidence")
                }
            }
            if !allowUnsupportedFocus, !focusClaimsAreConsistent(object) {
                throw ObjectResponseIssue.invalidValue("object \(object.id) focus consistency")
            }
        }
        return value
    }

    /// After the model's retry, abstain only on semantic focus failures. All schema,
    /// ownership and claim-pair checks must pass before any claims are removed.
    static func decodeAbstainingFromUnsupportedFocus(_ response: String, boardIDs: Set<String>, expectedConcepts: [String: String] = [:]) throws -> ObjectPhotoAssessment {
        let value = try decode(response, boardIDs: boardIDs, expectedConcepts: expectedConcepts, allowUnsupportedFocus: true)
        let affected = Set(value.objects.filter { object in
            !focusClaimsAreConsistent(object) || (object.focusQuality != .uncertain &&
                (object.focusEvidence.map { focusDescription($0.observation, supports: object.focusQuality) } != true))
        }.map(\.id))
        guard !affected.isEmpty else { return try decode(response, boardIDs: boardIDs, expectedConcepts: expectedConcepts) }
        var sanitized = value
        sanitized.objects = value.objects.map { object in
            guard affected.contains(object.id) else { return object }
            var sanitizedObject = object
            sanitizedObject.focusQuality = .uncertain
            sanitizedObject.focusEvidence = nil
            if containsFocusClaim(object.description) {
                sanitizedObject.description = "Object identified as \(object.concept)."
            }
            let strengths = retainedClaims(object.strengths, evidence: object.strengthEvidence)
            sanitizedObject.strengths = strengths.claims
            sanitizedObject.strengthEvidence = strengths.evidence
            let problems = retainedClaims(object.problems, evidence: object.problemEvidence)
            sanitizedObject.problems = problems.claims
            sanitizedObject.problemEvidence = problems.evidence
            return sanitizedObject
        }
        // A preference may have been based on the rejected focus judgments.
        sanitized.preferredObjectIDs = []
        if let summary = value.imageSummary, containsFocusClaim(summary) {
            sanitized.imageSummary = nil
        }
        sanitized.relationships = value.relationships.filter { !containsFocusClaim($0) }
        return try validate(sanitized, boardIDs: boardIDs, expectedConcepts: expectedConcepts)
    }

    /// Pair counts and crop ownership have already passed validation.
    private static func retainedClaims(_ claims: [String], evidence: [ObjectClaimEvidence]) -> (claims: [String], evidence: [ObjectClaimEvidence]) {
        let pairs = zip(claims, evidence).filter {
            !containsFocusClaim($0.0) && !containsFocusClaim($0.1.observation)
        }
        return (pairs.map(\.0), pairs.map(\.1))
    }

    private static func containsFocusClaim(_ text: String) -> Bool {
        text.range(of: #"(?i)sharp|crisp|focus|blur|smear|indistinct|soft|resolv|detail|texture|defined|definition"#, options: .regularExpression) != nil
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

    /// Conservative wording checks catch explicit contradictions, not visual truth.
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
                of: #"\b(?:clearly|distinctly|well)[ -](?:resolved|defined)\b|\bdistinct edges\b"#,
                options: .regularExpression,
            ) != nil
            let unsupported = text.range(
                of: #"\b(?:not|without|lack|lacks|lacking|no)\s+(?:(?:clearly|distinctly|well)[ -])?(?:sharp|crisp|resolved|defined|distinct|fine|detail)\b|\b(?:soft|unresolved)\b"#,
                options: .regularExpression,
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
