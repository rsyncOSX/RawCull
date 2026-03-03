import SwiftUI

struct CachedThumbnailView: View {
    @Environment(RawCullViewModel.self) private var viewModel

    /// Replace the let focusPoints property with a computed one:
    private var focusPoints: [FocusPoint]? {
        viewModel.getFocusPoints()
    }

    @Binding var scale: CGFloat
    @Binding var lastScale: CGFloat
    @Binding var offset: CGSize

    let url: URL

    @State private var image: NSImage?
    @State private var isLoading = false

    @State private var showFocusPoints = false
    @State private var markerSize: CGFloat = 40

    var body: some View {
        ZStack {
            if let image {
                VStack {
                    // Image display with zoom
                    GeometryReader { geo in
                        ZStack {
                            // 1️⃣ Image FIRST (background)
                            Image(nsImage: image)
                                .resizable()
                                .aspectRatio(contentMode: .fit)
                                .scaleEffect(scale)
                                .offset(offset)
                                .frame(width: geo.size.width, height: geo.size.height, alignment: .center)
                                .gesture(
                                    MagnificationGesture()
                                        .onChanged { value in
                                            scale = lastScale * value
                                        }
                                        .onEnded { _ in
                                            lastScale = scale
                                        }
                                )
                                .simultaneousGesture(
                                    DragGesture()
                                        .onChanged { value in
                                            if scale > 1.0 {
                                                offset = CGSize(
                                                    width: value.translation.width,
                                                    height: value.translation.height
                                                )
                                            }
                                        }
                                        .onEnded { _ in
                                            // Gesture ended
                                        }
                                )

                            // 2️⃣ Focus overlay SECOND (on top of image)
                            if showFocusPoints, let focusPoints {
                                FocusOverlayView(
                                    focusPoints: focusPoints,
                                    markerSize: markerSize
                                )
                                .scaleEffect(scale)
                                .offset(offset)
                                .allowsHitTesting(false)
                                .transition(.opacity.combined(with: .blurReplace))
                            }

                            VStack {
                                Spacer()
                                focuspointcontroller
                            }
                        }
                    }
                }
                .shadow(radius: 4)
                .background(Color(nsColor: .textBackgroundColor))
                .cornerRadius(8)
            } else if isLoading {
                ProgressView()
                    .fixedSize()
            } else {
                ContentUnavailableView("Select an Image", systemImage: "photo")
            }
        }
        .task(id: url) {
            isLoading = true
            let settingsmanager = await SettingsViewModel.shared.asyncgetsettings()
            let thumbnailSizePreview = settingsmanager.thumbnailSizePreview
            let cgImage = await RequestThumbnail().requestThumbnail(
                for: url,
                targetSize: thumbnailSizePreview
            )
            if let cgImage {
                image = NSImage(cgImage: cgImage, size: .zero)
            } else {
                image = nil
            }
            isLoading = false
        }
    }

    private var focuspointcontroller: some View {
        HStack(spacing: 12) {
            // Marker size slider (visible only when focus points are shown)
            if showFocusPoints {
                HStack(spacing: 6) {
                    Image(systemName: "viewfinder")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Slider(value: $markerSize, in: 32 ... 120, step: 4)
                        .frame(width: 100)
                        .controlSize(.small)
                    Image(systemName: "viewfinder")
                        .font(.body)
                        .foregroundStyle(.secondary)
                }
                .transition(.move(edge: .trailing).combined(with: .opacity))
            }

            // Toggle button — always white so it's visible on black background
            Button {
                withAnimation(.easeInOut(duration: 0.2)) {
                    showFocusPoints.toggle()
                }
            } label: {
                Image(systemName: showFocusPoints
                    ? "viewfinder.circle.fill"
                    : "viewfinder.circle")
                    .font(.title3)
                    .foregroundStyle(showFocusPoints ? .yellow : .white) // ← was .primary (black on black!)
                    .symbolEffect(.bounce, value: showFocusPoints)
            }
            .buttonStyle(.plain)
            .help(showFocusPoints ? "Hide focus points" : "Show focus points")
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 9)
        .background(.white.opacity(0.15), in: Capsule()) // ← was .ultraThinMaterial (invisible on black)
        .padding(10)
        .animation(.spring(duration: 0.3), value: showFocusPoints)
    }
}
