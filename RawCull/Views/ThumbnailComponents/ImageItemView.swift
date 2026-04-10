//
//  ImageItemView.swift
//  RawCull
//
//  Created by Thomas Evensen on 09/03/2026.
//

import OSLog
import SwiftUI

// MARK: - Sharpness Badge

struct SharpnessBadgeView: View {
    let score: Float
    let maxScore: Float

    /// 0–1, where 1 = sharpest image in the current set
    private var normalized: Float {
        guard maxScore > 0 else { return 0 }
        return min(score / maxScore, 1.0)
    }

    private var label: String {
        String(format: "%.0f", normalized * 100)
    }

    private var badgeColor: Color {
        switch normalized {
        case 0.65...: .green
        case 0.35...: .yellow
        default: .red
        }
    }

    var body: some View {
        Text(label)
            .font(.system(size: 9, weight: .semibold, design: .monospaced))
            .foregroundStyle(.white)
            .padding(.horizontal, 4)
            .padding(.vertical, 2)
            .background(badgeColor.opacity(0.80), in: RoundedRectangle(cornerRadius: 3))
    }
}

// MARK: - Saliency Badge

struct SaliencyBadgeView: View {
    let info: SaliencyInfo

    private var label: String {
        if let subject = info.subjectLabel {
            String(subject.prefix(10))
        } else {
            "subject"
        }
    }

    var body: some View {
        Text(label)
            .font(.system(size: 9, weight: .semibold, design: .monospaced))
            .foregroundStyle(.white)
            .padding(.horizontal, 4)
            .padding(.vertical, 2)
            .background(Color.cyan.opacity(0.80), in: RoundedRectangle(cornerRadius: 3))
    }
}

// MARK: - No-Subject Badge

struct NoSubjectBadgeView: View {
    var body: some View {
        Text("~")
            .font(.system(size: 9, weight: .semibold, design: .monospaced))
            .foregroundStyle(.white)
            .padding(.horizontal, 4)
            .padding(.vertical, 2)
            .background(Color.gray.opacity(0.70), in: RoundedRectangle(cornerRadius: 3))
    }
}

// MARK: - ImageItemView

struct ImageItemView: View {
    @Bindable var viewModel: RawCullViewModel
    private var settings: SettingsViewModel { SettingsViewModel.shared }

    let file: FileItem
    let selectedSource: ARWSourceCatalog?
    let isHovered: Bool
    let thumbnailSize: Int

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
                // Score + saliency badges — bottom-left corner, gated by settings toggles
                .overlay(alignment: .bottomLeading) {
                    let hasScore = settings.showScoringBadge && viewModel.sharpnessModel.scores[file.id] != nil
                    let hasSaliency = settings.showSaliencyBadge && viewModel.sharpnessModel.saliencyInfo[file.id] != nil
                    if hasScore || hasSaliency {
                        HStack(spacing: 3) {
                            if settings.showScoringBadge, let score = viewModel.sharpnessModel.scores[file.id] {
                                SharpnessBadgeView(
                                    score: score,
                                    maxScore: viewModel.sharpnessModel.maxScore,
                                )
                            }
                            if settings.showSaliencyBadge {
                                if let saliency = viewModel.sharpnessModel.saliencyInfo[file.id] {
                                    SaliencyBadgeView(info: saliency)
                                } else if hasScore {
                                    // Scored but Vision found no salient subject —
                                    // subject-weighting parameters had no effect on this photo.
                                    NoSubjectBadgeView()
                                }
                            }
                        }
                        .padding(5)
                    }
                }
                // Green tint ribbon at bottom when tagged
                .overlay(alignment: .bottom) {
                    if isTagged {
                        Rectangle()
                            .fill(Color.green.opacity(0.55))
                            .frame(height: 3)
                    }
                }
            }
            .frame(width: CGFloat(thumbnailSize), height: CGFloat(thumbnailSize))
            // Selected: accent glow border
            .overlay(
                RoundedRectangle(cornerRadius: 4)
                    .stroke(Color.accentColor, lineWidth: isSelected ? 3 : 0),
            )
            .shadow(
                color: isSelected ? Color.accentColor.opacity(0.65) : .clear,
                radius: isSelected ? 8 : 0,
            )
            .clipShape(RoundedRectangle(cornerRadius: 4))

            // Filename strip
            Text(file.name)
                .font(.system(size: 10, weight: .regular, design: .monospaced))
                .lineLimit(1)
                .truncationMode(.middle)
                .foregroundStyle(isSelected ? Color.accentColor : Color(white: 0.6))
                .padding(.horizontal, 5)
                .padding(.vertical, 4)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color(white: 0.1))

            // Rating color strip — 1=red 2=yellow 3=green 4=blue 5=purple
            if let color = ratingColor {
                color.frame(height: 4)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 4))
        .overlay(
            RoundedRectangle(cornerRadius: 4)
                .stroke(
                    isSelected ? Color.accentColor : Color(white: isHovered ? 0.35 : 0.18),
                    lineWidth: isSelected ? 2.5 : 1,
                ),
        )
        .shadow(color: .black.opacity(0.4), radius: 4, y: 2)
        .shadow(
            color: isSelected ? Color.accentColor.opacity(0.75) : .clear,
            radius: isSelected ? 12 : 0,
        )
        .scaleEffect(isHovered ? 1.02 : 1.0)
        .animation(.easeOut(duration: 0.15), value: isHovered)
        .contentShape(Rectangle())
        .onTapGesture(count: 2) { onDoubleSelect() }
        .onTapGesture(count: 1) { onSelect() }
    }

    private var isTagged: Bool {
        viewModel.taggedNamesCache.contains(file.name)
    }

    private var isSelected: Bool {
        viewModel.selectedFile?.id == file.id
    }

    private var ratingColor: Color? {
        switch viewModel.getRating(for: file) {
        case -1: .red
        case 2: .yellow
        case 3: .green
        case 4: .blue
        case 5: .purple
        default: nil
        }
    }
}
