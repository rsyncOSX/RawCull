import AppKit
import SwiftUI

struct ZoomImageCanvas: View {
    let cgImage: CGImage?
    let nsImage: NSImage?
    let nativeImageSize: CGSize?
    let focusMask: CGImage?
    let subjectOutline: CGImage?
    let clippingOverlay: CGImage?
    let showsSubjectOutline: Bool
    let focusTarget: CGPoint?
    @Binding var viewport: ComparisonViewportInteractionState
    let imageReady: (CGSize, CGSize) -> Void
    let resetToFit: () -> Void
    let zoomToTarget: () -> Void

    private var imageSize: CGSize? {
        if let cgImage {
            return CGSize(width: cgImage.width, height: cgImage.height)
        }
        return nsImage?.size
    }

    private var image: Image? {
        if let cgImage {
            return Image(decorative: cgImage, scale: 1, orientation: .up)
        }
        return nsImage.map(Image.init(nsImage:))
    }

    private var imageIdentity: ObjectIdentifier? {
        if let cgImage {
            return ObjectIdentifier(cgImage)
        }
        return nsImage.map(ObjectIdentifier.init)
    }

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                if let image, let imageSize {
                    ZStack {
                        image.resizable().scaledToFit()
                            .frame(width: geometry.size.width, height: geometry.size.height)
                        if cgImage != nil, let clippingOverlay {
                            Image(decorative: clippingOverlay, scale: 1, orientation: .up)
                                .resizable().scaledToFit()
                                .frame(width: geometry.size.width, height: geometry.size.height)
                                .allowsHitTesting(false)
                        }
                        if viewport.showFocusMask, let focusMask {
                            ImageReviewRasterOverlay(
                                image: Image(decorative: focusMask, scale: 1, orientation: .up),
                                size: geometry.size,
                            )
                            .transition(.opacity)
                        }
                        if showsSubjectOutline, let subjectOutline {
                            ImageReviewRasterOverlay(
                                image: Image(decorative: subjectOutline, scale: 1, orientation: .up),
                                size: geometry.size, kind: .subjectOutline,
                            )
                            .transition(.opacity)
                        }
                    }
                    .scaleEffect(viewport.scale)
                    .offset(viewport.offset)
                    .gesture(zoomPanGesture)
                    .onAppear { imageReady(nativeImageSize ?? imageSize, geometry.size) }
                    .onChange(of: imageIdentity) { _, _ in imageReady(nativeImageSize ?? imageSize, geometry.size) }
                    .onTapGesture(count: 2) {
                        withAnimation(.spring()) { viewport.scale > 1 ? resetToFit() : zoomToTarget() }
                    }
                } else {
                    HStack {
                        ProgressView().fixedSize()
                        Text("Extracting image…").font(.title)
                    }
                    .padding()
                    .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.gray.opacity(0.3), lineWidth: 1))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
                if viewport.showFocusPoints, let focusTarget {
                    FocusPointMarker(
                        normalizedX: focusTarget.x, normalizedY: focusTarget.y,
                        boxSize: 16, imageSize: imageSize,
                    )
                    .stroke(.red, style: StrokeStyle(lineWidth: 2.5, lineCap: .round))
                    .shadow(color: .black.opacity(0.8), radius: 2, x: 0, y: 0)
                    .scaleEffect(viewport.scale)
                    .offset(viewport.offset)
                    .allowsHitTesting(false)
                    .transition(.opacity.combined(with: .blurReplace))
                }
            }
        }
    }

    private var zoomPanGesture: some Gesture {
        SimultaneousGesture(
            MagnificationGesture()
                .onChanged { viewport.scale = viewport.lastScale * $0 }
                .onEnded { _ in
                    viewport.lastScale = viewport.scale
                    if viewport.scale < 1 {
                        withAnimation(.spring()) { resetToFit() }
                    }
                },
            DragGesture()
                .onChanged { value in
                    if viewport.scale > 1 {
                        viewport.offset = CGSize(
                            width: viewport.lastOffset.width + value.translation.width,
                            height: viewport.lastOffset.height + value.translation.height,
                        )
                    }
                }
                .onEnded { _ in viewport.lastOffset = viewport.offset },
        )
    }
}
