//
//  ImageItemView.swift
//  RawCull
//
//  Created by Thomas Evensen on 09/03/2026.
//

import OSLog
import RawCullCore
import SwiftUI

enum SharpnessLabel {
    case sharp
    case good
    case check
    case soft

    nonisolated init(score: Float, maxScore: Float) {
        guard maxScore > 0, score.isFinite, maxScore.isFinite else {
            self = .soft
            return
        }

        let normalized = min(max(score / maxScore, 0), 1)
        switch normalized {
        case 0.85...:
            self = .sharp

        case 0.65...:
            self = .good

        case 0.35...:
            self = .check

        default:
            self = .soft
        }
    }
}

// MARK: - Burst Candidate Badge

struct BurstCandidateBadgeView: View {
    let candidate: BurstCandidateScore
    let analysis: BurstAnalysisResult
    let rating: Int
    var saliencyLabel: String?
    var isCompact = false

    var body: some View {
        Group {
            if isCompact {
                HStack(spacing: 3) {
                    if let recommendationTitle {
                        rankBadge(recommendationTitle)
                    }
                    statusBadges
                }
            } else {
                VStack(alignment: .leading, spacing: 3) {
                    if let recommendationTitle {
                        rankBadge(recommendationTitle)
                    }
                    statusBadges
                }
            }
        }
        .help("Burst score \(Int(candidate.overallScore * 100))")
    }

    private func rankBadge(_ title: String) -> some View {
        Text(title)
            .font(.system(size: 9, weight: .bold, design: .monospaced))
            .foregroundStyle(.white)
            .padding(.horizontal, 4)
            .padding(.vertical, 2)
            .background(rankColor.opacity(0.85), in: RoundedRectangle(cornerRadius: 3))
    }

    @ViewBuilder
    private var statusBadges: some View {
        if rating == -1 {
            statusBadge("Rejected", color: .red)
        } else if rating == 3 {
            statusBadge("Keeper", color: .green)
        } else if rating == 2 {
            statusBadge("Top 2", color: .green)
        }

        if let saliencyLabel, !saliencyLabel.isEmpty {
            statusBadge(saliencyLabel, color: .cyan)
        }
    }

    private func statusBadge(_ title: String, color: Color) -> some View {
        Text(title)
            .font(.system(size: 9, weight: .semibold, design: .monospaced))
            .foregroundStyle(.white)
            .padding(.horizontal, 4)
            .padding(.vertical, 2)
            .background(color.opacity(0.85), in: RoundedRectangle(cornerRadius: 3))
    }

    private var recommendationTitle: String? {
        if analysis.reviewState == .manualWinnerOverride,
           analysis.recommendedFileID == candidate.fileID {
            return "Manual"
        }
        if analysis.reviewState == .manualWinnerOverride,
           analysis.candidates.first?.fileID == candidate.fileID {
            return "Auto best"
        }
        if analysis.recommendedFileID == candidate.fileID {
            return BurstGroupPresentation.recommendationBadge(for: candidate, in: analysis)
        }
        return nil
    }

    private var rankColor: Color {
        if analysis.reviewState == .manualWinnerOverride,
           analysis.recommendedFileID == candidate.fileID {
            return .orange
        }
        if analysis.reviewState == .manualWinnerOverride,
           analysis.candidates.first?.fileID == candidate.fileID {
            return .green
        }
        if analysis.recommendedFileID == candidate.fileID {
            switch analysis.confidence {
            case .high: return .green
            case .medium: return .orange
            case .low: return .gray
            }
        }
        if analysis.secondBestFileID == candidate.fileID {
            return .blue
        }
        return .black
    }
}

// MARK: - ImageItemView

struct ImageItemView: View {
    @Bindable var viewModel: RawCullViewModel

    let file: FileItem
    let isHovered: Bool
    let isSelected: Bool
    var isMultiSelected: Bool = false
    let thumbnailSize: Int
    let ratingValue: Int
    let ratingDisplay: RatingDisplay
    let ratingColor: Color?
    var onSelect: () -> Void = {}
    var onDoubleSelect: () -> Void = {}

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Thumbnail area
            ZStack {
                ThumbnailImageView(
                    file: file,
                    targetSize: thumbnailSize,
                    style: .grid,
                    showsShimmer: true,
                )
                .frame(width: CGFloat(thumbnailSize), height: CGFloat(thumbnailSize))
                .clipped()
                // Selection badge — top-right corner
                .overlay(alignment: .topTrailing) {
                    if isSelected || isMultiSelected {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: isSelected ? 17 : 15, weight: .bold))
                            .foregroundStyle(.white, selectionColor)
                            .padding(5)
                    }
                }
                // Rating and burst recommendation badges — top-left corner
                .overlay(alignment: .topLeading) {
                    VStack(alignment: .leading, spacing: 4) {
                        CurrentRatingBadgeView(
                            rating: ratingDisplay,
                            density: .compact,
                        )

                        if let groupID = viewModel.similarityModel.burstGroupLookup[file.id],
                           let analysis = viewModel.burstAnalysisResult(for: groupID),
                           let candidate = viewModel.burstCandidate(for: file) {
                            BurstCandidateBadgeView(
                                candidate: candidate,
                                analysis: analysis,
                                rating: ratingValue,
                                saliencyLabel: viewModel.sharpnessModel.saliencyInfo[file.id]?.subjectLabel,
                            )
                        }
                    }
                    .padding(5)
                }
            }
            .frame(width: CGFloat(thumbnailSize), height: CGFloat(thumbnailSize))
            // Selected: strong accent frame inside the image bounds
            .overlay(
                RoundedRectangle(cornerRadius: 4)
                    .stroke(selectionColor, lineWidth: isSelectionHighlighted ? imageSelectionLineWidth : 0),
            )
            .clipShape(RoundedRectangle(cornerRadius: 4))

            // Filename strip
            Text(file.name)
                .font(.system(size: 10, weight: .regular, design: .monospaced))
                .lineLimit(1)
                .truncationMode(.middle)
                .foregroundStyle(isSelectionHighlighted ? Color.white : Color(white: 0.6))
                .padding(.horizontal, 5)
                .padding(.vertical, 4)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(isSelectionHighlighted ? selectionColor.opacity(isSelected ? 0.75 : 0.55) : Color(white: 0.1))

            // Rating color strip — 1=red 2=yellow 3=green 4=blue 5=purple
            if let color = ratingColor {
                color.frame(height: 4)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 4))
        .overlay(
            RoundedRectangle(cornerRadius: 4)
                .stroke(borderColor, lineWidth: borderWidth),
        )
        .background(
            RoundedRectangle(cornerRadius: 4)
                .fill(isSelectionHighlighted ? selectionColor.opacity(isSelected ? 0.16 : 0.12) : Color.clear),
        )
        .shadow(color: .black.opacity(isSelectionHighlighted ? 0.18 : 0.28), radius: isSelectionHighlighted ? 1 : 3, y: 1)
        .scaleEffect(isHovered ? 1.02 : 1.0)
        .animation(.easeOut(duration: 0.15), value: isHovered)
        .contentShape(Rectangle())
        .onTapGesture(count: 2) { onDoubleSelect() }
        .onTapGesture(count: 1) { onSelect() }
    }

    private var borderColor: Color {
        if isSelected { return Color.accentColor }
        if isMultiSelected { return Color.teal }
        return Color(white: isHovered ? 0.35 : 0.18)
    }

    private var borderWidth: CGFloat {
        if isSelected { return 3.5 }
        if isMultiSelected { return 3.0 }
        return 1
    }

    private var imageSelectionLineWidth: CGFloat {
        isSelected ? 4 : 3
    }

    private var isSelectionHighlighted: Bool {
        isSelected || isMultiSelected
    }

    private var selectionColor: Color {
        isSelected ? Color.accentColor : Color.teal
    }
}
