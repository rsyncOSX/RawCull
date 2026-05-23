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

    private func ratingTitle(_ rating: Int) -> String {
        switch rating {
        case -1: "Rejected"
        case 0: "Picked"
        case 1...5: "\(rating) star"
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
