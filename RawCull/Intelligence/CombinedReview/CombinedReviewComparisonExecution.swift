import AppKit
import CoreGraphics
import Foundation

nonisolated struct CombinedReviewPair: Sendable {
    let left: CombinedReviewResult
    let right: CombinedReviewResult
    let leftRegion: ReviewRegionRecord
    let rightRegion: ReviewRegionRecord
}

// Selection-wide and paired comparison of completed image evidence.
extension CombinedReviewFeature {
    func comparisonPrompt(_ values: [CombinedReviewResult], model: ReviewModelSnapshot, pair: Bool = false) throws -> (text: String, pruned: Bool) {
        let snapshot = try currentManifest().snapshot
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
        let schema = """
        Compare for goal: \(snapshot.criteria). Board labels are image IDs/annotations. \(pair ? "Matched candidate crops; individual identity unverified." : "Full-frame appearance board; no fine-detail evidence.")
        Require shared scene AND subject evidence; generic concepts do not establish identity. Unrelated/missing/conflicting evidence: abstain. Technical detail requires compatible fidelity/scale and cited crop observations from EACH image. CLIP is not quality. No eye/RAW recovery/identity claims. Suggestions are untested.
        JSON only: {"comparability":"insufficient","decision":"abstain","preferred":[],"reason":"Different scenes; retain individual reports.","claims":[]}
        comparability=comparable/unrelated/insufficient; decision=preferred/tie/abstain; preferred=image IDs (1/2+/0). Reason: ONE sentence, max 200 chars; never enumerate photographs there.
        At most 3 claims: {"imageIDs":["ID"],"claim":{"text":"strength/weakness/tradeoff","type":"composition","evidence":[{"kind":"observation","id":"ID"}],"uncertainty":"limits","contradictions":[]}}. Each named image must contribute evidence. Types: composition/exposure/visibility/detail/suggestion. Unresolved ties stay ties. Rows are excerpts; omitted evidence cannot support claims.
        """
        func mandatoryRows(excerptLimit: Int) throws -> [String] {
            var rows: [String] = []
            for value in values {
                let observation = value.observations.first(where: { $0.regionID == nil && $0.availability == .available })
                    ?? value.observations.first(where: { $0.availability == .available && !$0.provenance.workID.rawValue.contains(":reconcile") })
                guard let observation else { throw ReviewValidationIssue(.grounding, "comparison.independentObservation") }
                let reference = try String(decoding: encoder.encode(ReviewEvidenceReference(kind: .observation, id: observation.id.rawValue)), as: UTF8.self)
                rows.append("\(value.file.id.rawValue) \(value.source?.fidelity ?? "unavailable") missing=\(value.report?.incomplete != false) \(reference) \(observation.text.prefix(excerptLimit)) [excerpt; limits: \(observation.uncertainty.prefix(excerptLimit / 2))]")
            }
            return rows
        }
        var prompt = "", excerptLimit = 80
        for limit in [80, 60, 40, 20] {
            let candidate = try schema + "\n" + mandatoryRows(excerptLimit: limit).joined(separator: "\n")
            if (try? CombinedReviewResponse.admitted(candidate, model: model, outputTokens: snapshot.responseTokens)) != nil {
                prompt = candidate; excerptLimit = limit; break
            }
        }
        guard !prompt.isEmpty else { throw ReviewValidationIssue(.responseLength, "comparison.mandatoryPromptFits") }
        var pruned = values.contains { value in
            value.observations.contains { $0.text.count > excerptLimit || $0.uncertainty.count > excerptLimit / 2 }
        }
        let crops = values.map { $0.observations.filter { $0.regionID != nil && $0.availability == .available } }
        for round in 0 ..< (crops.map(\.count).max() ?? 0) {
            for (index, observations) in crops.enumerated() where round < observations.count {
                let observation = observations[round]
                let row = try values[index].file.id.rawValue + " " + String(decoding: encoder.encode(ReviewEvidenceReference(kind: .observation, id: observation.id.rawValue)), as: UTF8.self) + " " + observation.text + " Limits: " + observation.uncertainty
                if (try? CombinedReviewResponse.admitted(prompt + "\n" + row, model: model, outputTokens: snapshot.responseTokens)) != nil {
                    prompt += "\n" + row
                } else {
                    pruned = true
                }
            }
        }
        for value in values {
            for measurement in value.measurements where measurement.hasCurrentMaskSemantics {
                let reference = try String(decoding: encoder.encode(ReviewEvidenceReference(kind: .measurement, id: measurement.id.rawValue)), as: UTF8.self)
                let row = try value.file.id.rawValue + " " + reference + " technical; uncalibrated " + String(decoding: encoder.encode(measurement.values), as: UTF8.self)
                if (try? CombinedReviewResponse.admitted(prompt + "\n" + row, model: model, outputTokens: snapshot.responseTokens)) != nil {
                    prompt += "\n" + row
                } else {
                    pruned = true
                }
            }
        }
        return try (CombinedReviewResponse.admitted(prompt, model: model, outputTokens: snapshot.responseTokens), pruned)
    }

    static func validatePromptReferences(_ report: ReviewSelectionReport, prompt: String) throws {
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
        for reference in report.claims.flatMap({ $0.claim.evidence + $0.claim.contradictions }) {
            guard try prompt.contains(String(decoding: encoder.encode(reference), as: UTF8.self)) else { throw ReviewValidationIssue(.grounding, "comparison.referenceIncludedInPrompt", field: "claims.evidence") }
        }
    }

    func compare(_ backend: any CombinedReviewBackendServing) async throws {
        let snapshot = try currentManifest().snapshot
        guard let qwen = snapshot.models["qwen"], let preference = ReviewSourcePreference(rawValue: snapshot.sourcePreference) else { throw ReviewRunError.invalidSnapshot }
        let id = Self.workID(snapshot.files[0].id, "selection")
        progress = "Comparing completed image evidence"
        let report: ReviewSelectionReport? = try await perform(id, category: .comparison) {
            guard results.allSatisfy({ $0.source != nil && $0.observations.contains { $0.availability == .available } }) else {
                return ReviewSelectionReport(comparability: .insufficient, decision: .abstain, preferred: [], claims: [], reason: "At least one image lacks source or validated observation evidence. Individual outcomes are retained.")
            }
            var images: [(ReviewImageID, CGImage)] = []
            for value in results {
                // Load one source at a time; retain only the small overview for the board.
                let source = try await sourceLoader.load(.init(url: value.file.url, preference: preference, policy: .appearance))
                guard source.metadata.identity == value.source?.sourceIdentity else { throw ReviewRunError.incompatible }
                images.append((value.file.id, source.overview))
            }
            let (board, cells) = try Self.comparisonBoard(images)
            let input = await retain(board)
            comparisonInputReference = input
            let prompt = try comparisonPrompt(results, model: qwen)
            let response = try await backend.respond(instruction: prompt.text, image: board, tokens: snapshot.responseTokens)
            var report = try CombinedReviewResponse.validated(response) { response in
                let report = try ReviewSelectionReport.decode(response)
                try report.validate(results: results)
                try Self.validatePromptReferences(report, prompt: prompt.text)
                return report
            }
            report.cells = cells; report.inputReference = input; report.contextPruned = prompt.pruned
            report.omittedPairs = results.count * (results.count - 1) / 2
            return report
        }
        selectionReport = report ?? .init(comparability: .insufficient, decision: .abstain, preferred: [], claims: [], reason: "Comparison failed validation or exceeded context. Individual reports remain available.")
        comparisonInputReference = selectionReport?.inputReference ?? comparisonInputReference
        try await comparePairs(backend, model: qwen, preference: preference)
    }

    func comparePairs(_ backend: any CombinedReviewBackendServing, model: ReviewModelSnapshot, preference: ReviewSourcePreference) async throws {
        guard let report = selectionReport, report.comparability == .comparable, report.decision == .tie else { return }
        let snapshot = try currentManifest().snapshot
        let candidates = results.filter { report.preferred.contains($0.file.id) }.sorted { $0.file.id.rawValue < $1.file.id.rawValue }
        var eligible: [CombinedReviewPair] = []
        for (index, left) in candidates.enumerated() {
            for right in candidates.dropFirst(index + 1) {
                // No automatic matching of multiple similar subjects. Same concept is a candidate, never proof of identity.
                guard left.subjects.count == 1, right.subjects.count == 1, left.subjects[0].concept == right.subjects[0].concept,
                      let leftRegion = left.regions.first(where: { $0.subjectID == left.subjects[0].id }),
                      let rightRegion = right.regions.first(where: { $0.subjectID == right.subjects[0].id }),
                      leftRegion.fidelity == rightRegion.fidelity, leftRegion.policy == rightRegion.policy,
                      abs(leftRegion.scaleX / rightRegion.scaleX - 1) <= 0.1, abs(leftRegion.scaleY / rightRegion.scaleY - 1) <= 0.1,
                      leftRegion.intendedRegionRetained, rightRegion.intendedRegionRetained,
                      leftRegion.support?.qualifiesWholeSubject == true, rightRegion.support?.qualifiesWholeSubject == true else { continue }
                eligible.append(.init(left: left, right: right, leftRegion: leftRegion, rightRegion: rightRegion))
            }
        }
        for pair in eligible.prefix(snapshot.depth.pairCap) {
            let left = pair.left, right = pair.right, leftRegion = pair.leftRegion, rightRegion = pair.rightRegion
            let workID = Self.workID(snapshot.files[0].id, "pair:" + left.file.id.rawValue + ":" + right.file.id.rawValue)
            if manifest?.work.contains(where: { $0.id == workID }) != true {
                try manifest?.work.append(.init(id: workID, imageID: snapshot.files[0].id, stage: .comparison,
                                                dependencies: [.init(id: Self.workID(snapshot.files[0].id, "selection"), allowsUnavailable: false)],
                                                compatibility: ReviewCompatibility.make(snapshot: snapshot, image: snapshot.files[0], stage: .comparison, region: leftRegion.id.rawValue + ":" + rightRegion.id.rawValue)))
            }
            let value: ReviewSelectionReport? = try await perform(workID, category: .comparison) {
                var crops: [(ReviewImageID, CGImage)] = []
                for (value, region) in [(left, leftRegion), (right, rightRegion)] {
                    let source = try await sourceLoader.load(.init(url: value.file.url, preference: preference, policy: .appearance))
                    guard source.metadata.identity == region.sourceIdentity, let crop = source.image.cropping(to: region.sourceRect) else { throw ReviewRunError.incompatible }
                    crops.append((value.file.id, crop))
                }
                let (board, cells) = try Self.comparisonBoard(crops)
                let prompt = try comparisonPrompt([left, right], model: model, pair: true)
                let response = try await backend.respond(instruction: prompt.text, image: board, tokens: snapshot.responseTokens)
                var value = try CombinedReviewResponse.validated(response) { response in
                    let value = try ReviewSelectionReport.decode(response)
                    try value.validate(results: [left, right]); try Self.validatePromptReferences(value, prompt: prompt.text)
                    return value
                }
                value.cells = cells; value.inputReference = await retain(board); value.contextPruned = prompt.pruned
                return value
            }
            if let value {
                selectionReport?.pairReports.append(value)
            }
        }
        let completedPairs = selectionReport?.pairReports.count ?? 0
        selectionReport?.omittedPairs = max(0, report.omittedPairs - completedPairs)
        // Pair suggestions remain explicit tradeoffs. They cannot silently resolve a selection-wide tie.
    }
}
