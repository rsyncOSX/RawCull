import SwiftUI

struct LoupeImageStage<Controls: View, Metadata: View>: View {
    let session: LoupeSessionModel
    let url: URL
    let thumbnailSizePreview: Int
    let size: CGSize
    @Binding var scale: CGFloat
    @Binding var lastScale: CGFloat
    @Binding var offset: CGSize
    @Binding var lastOffset: CGSize
    let showsFocusMask: Bool
    let focusMask: NSImage?
    let showsSubjectOutline: Bool
    let subjectOutlineImage: CGImage?
    let showFocusPoints: Bool
    let focusPoints: [FocusPoint]?
    let currentImageSize: CGSize?
    let sourceFailure: ImageReviewSourceFailure?
    @ViewBuilder let controls: () -> Controls
    @ViewBuilder let metadata: () -> Metadata

    var body: some View {
        ZStack {
            // 1️⃣ Image FIRST (background)
            LoupeImageContent(session: session, url: url, thumbnailSizePreview: thumbnailSizePreview)
                .scaleEffect(scale)
                .offset(offset)
                .frame(width: size.width, height: size.height, alignment: .center)
                .gesture(
                    MagnifyGesture()
                        .onChanged { value in
                            scale = lastScale * value.magnification
                        }
                        .onEnded { _ in
                            lastScale = scale
                        },
                )

                .simultaneousGesture(
                    DragGesture()
                        .onChanged { value in
                            if scale > 1.0 {
                                offset = CGSize(
                                    width: lastOffset.width + value.translation.width,
                                    height: lastOffset.height + value.translation.height,
                                )
                            }
                        }
                        .onEnded { _ in
                            lastOffset = offset
                        },
                )

            // 2️⃣ Focus mask overlay

            if showsFocusMask, let mask = focusMask {
                ImageReviewRasterOverlay(image: Image(nsImage: mask), size: size, kind: .focusMap)
                    .scaleEffect(scale)
                    .offset(offset)
                    .transition(.opacity)
            }

            if showsSubjectOutline, let subjectOutline = subjectOutlineImage {
                ImageReviewRasterOverlay(
                    image: Image(decorative: subjectOutline, scale: 1, orientation: .up), size: size, kind: .subjectOutline,
                )
                .scaleEffect(scale)
                .offset(offset)
                .transition(.opacity)
            }

            // 3️⃣ Focus points overlay
            if showFocusPoints, let focusPoints {
                FocusOverlayView(
                    focusPoints: focusPoints,
                    imageSize: currentImageSize,
                )
                .scaleEffect(scale)
                .offset(offset)
                .allowsHitTesting(false)
                .transition(.opacity.combined(with: .blurReplace))
            }

            VStack {
                Spacer()

                controls()
                    .padding(.bottom, 12)
            }

            metadata()

            if let failure = sourceFailure {
                Text(failure.message)
                    .font(.title2.weight(.semibold))
                    .padding(.horizontal, 18)
                    .padding(.vertical, 10)
                    .background(.regularMaterial, in: Capsule())
                    .transition(.opacity)
            }
        }
    }
}
