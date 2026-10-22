import RawCullCore
import SwiftUI

struct BurstImageStage: View {
    let selectedFile: FileItem?
    let imageState: ComparisonImageState?
    let focusPoints: [FocusPoint]?
    @Binding var viewportState: ComparisonViewportInteractionState
    @Binding var useThumbnailSource: Bool
    let rating: RatingDisplay
    let ratingValue: Int
    let metadataImage: NSImage?
    let rank: Int
    let frameCount: Int
    let sharpness: Float?
    let overallScore: Float?
    let showSubjectOutline: Bool
    let subjectOutlineFileID: FileItem.ID?
    let subjectOutline: CGImage?
    let isSuggested: Bool
    let subjectLabel: String?
    let canNavigatePrevious: Bool
    let canNavigateNext: Bool
    let navigate: (Int) -> Void
    let applyRating: (Int) -> Void
    let sourceChanged: () -> Void

    var body: some View {
        ZStack {
            Color.black.opacity(0.2)

            if let selectedFile {
                ComparisonImagePaneView(
                    file: selectedFile,
                    state: imageState,
                    focusPoints: focusPoints,
                    viewportState: $viewportState,
                    useThumbnailSource: $useThumbnailSource,
                    isSelected: true,
                    rating: rating,
                    exifSummary: ExifSummary.make(from: selectedFile.exifData),
                    saliencyLabel: nil,
                    burstAnalysis: nil,
                    burstCandidate: nil,
                    burstRating: ratingValue,
                    sharpnessContext: nil,
                    onSelect: {},
                    onRate: applyRating,
                    onSourceChange: sourceChanged,
                    showsChrome: false,
                    allowsDoubleClickZoom: false,
                    subjectOutline: showSubjectOutline && subjectOutlineFileID == selectedFile.id
                        ? subjectOutline : nil,
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(.horizontal, 82)
                .padding(.top, 36)
                .padding(.bottom, 2)
            } else {
                ContentUnavailableView("No burst frame", systemImage: "photo")
            }

            if let selectedFile {
                VStack(spacing: 0) {
                    BurstEvidenceShelf(
                        file: selectedFile,
                        image: metadataImage,
                        rating: rating,
                        rank: rank,
                        frameCount: frameCount,
                        sharpness: sharpness,
                        overallScore: overallScore,
                        exif: ExifSummary.make(from: selectedFile.exifData),
                    )
                    .padding(.top, 12)
                    Spacer()
                    BurstShortcutGuide()
                        .padding(.bottom, 12)
                }
                .padding(.horizontal, 116)
                .allowsHitTesting(true)
            }

            if let selectedFile {
                tagStrip(for: selectedFile)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                    .padding(18)
                    .allowsHitTesting(false)
            }

            HStack {
                navigationButton(systemImage: "chevron.left", delta: -1)
                Spacer()
                navigationButton(systemImage: "chevron.right", delta: 1)
            }
            .padding(.horizontal, 24)
        }
        .frame(minHeight: 420)
    }

    private func tagStrip(for file: FileItem) -> some View {
        HStack(spacing: 8) {
            if let image = imageState?.cgImage {
                ImagePixelDimensionsBadgeView(width: image.width, height: image.height)
            }

            WorkspaceTag(title: rating.label, color: rating.color)

            if isSuggested {
                WorkspaceTag(title: "Suggested", color: .orange)
            }

            if let subject = subjectLabel {
                WorkspaceTag(title: subject, color: .cyan)
            }
        }
    }

    private func navigationButton(systemImage: String, delta: Int) -> some View {
        Button {
            navigate(delta)
        } label: {
            Image(systemName: systemImage)
                .font(.title3.weight(.semibold))
                .frame(width: 36, height: 36)
        }
        .buttonStyle(.bordered)
        .buttonBorderShape(.circle)
        .disabled(delta < 0 ? !canNavigatePrevious : !canNavigateNext)
    }
}
