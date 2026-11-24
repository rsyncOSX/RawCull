import Foundation

/// One plain-language limit, with the pipeline wording it stands for. Repeated limits
/// (the same check failing on several crops) collapse into one note with a count.
nonisolated struct CombinedReviewLimitNote: Identifiable, Sendable {
    enum Group: Int, CaseIterable, Sendable {
        case image, subject, regions, findings, pipeline

        var title: LocalizedStringResource {
            switch self {
            case .image: "The image used"
            case .subject: "Subject and eyes"
            case .regions: "Regions"
            case .findings: "Findings left out"
            case .pipeline: "Review steps"
            }
        }
    }

    let group: Group
    let text: String
    /// The original reasons, unchanged, for anyone who needs the exact wording.
    let details: [String]
    var count: Int {
        details.count
    }

    var id: String {
        "\(group.rawValue)|\(text)"
    }
}

/// Turns the review's pipeline wording into sentences a photographer can read.
/// Presentation only: nothing is dropped, every original reason stays in `details`,
/// and wording the digest does not recognise is shown as it is.
nonisolated enum CombinedReviewLimitDigest {
    static func notes(limitations: [ReviewLimitation], sourceLimitations: [String],
                      omissions: [ReviewRegionOmission]) -> [CombinedReviewLimitNote] {
        var order: [String] = []
        var grouped: [String: (group: CombinedReviewLimitNote.Group, text: String, details: [String])] = [:]
        func add(_ group: CombinedReviewLimitNote.Group, _ text: String, _ detail: String) {
            let key = "\(group.rawValue)|\(text)"
            if grouped[key] == nil {
                order.append(key)
                grouped[key] = (group, text, [])
            }
            grouped[key]?.details.append(detail)
        }
        var seen: Set<String> = []
        for reason in sourceLimitations + limitations.map(\.reason) where seen.insert(reason).inserted {
            let (group, text) = plain(reason)
            add(group, text, reason)
        }
        for omission in omissions {
            add(.regions, plain(omission.reason),
                omission.detail + " · " + omission.reason.rawValue + " · " + omission.regionID.rawValue)
        }
        return order.compactMap { grouped[$0] }
            .map { CombinedReviewLimitNote(group: $0.group, text: $0.text, details: $0.details) }
            .sorted { $0.group.rawValue < $1.group.rawValue }
    }

    static func plain(_ reason: String) -> (CombinedReviewLimitNote.Group, String) {
        func starts(_ prefix: String) -> Bool {
            reason.hasPrefix(prefix)
        }
        func match(_ pattern: String) -> [String]? {
            guard let regex = try? NSRegularExpression(pattern: pattern),
                  let found = regex.firstMatch(in: reason, range: NSRange(reason.startIndex..., in: reason)) else { return nil }
            return (0 ..< found.numberOfRanges).map { index in
                Range(found.range(at: index), in: reason).map { String(reason[$0]) } ?? ""
            }
        }

        // The image the models saw.
        if let parts = match(#"^Preview reduced from (\S+) to (\S+?) "#) {
            return (.image, String(localized: "The review used a reduced preview (\(parts[2]) instead of \(parts[1])), so fine detail is limited."))
        }
        if starts("Camera processing and preview resolution") {
            return (.image, String(localized: "The camera's embedded preview was used, so its processing and resolution limit technical evidence."))
        }
        if starts("Output is SDR") {
            return (.image, String(localized: "Only 8-bit image data was analysed; the RAW file's extra precision was not used."))
        }

        // Subject, head and eyes.
        if starts("Eye localization unavailable") {
            return (.subject, String(localized: "The eyes could not be located, so eye sharpness was not checked."))
        }
        if starts("AF mapping is unavailable") {
            return (.subject, String(localized: "The camera's focus point could not be placed on the image; focus was measured on the subject outline alone."))
        }
        if starts("Main-subject priority is ambiguous") {
            return (.subject, String(localized: "The review could not tell which subject is the main one."))
        }
        if starts("Anatomy is unverified") {
            return (.subject, String(localized: "Head and eye regions are not verified; those crops are treated as general regions."))
        }
        if starts("Subject mask covers at least 95%") {
            return (.subject, String(localized: "The subject outline covers almost the whole photo, so it says little about the subject itself."))
        }
        if starts("No verified subject mask survived") {
            return (.subject, String(localized: "No reliable subject outline was found, so subject sharpness could not be measured."))
        }
        if reason.hasSuffix(": foreground touches the source edge; visibility may be partial.") {
            return (.subject, String(localized: "The subject touches the edge of the photo and may be cut off."))
        }
        if reason.contains("Producer bounds differ from foreground") {
            return (.subject, String(localized: "The subject outline and the detected box disagreed; crops were placed from the outline."))
        }

        // Crops and regions.
        if match(#"^Crop \S+ cannot establish target-specific detail"#) != nil {
            return (.regions, String(localized: "A crop could not show detail of the subject itself."))
        }
        if let parts = match(#"^Crop \S+: Rejected (\w+):"#) {
            return (.findings, String(localized: "A crop's \(criterion(parts[1])) observation failed a check and was not used."))
        }
        if let parts = match(#"^Crop \S+: (.+)$"#) {
            return (.regions, String(localized: "Crop note: \(parts[1])"))
        }
        if let parts = match(#"^(\d+) candidate regions were outside the chosen crop budget"#) {
            return (.regions, String(localized: "\(parts[1]) more regions were found but not inspected at this review depth."))
        }

        // Statements the model made but the review did not accept.
        if let parts = match(#"^Selected (\w+) rejected:"#) {
            return (.findings, String(localized: "The \(criterion(parts[1])) statement did not meet the evidence rules and was dropped."))
        }
        if let parts = match(#"^Selected (\w+) replaced with"#) {
            return (.findings, String(localized: "The \(criterion(parts[1])) statement was replaced with the best-supported observation."))
        }
        if let parts = match(#"^No supported (\w+) claim"#) {
            return (.findings, String(localized: "No \(criterion(parts[1])) finding: the observations did not support one."))
        }
        if starts("Generated claim") {
            return (.findings, String(localized: "A statement in the written report failed validation and was dropped."))
        }
        if starts("Report synthesis failed validation") {
            return (.findings, String(localized: "The written report failed validation, so only the individual observations are shown."))
        }
        if starts("Exposure and crop suggestions are hypotheses") {
            return (.findings, String(localized: "Exposure and crop suggestions are untested ideas; no edited version was evaluated."))
        }

        // Steps that did not run or finish.
        if starts("Overview/discovery unavailable") {
            return (.pipeline, String(localized: "The overview step did not finish; crop observations stand on their own."))
        }
        if starts("SAM unavailable") {
            return (.pipeline, String(localized: "Subject outlines were unavailable, so subject identity and masked detail were not assessed."))
        }
        if starts("CLIP unavailable") {
            return (.pipeline, String(localized: "Relevance matching (CLIP) was unavailable."))
        }
        if starts("Stage "), reason.contains(" unavailable: ") {
            return (.pipeline, String(localized: "A review step did not finish."))
        }
        if starts("Technical render alignment unavailable") {
            return (.pipeline, String(localized: "Technical measurements could not be aligned with the image."))
        }
        if starts("Some optional evidence was omitted") {
            return (.pipeline, String(localized: "Some optional evidence was left out to fit the model's context."))
        }
        if starts("Image review unavailable") {
            return (.pipeline, String(localized: "The review could not run on this image."))
        }
        return (.pipeline, reason)
    }

    static func plain(_ reason: ReviewRegionOmission.Reason) -> String {
        switch reason {
        case .budgetDepthPolicy: String(localized: "A region was not inspected at this review depth.")
        case .geometryFailure: String(localized: "A crop could not be built for a region.")
        case .ambiguousAnatomy: String(localized: "A possible head region was skipped because it could not be tied to one subject.")
        case .contextualPriority: String(localized: "A background or context region was skipped.")
        case .unavailableInput: String(localized: "Image data for a region was unavailable.")
        }
    }

    /// The pipeline's criterion names, in the words the findings use.
    private static func criterion(_ type: String) -> String {
        switch type {
        case "composition": String(localized: "framing")
        case "exposure": String(localized: "lighting")
        case "visibility": String(localized: "subject visibility")
        case "detail": String(localized: "visible detail")
        default: type
        }
    }
}
