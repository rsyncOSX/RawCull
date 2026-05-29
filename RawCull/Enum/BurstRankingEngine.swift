import Foundation

enum BurstRankingEngine {
    nonisolated static func rank(
        groups: [BurstGroup],
        filesByID: [UUID: FileItem],
        scores: [UUID: Float],
        maxScore: Float,
        saliencyInfo: [UUID: SaliencyInfo],
        boundaryEvidence: [BurstBoundaryEvidence],
        reviewStates: [Int: BurstReviewState] = [:],
    ) -> [BurstAnalysisResult] {
        groups.map { group in
            rankGroup(
                group,
                filesByID: filesByID,
                scores: scores,
                maxScore: maxScore,
                saliencyInfo: saliencyInfo,
                boundaryEvidence: boundaryEvidence,
                reviewState: reviewStates[group.id] ?? .none,
            )
        }
    }

    nonisolated static func rankGroup(
        _ group: BurstGroup,
        filesByID: [UUID: FileItem],
        scores: [UUID: Float],
        maxScore: Float,
        saliencyInfo: [UUID: SaliencyInfo],
        boundaryEvidence: [BurstBoundaryEvidence],
        reviewState: BurstReviewState = .none,
    ) -> BurstAnalysisResult {
        let files = group.fileIDs.compactMap { filesByID[$0] }
        let idSet = Set(group.fileIDs)
        let groupEvidence = boundaryEvidence.filter {
            idSet.contains($0.previousID) && idSet.contains($0.currentID)
        }
        let metadataStable = !groupEvidence.contains { $0.exposureChanged || $0.cameraChanged || $0.lensChanged }
        let tightSimilarity = groupEvidence.allSatisfy { evidence in
            guard let distance = evidence.visualDistance else { return false }
            return distance < 0.22
        }

        let dominantSubject = dominantSubject(in: files, saliencyInfo: saliencyInfo)
        let burstRelativeSharpness = burstRelativeSharpnessComponents(
            fileIDs: group.fileIDs,
            scores: scores,
            maxScore: maxScore,
        )

        var candidates = files.map { file in
            candidate(
                file,
                scores: scores,
                maxScore: maxScore,
                burstRelativeSharpness: burstRelativeSharpness[file.id],
                saliencyInfo: saliencyInfo,
                dominantSubject: dominantSubject,
                metadataStable: metadataStable,
                tightSimilarity: tightSimilarity,
            )
        }
        candidates.sort {
            if $0.overallScore == $1.overallScore {
                let lhsIndex = group.fileIDs.firstIndex(of: $0.fileID) ?? 0
                let rhsIndex = group.fileIDs.firstIndex(of: $1.fileID) ?? 0
                return lhsIndex < rhsIndex
            }
            return $0.overallScore > $1.overallScore
        }

        let best = candidates.first
        let second = candidates.dropFirst().first
        let hasScores = files.contains { scores[$0.id] != nil }
        let confidence = confidence(
            groupSize: files.count,
            best: best,
            second: second,
            hasScores: hasScores,
            metadataStable: metadataStable,
            tightSimilarity: tightSimilarity,
        )
        candidates = candidates.map { item in
            var updated = item
            updated.confidence = confidence
            return updated
        }

        let reasons = resultReasons(best: best, second: second, metadataStable: metadataStable, tightSimilarity: tightSimilarity)
        let cautions = resultCautions(best: best, second: second, hasScores: hasScores, metadataStable: metadataStable, tightSimilarity: tightSimilarity)

        return BurstAnalysisResult(
            groupID: group.id,
            fileIDs: group.fileIDs,
            candidates: candidates,
            recommendedFileID: best?.fileID,
            secondBestFileID: second?.fileID,
            confidence: confidence,
            reviewState: reviewState,
            isSafeForOneClickCulling: confidence == .high,
            reasons: reasons,
            cautions: cautions,
        )
    }

    private nonisolated static func candidate(
        _ file: FileItem,
        scores: [UUID: Float],
        maxScore: Float,
        burstRelativeSharpness: Float?,
        saliencyInfo: [UUID: SaliencyInfo],
        dominantSubject: String?,
        metadataStable: Bool,
        tightSimilarity: Bool,
    ) -> BurstCandidateScore {
        let sharpness = normalizedScore(scores[file.id], maxScore: maxScore)
        let rankingSharpness = if let burstRelativeSharpness {
            sharpness * 0.65 + burstRelativeSharpness * 0.35
        } else {
            sharpness
        }
        let focus = file.afFocusNormalized == nil ? Float(0.45) : Float(0.70)
        let saliency = saliencyComponent(fileID: file.id, saliencyInfo: saliencyInfo, dominantSubject: dominantSubject)
        let metadata = metadataComponent(file: file, metadataStable: metadataStable, tightSimilarity: tightSimilarity)
        let overall = rankingSharpness * 0.62 + focus * 0.12 + saliency * 0.10 + metadata * 0.16

        var reasons: [String] = []
        var cautions: [String] = []
        if scores[file.id] != nil {
            reasons.append("Sharpness measured")
            if burstRelativeSharpness != nil {
                reasons.append("Burst-relative sharpness measured")
            }
        } else {
            cautions.append("Sharpness missing")
        }
        if file.afFocusNormalized != nil {
            reasons.append("AF evidence available")
        } else {
            cautions.append("AF evidence missing")
        }
        if saliencyInfo[file.id]?.subjectLabel != nil {
            reasons.append("Subject classified")
        }
        if !metadataStable {
            cautions.append("Metadata changed")
        }

        return BurstCandidateScore(
            fileID: file.id,
            overallScore: overall,
            sharpnessComponent: sharpness,
            burstRelativeSharpnessComponent: burstRelativeSharpness,
            focusPointComponent: focus,
            saliencyComponent: saliency,
            metadataComponent: metadata,
            confidence: .low,
            reasons: reasons,
            cautions: cautions,
        )
    }

    nonisolated static func burstRelativeSharpnessComponents(
        fileIDs: [UUID],
        scores: [UUID: Float],
        maxScore: Float,
    ) -> [UUID: Float] {
        let normalizedScores = fileIDs.compactMap { fileID -> (UUID, Float)? in
            guard scores[fileID] != nil else { return nil }
            let normalized = normalizedScore(scores[fileID], maxScore: maxScore)
            return normalized.isFinite ? (fileID, normalized) : nil
        }
        guard normalizedScores.count >= 2 else { return [:] }
        guard let minScore = normalizedScores.map(\.1).min(),
              let maxScore = normalizedScores.map(\.1).max() else {
            return [:]
        }
        let spread = maxScore - minScore
        guard spread >= 0.03 else { return [:] }
        return Dictionary(uniqueKeysWithValues: normalizedScores.map { fileID, score in
            (fileID, min(max((score - minScore) / spread, 0), 1))
        })
    }

    private nonisolated static func normalizedScore(_ score: Float?, maxScore: Float) -> Float {
        guard let score, score.isFinite, maxScore.isFinite, maxScore > 0 else { return 0 }
        return min(max(score / maxScore, 0), 1)
    }

    private nonisolated static func saliencyComponent(
        fileID: UUID,
        saliencyInfo: [UUID: SaliencyInfo],
        dominantSubject: String?,
    ) -> Float {
        guard let label = saliencyInfo[fileID]?.subjectLabel else { return 0.45 }
        guard let dominantSubject else { return 0.60 }
        return label == dominantSubject ? 0.75 : 0.25
    }

    private nonisolated static func metadataComponent(
        file: FileItem,
        metadataStable: Bool,
        tightSimilarity: Bool,
    ) -> Float {
        var value: Float = metadataStable ? 0.70 : 0.40
        if tightSimilarity { value += 0.15 }
        if let iso = file.exifData?.isoValue, iso >= 6400 { value -= 0.10 }
        if let aperture = file.exifData?.apertureValue, aperture <= 5.6 { value += 0.05 }
        return min(max(value, 0), 1)
    }

    private nonisolated static func dominantSubject(
        in files: [FileItem],
        saliencyInfo: [UUID: SaliencyInfo],
    ) -> String? {
        let labels = files.compactMap { saliencyInfo[$0.id]?.subjectLabel }
        guard !labels.isEmpty else { return nil }
        return Dictionary(grouping: labels, by: { $0 })
            .max { $0.value.count < $1.value.count }?
            .key
    }

    private nonisolated static func confidence(
        groupSize: Int,
        best: BurstCandidateScore?,
        second: BurstCandidateScore?,
        hasScores: Bool,
        metadataStable: Bool,
        tightSimilarity: Bool,
    ) -> BurstDecisionConfidence {
        guard hasScores, let best else { return .low }
        let gap = best.overallScore - (second?.overallScore ?? 0)
        if groupSize >= 3,
           gap >= 0.12,
           best.sharpnessComponent >= 0.65,
           metadataStable,
           tightSimilarity {
            return .high
        }
        if gap >= 0.05, metadataStable {
            return .medium
        }
        return .low
    }

    private nonisolated static func resultReasons(
        best: BurstCandidateScore?,
        second: BurstCandidateScore?,
        metadataStable: Bool,
        tightSimilarity: Bool,
    ) -> [String] {
        var reasons: [String] = []
        if best?.sharpnessComponent ?? 0 > 0 {
            reasons.append("Sharpest candidate leads")
        }
        if metadataStable {
            reasons.append("Exposure stable")
        }
        if tightSimilarity {
            reasons.append("Subject stable")
        }
        if let best, let second, best.overallScore - second.overallScore >= 0.12 {
            reasons.append("Best is clearly ahead")
        }
        return Array(reasons.prefix(3))
    }

    private nonisolated static func resultCautions(
        best: BurstCandidateScore?,
        second: BurstCandidateScore?,
        hasScores: Bool,
        metadataStable: Bool,
        tightSimilarity: Bool,
    ) -> [String] {
        var cautions: [String] = []
        if !hasScores {
            cautions.append("Sharpness scores missing")
        }
        if !metadataStable {
            cautions.append("Exposure or metadata changed")
        }
        if !tightSimilarity {
            cautions.append("Similarity spread is wider")
        }
        if let best, let second, best.overallScore - second.overallScore < 0.05 {
            cautions.append("Top two are close")
        }
        return Array(cautions.prefix(3))
    }
}
