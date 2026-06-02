import SwiftUI

struct CandidateInspectorView: View {
    let context: CandidateInspectorContext?

    var body: some View {
        if let context {
            Form {
                Section("Candidate") {
                    LabeledContent("File", value: context.file.name)
                    LabeledContent("Rank", value: "#\(context.rank)")
                    LabeledContent("Overall Score", value: percent(context.candidate.overallScore))
                    LabeledContent("Confidence", value: context.confidence.title)
                    LabeledContent("Rating", value: ratingTitle(context.rating))
                    if let saliencyLabel = context.saliencyLabel {
                        LabeledContent("Subject", value: saliencyLabel)
                    }
                    LabeledContent("Focus Points", value: context.hasFocusPoints ? "Available" : "Unavailable")
                    if let sharpnessScore = context.sharpnessScore {
                        LabeledContent("Sharpness", value: percent(sharpnessScore))
                    }
                }

                Section("Score Components") {
                    LabeledContent("Sharpness", value: percent(context.candidate.sharpnessComponent))
                    if let burstRelativeSharpness = context.candidate.burstRelativeSharpnessComponent {
                        LabeledContent("Burst-relative", value: percent(burstRelativeSharpness))
                    }
                    LabeledContent("Focus Point", value: percent(context.candidate.focusPointComponent))
                    LabeledContent("Saliency", value: percent(context.candidate.saliencyComponent))
                    LabeledContent("Metadata", value: percent(context.candidate.metadataComponent))
                    if let breakdown = context.sharpnessBreakdown {
                        if let subjectScore = breakdown.subjectScore {
                            LabeledContent("Subject Detail", value: percent(subjectScore))
                        }
                        if let globalScore = breakdown.globalScore {
                            LabeledContent("Global Detail", value: percent(globalScore))
                        }
                        if let afPointScore = breakdown.afPointScore {
                            LabeledContent("AF Detail", value: percent(afPointScore))
                        }
                        LabeledContent("Source", value: breakdown.scoringSource.title)
                        LabeledContent("Blur Gate", value: decimal(breakdown.blurGateSigma))
                        if let subjectLabel = breakdown.subjectLabel {
                            LabeledContent("Subject Label", value: subjectLabel)
                        }
                        if let subjectConfidence = breakdown.subjectConfidence {
                            LabeledContent("Subject Confidence", value: percent(subjectConfidence))
                        }
                        LabeledContent("Focus Flag", value: breakdown.focusFailureKind.title)
                        if let regionSource = breakdown.focusMaskRegionSource {
                            LabeledContent("Mask Region", value: regionSource.title)
                        }
                        if let visualThreshold = breakdown.focusMaskVisualThreshold {
                            LabeledContent("Mask Threshold", value: decimal(visualThreshold))
                        }
                    }
                }

                if let evidence = context.sharpnessBreakdown?.focusEvidence {
                    Section("Focus Evidence") {
                        LabeledContent("Winning Region", value: evidence.winningRegion.title)
                        if let region = evidence.visualizedRegion {
                            LabeledContent("Rendered Region", value: region.title)
                        }
                        if let style = evidence.overlayStyle {
                            LabeledContent("Overlay Style", value: style.title)
                        }
                        if let localScore = evidence.scoringLocalDetailScore {
                            LabeledContent("Scoring Local Detail", value: percent(localScore))
                        }
                        if let afCenterScore = evidence.afCenterScore {
                            LabeledContent("AF Center Detail", value: percent(afCenterScore))
                        }
                        if let afNeighborhoodScore = evidence.afNeighborhoodScore {
                            LabeledContent("AF Neighborhood Detail", value: percent(afNeighborhoodScore))
                        }
                        if let afPatchScore = evidence.scoringAFLocalPatchScore {
                            LabeledContent("Scoring AF Patch", value: percent(afPatchScore))
                        }
                        if let subjectPatchScore = evidence.scoringSubjectInteriorPatchScore {
                            LabeledContent("Scoring Subject Patch", value: percent(subjectPatchScore))
                        }
                        LabeledContent("Saliency Candidates", value: "\(evidence.saliencyCandidateCount)")
                        if let reason = evidence.saliencySelectionReason {
                            LabeledContent("Saliency Selection", value: reason)
                        }
                        if let confidence = evidence.focusEvidenceConfidence {
                            LabeledContent("Location Confidence", value: confidence.title)
                        }
                        if let reason = evidence.focusEvidenceConfidenceReason {
                            Text(reason)
                                .foregroundStyle(evidenceNeedsReview(evidence) ? .orange : .secondary)
                        }
                        if let distance = evidence.afDistanceFromCentroid {
                            LabeledContent("AF Distance", value: percent(distance))
                        }
                        if let alignment = evidence.spatialAlignmentScore {
                            LabeledContent("Spatial Alignment", value: percent(alignment))
                        }
                        if let threshold = evidence.effectiveVisualThreshold {
                            LabeledContent("Evidence Threshold", value: decimal(threshold))
                        }
                        if let coverage = evidence.maskCoverage {
                            LabeledContent("Evidence Coverage", value: percent(coverage))
                        }
                        LabeledContent("Visibility Relaxed", value: evidence.relaxedForVisibility ? "Yes" : "No")
                        if let dominance = evidence.localPatchDominance {
                            LabeledContent("Patch Dominance", value: decimal(dominance))
                        }
                        LabeledContent("Silhouette Penalty", value: evidence.silhouettePenaltyApplied ? "Applied" : "None")
                        ForEach(Array(evidence.patchRankings.prefix(3).enumerated()), id: \.offset) { index, patch in
                            LabeledContent("Patch \(index + 1)", value: patchSummary(patch))
                        }
                        if evidenceNeedsReview(evidence) {
                            Text("Review focus location: evidence is global-only or not aligned with the AF marker.")
                                .foregroundStyle(.orange)
                        }
                    }
                }

                if !context.exifSummary.detailRows.isEmpty {
                    Section("Camera Settings") {
                        ForEach(context.exifSummary.detailRows) { row in
                            LabeledContent(row.label, value: row.value)
                        }
                    }
                }

                if !context.candidate.reasons.isEmpty {
                    Section("Candidate Reasons") {
                        bulletList(context.candidate.reasons)
                    }
                }

                if !context.candidate.cautions.isEmpty {
                    Section("Candidate Cautions") {
                        bulletList(context.candidate.cautions, color: .orange)
                    }
                }

                if !context.groupReasons.isEmpty || !context.groupCautions.isEmpty {
                    Section("Group Evidence") {
                        bulletList(context.groupReasons)
                        bulletList(context.groupCautions, color: .orange)
                    }
                }

                Section("Rank Table") {
                    ForEach(context.rankRows) { row in
                        CandidateRankRowView(row: row)
                    }
                }
            }
            .formStyle(.grouped)
            .navigationTitle("Candidate Inspector")
        } else {
            ContentUnavailableView(
                "No Candidate Selected",
                systemImage: "sidebar.right",
                description: Text("Select a burst candidate in comparison view to inspect ranking evidence."),
            )
            .padding()
        }
    }

    private func percent(_ value: Float) -> String {
        "\(Int((value * 100).rounded()))%"
    }

    private func decimal(_ value: Float) -> String {
        String(format: "%.2f", value)
    }

    private func patchSummary(_ patch: FocusPatchRanking) -> String {
        let distance = patch.distanceToAF.map { String(format: "%.3f", $0) } ?? "—"
        return String(
            format: "%.3f  AF %@  cover %.2f  eye %+0.2f  ring %.2f  compact %.2f  line %.2f  below %.2f",
            patch.compositeScore,
            distance,
            patch.coverage,
            patch.eyeHeadHeuristicAdjustment,
            patch.ringDetailScore,
            patch.compactDetailScore,
            patch.linearEdgePenalty,
            patch.belowAFPenalty,
        )
    }

    private func evidenceNeedsReview(_ evidence: FocusEvidence) -> Bool {
        evidence.visualizedRegion == .global || evidence.focusEvidenceConfidence == .low
    }

    private func ratingTitle(_ rating: Int) -> String {
        switch rating {
        case -1: "Rejected"
        case 0: "Picked"
        case 1 ... 5: "\(rating) star"
        default: "Unrated"
        }
    }

    private func bulletList(_ items: [String], color: Color = .secondary) -> some View {
        ForEach(items, id: \.self) { item in
            Text(item)
                .foregroundStyle(color)
        }
    }
}

private struct CandidateRankRowView: View {
    let row: CandidateRankRow

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text("#\(row.rank)")
                .font(.system(.caption, design: .monospaced).weight(.semibold))
                .frame(width: 28, alignment: .leading)

            VStack(alignment: .leading, spacing: 2) {
                Text(row.fileName)
                    .lineLimit(1)
                HStack(spacing: 4) {
                    if row.isManualWinner {
                        rankBadge("Manual", color: .orange)
                    } else if row.isRecommended {
                        rankBadge("Best", color: .green)
                    } else if row.isSecondBest {
                        rankBadge("2nd", color: .blue)
                    }
                    if row.isSelected {
                        rankBadge("Selected", color: .accentColor)
                    }
                }
            }

            Spacer()

            Text("\(Int((row.score * 100).rounded()))%")
                .font(.system(.caption, design: .monospaced).weight(.semibold))
                .foregroundStyle(.secondary)
        }
    }

    private func rankBadge(_ title: String, color: Color) -> some View {
        Text(title)
            .font(.caption2.weight(.semibold))
            .foregroundStyle(color)
    }
}
