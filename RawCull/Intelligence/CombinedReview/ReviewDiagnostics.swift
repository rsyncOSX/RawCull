import Foundation

nonisolated enum ReviewDiagnosticRetention: String, Codable, Sendable { case compact, boundedRejectedText }

nonisolated enum ReviewValidationCode: String, Codable, Sendable {
    case json, schema, unknownID, ownership, unsupportedDomain, responseLength, grounding, maskDecoding, geometry
    case runtime, timeout, cancellation, budget, incompatible
}

/// Reasons/paths are owned constants, never interpolated model text, file paths or decoder descriptions.
nonisolated struct ReviewValidationIssue: Error, Sendable {
    let code: ReviewValidationCode
    let check: String
    let fieldPath: String?
    let evidenceReference: ReviewEvidenceReference?
    init(_ code: ReviewValidationCode, _ check: String, field: String? = nil, reference: ReviewEvidenceReference? = nil) {
        self.code = code; self.check = check; fieldPath = field; evidenceReference = reference
    }

    private static func safePath(_ path: String) -> String? {
        let known = Set(["observations", "uncertainty", "regionID", "insufficientEvidence", "claims", "text", "type", "evidence", "contradictions", "kind", "id", "concepts", "query", "displayName", "reason", "primarySubjects", "contextualConcepts", "concept", "location", "x", "y", "comparability", "decision", "preferred", "imageIDs", "claim"])
        let parts = path.split(separator: ".").filter { known.contains(String($0)) || $0.allSatisfy(\.isNumber) }.map(String.init)
        return parts.isEmpty ? nil : String(parts.joined(separator: ".").prefix(120))
    }

    static func classify(_ error: any Error) -> Self {
        if let value = error as? Self { return value }
        if let value = error as? ReviewResponseRejection { return value.issue }
        if let value = error as? ObjectResponseIssue {
            switch value {
            case .invalidJSON, .incompleteJSON: return .init(.json, "json.completeObject")
            case let .invalidSchema(path): return .init(.schema, "schema.requiredFieldOrType", field: safePath(path))
            case let .invalidValue(path): return .init(.schema, "schema.value", field: safePath(path))
            case .unknownID, .missingID, .duplicateID: return .init(.unknownID, "reference.knownUniqueID")
            case .tooManyItems: return .init(.responseLength, "schema.itemCount")
            }
        }
        if let value = error as? SubjectMaskDecodingError {
            return .init(value == .unsafeRegistration ? .geometry : .maskDecoding, "mask." + value.rawValue, field: "subjectMask")
        }
        if let value = error as? ReviewImageError {
            switch value {
            case .invalidGeometry, .unsupportedAlignment: return .init(.geometry, "source.registeredGeometry")
            default: return .init(.runtime, "source.availableRender")
            }
        }
        if let value = error as? ReviewRunError {
            switch value {
            case .budgetExhausted: return .init(.budget, "budget.allowance")
            case .incompatible: return .init(.incompatible, "compatibility.currentSemantics")
            case .invalidEvidence: return .init(.grounding, "evidence.stageValidation")
            default: return .init(.runtime, "execution.availableDependency")
            }
        }
        if error is CancellationError { return .init(.cancellation, "execution.cancelled") }
        let nsError = error as NSError
        if nsError.domain == NSURLErrorDomain, nsError.code == NSURLErrorTimedOut { return .init(.timeout, "runtime.timeout") }
        return .init(.runtime, "runtime.stageFailure")
    }
}

nonisolated struct ReviewResponseRejection: Error, Sendable {
    let issue: ReviewValidationIssue
    let response: String
}

nonisolated struct ReviewFailureDiagnostic: Codable, Sendable {
    let stage: ReviewStage
    let workID: ReviewWorkID
    let code: ReviewValidationCode
    let check: String
    let fieldPath: String?
    let evidenceReference: ReviewEvidenceReference?
    var rejectedResponseKey: String?
    var retainedResponseBytes: Int = 0
    var responseTruncated: Bool = false
    var retentionUnavailable: Bool = false
    var compactReason: String { code.rawValue + ": " + check }
}

nonisolated struct ReviewRejectedResponse: Codable, Sendable {
    let runID: UUID
    let workID: ReviewWorkID
    let text: String
    let truncated: Bool
}

nonisolated enum ReviewDiagnosticLimits {
    static let perResponseBytes = 4096
    static let perRunBytes = 32768
    static func bounded(_ text: String, maximumBytes: Int) -> (text: String, truncated: Bool) {
        var prefix = Array(text.utf8.prefix(max(0, maximumBytes)))
        while String(bytes: prefix, encoding: .utf8) == nil { prefix.removeLast() }
        return (String(bytes: prefix, encoding: .utf8) ?? "", prefix.count < text.utf8.count)
    }
}

nonisolated struct ReviewEvidenceOnlySummary: Codable, Sendable {
    struct Row: Codable, Sendable {
        let reference: ReviewEvidenceReference
        let text: String
        let availability: ReviewEvidenceAvailability
    }
    let label: String
    let rows: [Row]
    let limitations: [String]
    static func make(_ result: CombinedReviewResult) -> Self {
        let observations = result.observations.filter { !$0.provenance.workID.rawValue.contains(":reconcile") }.map {
            Row(reference: .init(kind: .observation, id: $0.id.rawValue), text: $0.text + " · " + $0.uncertainty, availability: $0.availability)
        }
        let measurements = result.measurements.map { value in
            Row(reference: .init(kind: .measurement, id: value.id.rawValue),
                text: "Subject " + value.subjectID.rawValue + "; scorer " + (value.scorerVersion ?? "unknown") + "; " + value.values.keys.sorted().map { "\($0)=\(value.values[$0, default: 0])" }.joined(separator: ", "),
                availability: value.hasCurrentMaskSemantics ? value.availability : .unknown)
        }
        return .init(label: "Evidence-only summary — unsynthesized", rows: observations + measurements, limitations: result.limitations.map(\.reason))
    }
}
