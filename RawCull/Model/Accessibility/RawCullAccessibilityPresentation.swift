import Foundation

enum RawCullAccessibilityPresentation {
    static func savedCatalogValue(
        fileCount: Int,
        date: String?,
        isSelected: Bool,
    ) -> String {
        var values = [count(fileCount, singular: "file")]
        if let date, !date.isEmpty {
            values.append(date)
        }
        values.append(isSelected ? "Selected" : "Not selected")
        return values.joined(separator: ", ")
    }

    static func savedRecordValue(
        rating: Int?,
        dateTagged: String?,
        isSelected: Bool,
    ) -> String {
        var values = [ratingDescription(rating)]
        if let dateTagged, !dateTagged.isEmpty {
            values.append("Tagged \(dateTagged)")
        }
        values.append(isSelected ? "Selected" : "Not selected")
        return values.joined(separator: ", ")
    }

    static func imageValue(
        rating: RatingDisplay,
        isSelected: Bool,
        isMultiSelected: Bool,
        semanticRank: Int? = nil,
        semanticResultCount: Int? = nil,
    ) -> String {
        var values = [rating.help]
        if isSelected {
            values.append("Primary selection")
        } else if isMultiSelected {
            values.append("Included in selection")
        } else {
            values.append("Not selected")
        }
        if let semanticRank, let semanticResultCount {
            values.append("Semantic result \(semanticRank) of \(semanticResultCount)")
        }
        return values.joined(separator: ", ")
    }

    static func capabilityValue(
        status: RawCullAICapabilityStatus,
        availableMessage: String,
        missingMessage: String,
    ) -> String {
        switch status {
        case let .checking(expectedLocations):
            if let location = expectedLocations.first {
                "Checking availability at \(location.path)."
            } else {
                "Checking availability."
            }

        case .available:
            "Available. \(availableMessage)"

        case let .missing(expectedLocations):
            if let location = expectedLocations.first {
                "Missing. \(missingMessage) Expected location: \(location.path)"
            } else {
                "Missing. \(missingMessage)"
            }

        case let .invalid(location, reason):
            if let location {
                "Invalid at \(location.path). \(reason)"
            } else {
                "Invalid. \(reason)"
            }

        case let .unavailable(reason):
            "Unavailable. \(reason)"
        }
    }

    static func modelDownloadValue(
        state: RawCullAIModelDownloadState,
        licenceAccepted: Bool,
    ) -> String {
        let stateDescription = switch state {
        case .checking: "Checking availability"
        case let .unavailable(reason): "Unavailable. \(String(localized: reason))"
        case .licenceRequired: "Licence acceptance required"
        case .notConfigured: "Download service not configured"
        case .ready: "Ready to download"

        case let .downloading(progress):
            "Downloading \(Int((min(max(progress, 0), 1) * 100).rounded())) percent"

        case .validating: "Validating downloaded model"
        case .installed: "Installed and managed by macOS"
        case .removing: "Removing downloaded model"
        case let .failed(message): "Download failed. \(message)"
        }
        let licence = licenceAccepted ? "Licence accepted" : "Licence not accepted"
        return "\(stateDescription). \(licence)."
    }

    static func semanticSearchValue(
        _ presentation: SemanticSearchUIPresentation,
    ) -> String {
        let availability = switch presentation.availability {
        case .checking:
            "Checking CLIP availability"

        case let .ready(_, backend):
            "Ready using \(backendDescription(backend))"

        case let .unavailable(reason, _):
            "Unavailable. \(reason)"

        case let .failed(_, reason):
            "Failed. \(reason)"
        }
        let coverage = "\(presentation.coverage.indexedFileCount) of \(presentation.coverage.catalogFileCount) images indexed"
        let activity = switch presentation.activity {
        case .idle:
            "Idle"

        case let .indexing(completed, total, phase):
            "Indexing \(phaseDescription(phase)), \(completed) of \(total)"

        case let .searching(query):
            "Searching for \(query)"

        case let .results(summary):
            "Showing \(summary.resultCount) of \(summary.rankedImageCount) ranked images"

        case let .emptyResults(summary):
            "No results for \(summary.query)"

        case let .emptyIndex(query, excludedFileCount):
            "No compatible index for \(query), \(excludedFileCount) images excluded"

        case let .failed(query, message):
            "Search for \(query) failed. \(message)"
        }
        return "\(availability). \(coverage). \(activity)."
    }

    static func deepReviewValue(
        state: DeepAIReviewPresentationState,
        cachedResult: DeepAIReviewResult?,
    ) -> String {
        if let cachedResult {
            let recommendation = if let fileName = cachedResult.recommendedCandidate?.fileName {
                "Recommends \(fileName)"
            } else {
                "No reliable winner"
            }
            return "Completed. \(recommendation). \(confidence(cachedResult.confidence)) confidence."
        }
        return switch state {
        case .ready, .completed:
            "Idle. AI subject-detail review has not run for this group."

        case .checking:
            "Checking the selected Deep Review model."

        case let .unavailable(reason):
            "Deep Review unavailable. \(reason)"

        case let .preparing(_, totalCount):
            "Preparing Deep Review for \(count(totalCount, singular: "candidate"))."

        case let .running(progress):
            "Running SAM 3 Deep Review, \(progress.completedCount) of \(progress.totalCount) candidates complete."

        case .completing:
            "Completing Deep Review."

        case .cancelled:
            "Deep Review cancelled."

        case let .failed(_, failure):
            "Deep Review failed. \(deepReviewFailure(failure))"
        }
    }

    static func backendDescription(
        _ backend: RawCullSemanticSearchBackendPresentation,
    ) -> String {
        if let modelFingerprint = backend.modelFingerprint {
            return "\(backend.displayName) model \(modelFingerprint)"
        }
        return backend.displayName
    }

    private static func ratingDescription(_ rating: Int?) -> String {
        guard let rating else { return "Unrated" }
        return RatingDisplay(rating: rating).help
    }

    private static func phaseDescription(_ phase: SimilarityIndexingPhase) -> String {
        switch phase {
        case .idle: "idle"
        case .generating: "generating artifacts"
        case .saving: "saving artifacts"
        }
    }

    private static func confidence(_ confidence: DeepAIReviewConfidence) -> String {
        switch confidence {
        case .high: "High"
        case .medium: "Medium"
        case .low: "Low"
        }
    }

    private static func deepReviewFailure(_ failure: DeepAIReviewFailure) -> String {
        switch failure {
        case let .modelUnavailable(reason): reason
        case .noCandidates: "No candidates are available"
        case let .pipelineFailed(reason): "The segmentation pipeline failed. \(reason)"
        }
    }

    private static func count(_ count: Int, singular: String) -> String {
        "\(count) \(singular)\(count == 1 ? "" : "s")"
    }
}
