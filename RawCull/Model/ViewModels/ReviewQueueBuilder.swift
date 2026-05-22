import Foundation

struct ReviewQueueBuilder {
    struct Input {
        var catalog: URL?
        var files: [FileItem]
        var burstGroups: [BurstGroup]
        var burstResults: [Int: BurstAnalysisResult]
        var boundaryEvidence: [BurstBoundaryEvidence]
        var sharpnessScores: [UUID: Float]
        var sharpnessWasExpected: Bool
        var diagnosticIssues: [RawFileDiagnosticIssue]
        var copyOutput: [String]
        var persistedStates: [ReviewQueueItemState]
        var createdAt: Date = .init()
    }

    func build(input: Input) -> [ReviewQueueItem] {
        let filesByID = Dictionary(uniqueKeysWithValues: input.files.map { ($0.id, $0) })
        let groupsByID = Dictionary(uniqueKeysWithValues: input.burstGroups.map { ($0.id, $0) })
        let stateByFingerprint = Dictionary(uniqueKeysWithValues: input.persistedStates.map { ($0.fingerprint, $0) })

        var items: [ReviewQueueItem] = []
        items += burstItems(input: input, groupsByID: groupsByID, filesByID: filesByID)
        items += sharpnessItems(input: input)
        items += diagnosticItems(input: input)
        items += metadataItems(input: input, filesByID: filesByID)
        items += catalogItems(input: input)
        items += copyItems(input: input)

        var deduped: [String: ReviewQueueItem] = [:]
        for item in items {
            guard deduped[item.fingerprint] == nil else { continue }
            var item = item
            if let persisted = stateByFingerprint[item.fingerprint] {
                item.resolutionState = persisted.resolutionState
                item.resolvedAt = persisted.resolvedAt
            }
            deduped[item.fingerprint] = item
        }

        return deduped.values.sorted { lhs, rhs in
            if lhs.resolutionState != rhs.resolutionState {
                return lhs.resolutionState.rawValue < rhs.resolutionState.rawValue
            }
            if lhs.severity != rhs.severity {
                return lhs.severity > rhs.severity
            }
            if lhs.category != rhs.category {
                return lhs.category.title < rhs.category.title
            }
            return lhs.title.localizedStandardCompare(rhs.title) == .orderedAscending
        }
    }

    private func burstItems(
        input: Input,
        groupsByID: [Int: BurstGroup],
        filesByID: [UUID: FileItem],
    ) -> [ReviewQueueItem] {
        input.burstResults.values.compactMap { result in
            guard result.reviewState == .none || result.reviewState == .algorithmReviewed else { return nil }
            guard result.confidence == .low || result.confidence == .medium else { return nil }
            let groupFileNames = groupsByID[result.groupID]?.fileIDs.compactMap { filesByID[$0]?.name } ?? []
            let subject = groupFileNames.joined(separator: ",")
            let title = result.confidence == .low ? "Low-confidence burst" : "Review burst recommendation"
            let detail = (result.cautions + result.reasons).first ?? "RawCull is not fully confident about the recommended frame."
            return makeItem(
                input: input,
                category: .burst,
                severity: result.confidence == .low ? .warning : .info,
                fileName: groupFileNames.first,
                fileID: groupsByID[result.groupID]?.fileIDs.first,
                groupID: result.groupID,
                relatedFileNames: groupFileNames,
                title: title,
                detail: detail,
                recommendedAction: result.confidence == .low ? "Open comparison for this burst" : "Review top burst candidates",
                source: .burstAnalysis,
                subject: subject.isEmpty ? "group-\(result.groupID)" : subject,
                reason: "burst-\(result.confidence.rawValue)",
            )
        }
    }

    private func sharpnessItems(input: Input) -> [ReviewQueueItem] {
        guard input.sharpnessWasExpected else { return [] }
        return input.files.compactMap { file in
            guard input.sharpnessScores[file.id] == nil else { return nil }
            return makeItem(
                input: input,
                category: .sharpness,
                severity: .warning,
                fileName: file.name,
                fileID: file.id,
                groupID: nil,
                relatedFileNames: [file.name],
                title: "Missing sharpness score",
                detail: "This file does not have a saved sharpness score after scoring was expected to complete.",
                recommendedAction: "Re-run sharpness scoring",
                source: .sharpnessScoring,
                subject: file.name,
                reason: "missing-sharpness",
            )
        }
    }

    private func diagnosticItems(input: Input) -> [ReviewQueueItem] {
        input.diagnosticIssues.map { issue in
            let file = input.files.first { $0.name == issue.fileName }
            return makeItem(
                input: input,
                category: issue.category,
                severity: issue.severity,
                fileName: issue.fileName,
                fileID: file?.id,
                groupID: nil,
                relatedFileNames: [issue.fileName],
                title: issue.category == .parser ? "RAW parser issue" : "Catalog issue",
                detail: "\(issue.message) \(issue.recoveryHint)",
                recommendedAction: issue.category == .parser ? "Open diagnostics for this file" : "Review catalog health",
                source: issue.category == .parser ? .rawDiagnostics : .catalogHealth,
                subject: issue.fileName,
                reason: issue.message,
            )
        }
    }

    private func metadataItems(input: Input, filesByID: [UUID: FileItem]) -> [ReviewQueueItem] {
        input.boundaryEvidence.compactMap { evidence in
            guard evidence.exposureChanged || evidence.cameraChanged || evidence.lensChanged else { return nil }
            guard let previous = filesByID[evidence.previousID], let current = filesByID[evidence.currentID] else { return nil }
            let changes = [
                evidence.exposureChanged ? "exposure" : nil,
                evidence.cameraChanged ? "camera" : nil,
                evidence.lensChanged ? "lens" : nil
            ].compactMap(\.self)
            let related = [previous.name, current.name]
            return makeItem(
                input: input,
                category: .metadata,
                severity: .info,
                fileName: current.name,
                fileID: current.id,
                groupID: nil,
                relatedFileNames: related,
                title: "Metadata changed in close sequence",
                detail: "Detected a \(changes.joined(separator: ", ")) change between adjacent files.",
                recommendedAction: "Review the group boundary",
                source: .burstAnalysis,
                subject: related.joined(separator: ","),
                reason: "metadata-\(changes.joined(separator: "-"))",
            )
        }
    }

    private func catalogItems(input: Input) -> [ReviewQueueItem] {
        let duplicates = Dictionary(grouping: input.files, by: \.name)
            .filter { $0.value.count > 1 }
        return duplicates.map { name, files in
            makeItem(
                input: input,
                category: .catalog,
                severity: .blocking,
                fileName: name,
                fileID: files.first?.id,
                groupID: nil,
                relatedFileNames: files.map(\.name),
                title: "Duplicate file name",
                detail: "Multiple files in this catalog share the same durable file name, which can make saved review state ambiguous.",
                recommendedAction: "Rename or separate duplicate files",
                source: .catalogHealth,
                subject: name,
                reason: "duplicate-file-name",
            )
        }
    }

    private func copyItems(input: Input) -> [ReviewQueueItem] {
        let issueLines = input.copyOutput.filter { line in
            let lowercased = line.lowercased()
            return lowercased.contains("error") ||
                lowercased.contains("failed") ||
                lowercased.contains("permission denied") ||
                lowercased.contains("no such file") ||
                lowercased.contains("skipped")
        }
        guard !issueLines.isEmpty else { return [] }

        return [
            makeItem(
                input: input,
                category: .copy,
                severity: .blocking,
                fileName: nil,
                fileID: nil,
                groupID: nil,
                relatedFileNames: extractFileNames(from: issueLines, knownFiles: input.files),
                title: "Copy reported issues",
                detail: issueLines.prefix(3).joined(separator: " "),
                recommendedAction: "Open rsync output",
                source: .rsyncCopy,
                subject: issueLines.joined(separator: "|"),
                reason: "rsync-copy-issue",
            )
        ]
    }

    private func extractFileNames(from lines: [String], knownFiles: [FileItem]) -> [String] {
        knownFiles
            .map(\.name)
            .filter { name in lines.contains { $0.contains(name) } }
    }

    private func makeItem(
        input: Input,
        category: ReviewQueueCategory,
        severity: ReviewQueueSeverity,
        fileName: String?,
        fileID: UUID?,
        groupID: Int?,
        relatedFileNames: [String],
        title: String,
        detail: String,
        recommendedAction: String,
        source: ReviewQueueSource,
        subject: String,
        reason: String,
    ) -> ReviewQueueItem {
        ReviewQueueItem(
            category: category,
            severity: severity,
            resolutionState: .open,
            fileName: fileName,
            fileID: fileID,
            groupID: groupID,
            relatedFileNames: relatedFileNames,
            title: title,
            detail: detail,
            recommendedAction: recommendedAction,
            source: source,
            createdAt: input.createdAt,
            resolvedAt: nil,
            fingerprint: ReviewQueueFingerprint.make(
                catalog: input.catalog,
                category: category,
                subject: subject,
                reason: reason,
            ),
        )
    }
}
