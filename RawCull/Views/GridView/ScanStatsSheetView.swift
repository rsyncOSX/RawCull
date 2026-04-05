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

            Form {
                // MARK: Catalog

                Section("Catalog") {
                    if let catalog = viewModel.selectedSource {
                        LabeledContent("Name", value: catalog.name)
                    }
                    LabeledContent("Files scanned", value: "\(viewModel.files.count) ARW")
                    LabeledContent("Total size", value: totalSize)
                    if let range = dateRange {
                        LabeledContent("Date range", value: range)
                    }
                    if let cameras = uniqueCameras {
                        LabeledContent("Camera", value: cameras)
                    }
                    if let lenses = uniqueLenses {
                        LabeledContent("Lens", value: lenses)
                    }
                }

                // MARK: Culling

                Section("Culling Status") {
                    let s = cullingStats
                    let total = s.total

                    Grid(alignment: .leadingFirstTextBaseline, horizontalSpacing: 14, verticalSpacing: 5) {
                        // Header
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
                    .font(.callout.monospacedDigit())
                    .padding(.vertical, 4)

                    // Picked-but-unrated nudge
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

                // MARK: Sharpness

                if !viewModel.sharpnessModel.scores.isEmpty {
                    Section("Sharpness Scoring") {
                        let scores = Array(viewModel.sharpnessModel.scores.values)
                        let scored = scores.count
                        let total = viewModel.files.count
                        let mean = scores.reduce(0, +) / Float(scores.count)
                        let minScore = scores.min() ?? 0
                        let maxScore = scores.max() ?? 0

                        LabeledContent("Scored", value: "\(scored) of \(total)")
                        LabeledContent("Mean score", value: String(format: "%.1f", mean))
                        LabeledContent("Range", value: String(format: "%.1f – %.1f", minScore, maxScore))
                    }
                }
            }
            .formStyle(.grouped)
        }
        .frame(width: 440)
        .fixedSize(horizontal: false, vertical: true)
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

    // MARK: Computed properties

    private var cullingStats: (rejected: Int, kept: Int, r2: Int, r3: Int, r4: Int, r5: Int, unrated: Int, total: Int) {
        guard let catalog = viewModel.selectedSource?.url else {
            let n = viewModel.filteredFiles.count
            return (0, 0, 0, 0, 0, 0, n, n)
        }
        var rejected = 0, kept = 0, r2 = 0, r3 = 0, r4 = 0, r5 = 0, unrated = 0
        for file in viewModel.filteredFiles {
            if !viewModel.cullingModel.isTagged(photo: file.name, in: catalog) {
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
