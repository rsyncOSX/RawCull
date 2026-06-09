//
//  ScanStatsSheetView.swift
//  RawCull
//
//  Created by Thomas Evensen on 04/04/2026.
//

import SwiftUI

struct ScanStatsSheetView: View {
    @Environment(\.dismiss) private var dismiss

    let viewModel: RawCullViewModel

    var body: some View {
        VStack(spacing: 0) {
            // Title bar
            HStack {
                Label("Scan Summary", systemImage: "chart.bar.doc.horizontal")
                    .font(.title3.bold())
                Spacer()
                Button("Done") { dismiss() }
                    .keyboardShortcut(.return)
                    .buttonStyle(.borderedProminent)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 14)

            Divider()

            ScrollView {
                summaryContent
                    .padding(20)
            }
        }
        .frame(width: 800)
        .fixedSize(horizontal: false, vertical: true)
    }

    // MARK: Summary layout

    private var summaryContent: some View {
        HStack(alignment: .top, spacing: 28) {
            VStack(alignment: .leading, spacing: 14) {
                cullingStatusSection
                Divider()
                catalogSummarySection
                Divider()
                sharpnessSummarySection
                if !viewModel.burstAnalysisResults.isEmpty {
                    Divider()
                    burstReviewSummarySection
                }
            }
            .frame(width: 260, alignment: .topLeading)

            burstLabelGuideSection
                .frame(maxWidth: .infinity, alignment: .topLeading)
        }
    }

    private var cullingStatusSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Culling Status")
                .font(.headline)

            let s = cullingStats
            let total = s.total

            Grid(alignment: .leadingFirstTextBaseline, horizontalSpacing: 18, verticalSpacing: 7) {
                GridRow {
                    Text("Status")
                        .gridColumnAlignment(.leading)
                    Text("Count")
                        .gridColumnAlignment(.trailing)
                    Text("%")
                        .gridColumnAlignment(.trailing)
                }
                .font(.caption)
                .foregroundStyle(.secondary)

                Divider().gridCellUnsizedAxes(.horizontal)

                statRow("✕  Rejected", color: .red, count: s.rejected, total: total)
                statRow("P  Kept", color: .accentColor, count: s.kept, total: total)
                statRow("★2", color: .yellow, count: s.r2, total: total)
                statRow("★3", color: .green, count: s.r3, total: total)
                statRow("★4", color: .blue, count: s.r4, total: total)
                statRow("★5", color: .purple, count: s.r5, total: total)
                statRow("—  Unrated", color: .secondary, count: s.unrated, total: total)

                Divider().gridCellUnsizedAxes(.horizontal)

                GridRow {
                    Text("Total")
                        .fontWeight(.semibold)
                        .gridColumnAlignment(.leading)
                    Text("\(total)")
                        .fontWeight(.semibold)
                        .monospacedDigit()
                        .gridColumnAlignment(.trailing)
                    Text("100%")
                        .fontWeight(.semibold)
                        .monospacedDigit()
                        .gridColumnAlignment(.trailing)
                        .opacity(total > 0 ? 1 : 0)
                }
            }
            .font(.body.monospacedDigit())

            let allPicked = s.kept + s.r2 + s.r3 + s.r4 + s.r5
            if allPicked > 0 {
                let needRating = s.kept
                Text(needRating == 0
                    ? "All \(allPicked) picked images have a star rating"
                    : "\(needRating) of \(allPicked) picked images still need a star rating")
                    .font(.caption)
                    .foregroundStyle(needRating == 0 ? Color.secondary : Color.orange)
            }
        }
    }

    private var burstLabelGuideSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Burst Label Guide")
                .font(.headline)

            Grid(alignment: .leadingFirstTextBaseline, horizontalSpacing: 10, verticalSpacing: 5) {
                ForEach(burstLabelGuideRows, id: \.label) { row in
                    guideRow(row.label, row.description)
                }
            }
            .font(.caption)
        }
    }

    // MARK: Minor summaries

    private var catalogSummarySection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Catalog")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)

            Grid(alignment: .leadingFirstTextBaseline, horizontalSpacing: 12, verticalSpacing: 4) {
                if let catalog = viewModel.selectedSource {
                    minorInfoRow("Name", catalog.name)
                }
                minorInfoRow("Files scanned", "\(viewModel.files.count) RAW")
                minorInfoRow("Total size", totalSize)
                if let range = dateRange {
                    minorInfoRow("Date range", range)
                }
                if let cameras = uniqueCameras {
                    minorInfoRow("Camera", cameras)
                }
                if let lenses = uniqueLenses {
                    minorInfoRow("Lens", lenses)
                }
            }
            .font(.caption)
        }
    }

    private var sharpnessSummarySection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Sharpness Scoring")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)

            Grid(alignment: .leadingFirstTextBaseline, horizontalSpacing: 12, verticalSpacing: 4) {
                let scores = Array(viewModel.sharpnessModel.scores.values)
                if scores.isEmpty {
                    minorInfoRow("Status", "Not scored")
                    minorInfoRow("Scored", "0 of \(viewModel.files.count)")
                } else {
                    let scored = scores.count
                    let total = viewModel.files.count
                    let mean = scores.reduce(0, +) / Float(scores.count)
                    let minScore = scores.min() ?? 0
                    let maxScore = scores.max() ?? 0

                    minorInfoRow("Scored", "\(scored) of \(total)")
                    minorInfoRow("Mean score", String(format: "%.1f", mean))
                    minorInfoRow("Range", String(format: "%.1f – %.1f", minScore, maxScore))
                }
            }
            .font(.caption)
        }
    }

    private var burstReviewSummarySection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Burst Review")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)

            Grid(alignment: .leadingFirstTextBaseline, horizontalSpacing: 12, verticalSpacing: 4) {
                let counts = viewModel.burstReviewQueueCounts
                minorInfoRow("Total groups", "\(viewModel.similarityModel.burstGroups.count)")
                minorInfoRow("Needs review", "\(counts.needsReview)")
                minorInfoRow("Deferred", "\(counts.deferred)")
                minorInfoRow("Reviewed", "\(counts.reviewed)")
            }
            .font(.caption)
        }
    }

    // MARK: Grid row builder

    private func statRow(_ label: String, color: Color, count: Int, total: Int) -> some View {
        GridRow {
            Text(label)
                .foregroundStyle(color)
                .gridColumnAlignment(.leading)
            Text("\(count)")
                .monospacedDigit()
                .gridColumnAlignment(.trailing)
            Text(total > 0 ? String(format: "%d%%", Int((Double(count) / Double(total) * 100).rounded())) : "—")
                .monospacedDigit()
                .foregroundStyle(count == 0 ? Color.secondary.opacity(0.5) : Color.secondary)
                .gridColumnAlignment(.trailing)
        }
    }

    private func minorInfoRow(_ label: String, _ value: String) -> some View {
        GridRow {
            Text(label)
                .foregroundStyle(.secondary)
                .gridColumnAlignment(.leading)
            Text(value)
                .lineLimit(1)
                .truncationMode(.middle)
                .gridColumnAlignment(.leading)
        }
    }

    private func guideRow(_ label: String, _ description: String) -> some View {
        GridRow {
            Text(label)
                .fontWeight(.semibold)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: false)
                .gridColumnAlignment(.leading)
            Text(description)
                .foregroundStyle(.primary)
                .fixedSize(horizontal: false, vertical: true)
                .gridColumnAlignment(.leading)
        }
    }

    // MARK: Computed properties

    private var burstLabelGuideRows: [(label: String, description: String)] {
        [
            // ("Burst N", "The numbered burst group currently open for review."),
            ("High confidence", "RawCull found a clear best frame and one-click culling is safe."),
            ("Review recommended", "RawCull suggests a frame, but the group should be inspected."),
            ("Low confidence", "RawCull cannot choose safely; manual review is needed."),
            ("Evidence", "Reasons RawCull favors the suggested frame."),
            ("Caution", "Signals that make the recommendation less certain."),
            ("Needs Review", "The group is in the active review queue."),
            ("Reviewed", "You marked the group as checked."),
            ("Deferred", "You postponed the group for later."),
            ("Manual winner", "Your selected winner overrides the automatic pick."),
            ("Applied", "A burst culling action has already been applied."),
            ("Best / Suggested / Check frame", "Recommendation badges for automatic picks."),
            ("Manual / Auto best", "Manual choice and original automatic best badges."),
            ("Keeper / Top 2 / Rejected", "Culling outcomes applied to burst frames."),
            ("Subject labels", "Saliency hints such as person when a subject is classified.")
        ]
    }

    private var cullingStats: (rejected: Int, kept: Int, r2: Int, r3: Int, r4: Int, r5: Int, unrated: Int, total: Int) {
        guard let catalog = viewModel.selectedSource?.url else {
            let n = viewModel.filteredFiles.count
            return (0, 0, 0, 0, 0, 0, n, n)
        }
        var rejected = 0, kept = 0, r2 = 0, r3 = 0, r4 = 0, r5 = 0, unrated = 0
        for file in viewModel.filteredFiles {
            if !viewModel.cullingModel.isUnrated(photo: file.name, in: catalog) {
                unrated += 1
            } else {
                switch viewModel.getRating(for: file) {
                case -1: rejected += 1
                case 0: kept += 1
                case 2: r2 += 1
                case 3: r3 += 1
                case 4: r4 += 1
                case 5: r5 += 1
                default: unrated += 1
                }
            }
        }
        return (rejected, kept, r2, r3, r4, r5, unrated, viewModel.filteredFiles.count)
    }

    private var totalSize: String {
        let bytes = viewModel.files.reduce(Int64(0)) { $0 + $1.size }
        return ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }

    private var dateRange: String? {
        let dates = viewModel.files.map(\.dateModified)
        guard let first = dates.min(), let last = dates.max() else { return nil }
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        if Calendar.current.isDate(first, inSameDayAs: last) {
            return formatter.string(from: first)
        }
        return "\(formatter.string(from: first)) – \(formatter.string(from: last))"
    }

    private var uniqueCameras: String? {
        let names = Set(viewModel.files.compactMap(\.exifData?.camera))
        guard !names.isEmpty else { return nil }
        return names.sorted().joined(separator: ", ")
    }

    private var uniqueLenses: String? {
        let names = Set(viewModel.files.compactMap(\.exifData?.lensModel))
        guard !names.isEmpty else { return nil }
        return names.sorted().joined(separator: ", ")
    }
}
