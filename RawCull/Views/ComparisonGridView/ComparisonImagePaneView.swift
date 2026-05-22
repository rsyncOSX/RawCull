import SwiftUI

struct ComparisonImagePaneView: View {
    let file: FileItem
    let state: ComparisonImageState?
    let focusPoints: [FocusPoint]?
    let scale: CGFloat
    let offset: CGSize
    let showFocusMask: Bool
    let showFocusPoints: Bool
    let markerSize: CGFloat
    let isSelected: Bool
    let rating: RatingDisplay
    let burstAnalysis: BurstAnalysisResult?
    let burstCandidate: BurstCandidateScore?
    let burstRating: Int
    let zoomPanGesture: AnyGesture<Void>
    let onSelect: () -> Void
    let onToggleZoom: () -> Void

    var body: some View {
        GeometryReader { geo in
            ZStack {
                Color.black

                if let state {
                    imageContent(state, in: geo.size)
                } else {
                    ProgressView()
                        .fixedSize()
                }

                VStack {
                    VStack(alignment: .leading, spacing: 6) {
                        HStack(alignment: .top) {
                            if let burstAnalysis, let burstCandidate {
                                BurstCandidateBadgeView(
                                    candidate: burstCandidate,
                                    analysis: burstAnalysis,
                                    rating: burstRating,
                                )
                            }
                            Spacer()
                            CurrentRatingBadgeView(rating: rating)
                        }

                        VStack(alignment: .leading, spacing: 2) {
                            Text(file.name)
                                .font(.headline)
                                .lineLimit(1)
                            Text(file.url.deletingLastPathComponent().path())
                                .font(.caption)
                                .lineLimit(1)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(.regularMaterial)
                    .clipShape(.rect(cornerRadius: 8))
                    .padding(8)

                    Spacer()
                }
            }
            .clipShape(.rect(cornerRadius: 8))
            .contentShape(Rectangle())
            .gesture(zoomPanGesture)
            .onTapGesture(count: 1, perform: onSelect)
            .onTapGesture(count: 2, perform: onToggleZoom)
        }
        .background(Color(nsColor: .textBackgroundColor))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color.accentColor, lineWidth: isSelected ? 3 : 0),
        )
        .shadow(
            color: isSelected ? Color.accentColor.opacity(0.55) : .clear,
            radius: isSelected ? 10 : 0,
        )
        .clipShape(.rect(cornerRadius: 8))
    }

    @ViewBuilder
    private func imageContent(_ state: ComparisonImageState, in size: CGSize) -> some View {
        if let cgImage = state.cgImage {
            ZStack {
                Image(decorative: cgImage, scale: 1.0, orientation: .up)
                    .resizable()
                    .scaledToFit()
                    .frame(width: size.width, height: size.height)

                if showFocusMask, let focusMask = state.focusMask {
                    Image(decorative: focusMask, scale: 1.0, orientation: .up)
                        .resizable()
                        .scaledToFit()
                        .frame(width: size.width, height: size.height)
                        .blendMode(.screen)
                        .opacity(0.95)
                        .transition(.opacity)
                }

                focusPointOverlay(imageSize: CGSize(width: cgImage.width, height: cgImage.height))
            }
            .scaleEffect(scale)
            .offset(offset)
        } else if let nsImage = state.nsImage {
            ZStack {
                Image(nsImage: nsImage)
                    .resizable()
                    .scaledToFit()
                    .frame(width: size.width, height: size.height)

                focusPointOverlay(imageSize: nsImage.size)
            }
            .scaleEffect(scale)
            .offset(offset)
        } else {
            VStack(spacing: 8) {
                if state.isLoading {
                    ProgressView()
                        .fixedSize()
                    Text("Extracting image...")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    Image(systemName: "photo")
                        .font(.largeTitle)
                        .foregroundStyle(.secondary)
                    Text("No preview available")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    @ViewBuilder
    private func focusPointOverlay(imageSize: CGSize) -> some View {
        if showFocusPoints, let focusPoints {
            FocusOverlayView(
                focusPoints: focusPoints,
                imageSize: imageSize,
                markerSize: markerSize,
            )
            .allowsHitTesting(false)
            .transition(.opacity.combined(with: .blurReplace))
        }
    }
}
