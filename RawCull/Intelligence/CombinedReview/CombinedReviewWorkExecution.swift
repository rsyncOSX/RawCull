import CoreGraphics
import Foundation

// Shared work lifecycle and evidence support. Mutable run state remains on the feature.
extension CombinedReviewFeature {
    func perform<Value: Codable & Sendable>(_ id: ReviewWorkID, category: ReviewAttemptCategory? = nil,
                                            operation: () async throws -> Value) async throws -> Value? {
        try Task.checkCancellation()
        guard let item = manifest?.work.first(where: { $0.id == id }) else { throw ReviewRunError.invalidDependency }
        if item.state == .completed, let key = item.artifactKey {
            let artifact = try await store.loadArtifact(key: key, expected: item.compatibility)
            return try JSONDecoder().decode(Value.self, from: artifact.payload)
        }
        if item.state.terminal {
            result?.failures[id.rawValue] = item.reason; return nil
        }
        do {
            try manifest?.begin(id, category: category)
            try await store.saveManifest(currentManifest())
            let value = try await operation()
            try Task.checkCancellation()
            let payload = try JSONEncoder().encode(value)
            let key = store.artifactKey(id, compatibility: item.compatibility)
            var completed = try currentManifest()
            try completed.finish(id, state: .completed, artifactKey: key)
            try await store.commit(.init(workID: id, compatibility: item.compatibility, payload: payload, created: Date()), manifest: completed)
            manifest = completed
            return value
        } catch is CancellationError { throw CancellationError() } catch {
            try Task.checkCancellation()
            let diagnostic = await failureDiagnostic(error, item: item)
            try Task.checkCancellation()
            if manifest?.work.first(where: { $0.id == id })?.state == .running {
                try manifest?.finish(id, state: .failed, reason: diagnostic.compactReason)
            } else {
                try manifest?.skip(id, reason: diagnostic.compactReason)
            }
            if let index = manifest?.work.firstIndex(where: { $0.id == id }) {
                manifest?.work[index].diagnostic = diagnostic
            }
            result?.failures[id.rawValue] = diagnostic.compactReason
            try await store.saveManifest(currentManifest())
            return nil
        }
    }

    /// One fresh response may repair a malformed request-boundary payload. Every
    /// additional model call is charged and the original rejection is retained.
    func validatedResponse<Value>(instruction: String, image: CGImage, model: ReviewModelSnapshot,
                                  tokens: Int, backend: any CombinedReviewBackendServing,
                                  validation: (String) throws -> Value) async throws -> Value {
        let text = try await backend.respond(instruction: instruction, image: image, tokens: tokens)
        do {
            return try CombinedReviewResponse.validated(text, validation)
        } catch let rejection as ReviewResponseRejection {
            guard CombinedReviewResponse.canRepair(rejection.issue),
                  let file = activeFile else { throw rejection }
            let correction = CombinedReviewResponse.repairInstruction(for: rejection.issue)
            // Keep the full original schema and evidence; never truncate to fit a repair.
            guard let prompt = try? CombinedReviewResponse.admitted(instruction + "\n" + correction, model: model, outputTokens: tokens) else { throw rejection }
            do { try manifest?.budget.consume(.repair, imageID: file.id) } catch { throw rejection }
            if let index = manifest?.work.firstIndex(where: { $0.imageID == file.id && $0.state == .running }) {
                manifest?.work[index].attempts += 1
            }
            try await store.saveManifest(currentManifest())
            try Task.checkCancellation()
            let repaired = try await backend.respond(instruction: prompt, image: image, tokens: tokens)
            let value = try CombinedReviewResponse.validated(repaired, validation)
            if let item = manifest?.work.first(where: { $0.imageID == file.id && $0.state == .running }) {
                let diagnostic = await failureDiagnostic(rejection, item: item)
                if let index = manifest?.work.firstIndex(where: { $0.id == item.id }) {
                    manifest?.work[index].diagnostic = diagnostic
                }
            }
            return value
        }
    }

    func failureDiagnostic(_ error: any Error, item: ReviewWorkItem) async -> ReviewFailureDiagnostic {
        let issue = ReviewValidationIssue.classify(error)
        var diagnostic = ReviewFailureDiagnostic(stage: item.stage, workID: item.id, code: issue.code,
                                                 check: issue.check, fieldPath: issue.fieldPath, evidenceReference: issue.evidenceReference)
        if let rejection = error as? ReviewResponseRejection,
           let snapshot = manifest?.snapshot, snapshot.diagnosticRetention == .boundedRejectedText {
            let used = manifest?.retainedDiagnosticBytes ?? 0
            let cap = min(ReviewDiagnosticLimits.perResponseBytes, max(0, ReviewDiagnosticLimits.perRunBytes - used))
            let bounded = ReviewDiagnosticLimits.bounded(rejection.response, maximumBytes: cap)
            diagnostic.responseTruncated = bounded.truncated
            if !bounded.text.isEmpty {
                do {
                    diagnostic.rejectedResponseKey = try await store.retainRejectedResponse(.init(runID: snapshot.id, workID: item.id, text: bounded.text, truncated: bounded.truncated))
                    diagnostic.retainedResponseBytes = bounded.text.utf8.count
                    manifest?.retainedDiagnosticBytes = used + diagnostic.retainedResponseBytes
                } catch { diagnostic.retentionUnavailable = true }
            }
        }
        return diagnostic
    }

    func addWork(_ name: String, stage: ReviewStage, parents: [ReviewWorkID], source: String, region: String = "") throws -> ReviewWorkID {
        let run = try currentManifest()
        guard let file = activeFile else { throw ReviewRunError.invalidSnapshot }
        let id = Self.workID(file.id, name)
        if let existing = run.work.first(where: { $0.id == id }) {
            let expected = try ReviewCompatibility.make(snapshot: run.snapshot, image: file, stage: stage,
                                                        sourceRender: source, region: region)
            guard existing.stage == stage, existing.compatibility == expected else { throw ReviewRunError.incompatible }
            return id
        }
        try manifest?.work.append(.init(id: id, imageID: file.id, stage: stage,
                                        dependencies: parents.map { .init(id: $0, allowsUnavailable: true) },
                                        compatibility: ReviewCompatibility.make(snapshot: run.snapshot, image: file, stage: stage, sourceRender: source, region: region)))
        return id
    }

    func retain(_ image: CGImage, force: Bool = false) async -> String? {
        guard force || manifest?.snapshot.retentionPolicy == .exactInputs else { return nil }
        return try? await store.retainInput(Self.encodeInput(image))
    }

    @concurrent static func encodeInput(_ image: CGImage) async throws -> Data {
        try Task.checkCancellation()
        return try ReviewImageSource.pngData(for: image)
    }

    func limitation(_ reason: String) {
        guard let file = result?.file, result?.limitations.contains(where: { $0.reason == reason }) != true else { return }
        result?.limitations.append(.init(id: .init(rawValue: file.id.rawValue + ":limit:" + ReviewCompatibility.digest(reason)), reason: reason, relatedEvidence: []))
    }

    func provenance(_ id: ReviewWorkID, source: ReviewImageSource, input: String? = nil) throws -> ReviewEvidenceProvenance {
        guard let item = manifest?.work.first(where: { $0.id == id }), let file = result?.file else { throw ReviewRunError.invalidEvidence }
        return .init(workID: id, imageID: file.id, sourceIdentity: source.metadata.identity,
                     renderPolicy: source.metadata.policy.rawValue, compatibility: item.compatibility,
                     modelIdentity: item.compatibility.fields["model"], inputReference: input)
    }

    func replaceDependencies(_ id: ReviewWorkID, with parents: [ReviewWorkID]) {
        guard let index = manifest?.work.firstIndex(where: { $0.id == id }), let item = manifest?.work[index], item.state == .pending else { return }
        var replacement = ReviewWorkItem(id: item.id, imageID: item.imageID, stage: item.stage,
                                         dependencies: parents.map { .init(id: $0, allowsUnavailable: true) }, compatibility: item.compatibility)
        replacement.attempts = item.attempts
        manifest?.work[index] = replacement
    }
}
