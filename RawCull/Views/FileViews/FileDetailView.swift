import SwiftUI

struct FileDetailView: View {
    @Environment(\.openWindow) var openWindow
    @Bindable var viewModel: RawCullViewModel

    @Binding var cgImage: CGImage?
    @Binding var nsImage: NSImage?
    @Binding var selectedFileID: UUID?
    @Binding var scale: CGFloat
    @Binding var lastScale: CGFloat
    @Binding var offset: CGSize

    let file: FileItem?

    var body: some View {
        if viewModel.showDetailsTagView, let url = file?.url {
            DeepDiveTagsView(
                url: url,
            )
        } else {
            if let file {
                VStack(spacing: 20) {
                    MainCachedThumbnailView(
                        scale: $scale,
                        lastScale: $lastScale,
                        offset: $offset,
                        url: file.url,
                    )

                    HStack {
                        VStack {
                            HStack {
                                Button(action: {
                                    withAnimation(.spring()) {
                                        viewModel.scale = max(0.5, viewModel.scale - 0.2)
                                    }
                                }, label: {
                                    Image(systemName: "minus")
                                        .font(.system(size: 12))
                                })
                                .disabled(viewModel.scale <= 0.5)
                                .help("Zoom out")

                                Button(action: {
                                    withAnimation(.spring()) {
                                        viewModel.resetZoom()
                                    }
                                }, label: {
                                    Text("Reset \(viewModel.scale * 100, format: .number.precision(.fractionLength(0)))%")
                                        .font(.caption)
                                })
                                .disabled(viewModel.scale == 1.0 && viewModel.offset == .zero)
                                .help("Reset zoom")

                                Button(action: {
                                    withAnimation(.spring()) {
                                        viewModel.scale = min(4.0, viewModel.scale + 0.2)
                                    }
                                }, label: {
                                    Image(systemName: "plus")
                                        .font(.system(size: 12))
                                })
                                .disabled(viewModel.scale >= 4.0)
                                .help("Zoom in")
                            }

                            Text(file.name)
                                .font(.headline)
                            Text(file.url.deletingLastPathComponent().path())
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding()
                }
                .padding()
                .onTapGesture(count: 2) {
                    guard let selectedID = selectedFileID,
                          let file = files.first(where: { $0.id == selectedID }) else { return }

                    ZoomPreviewHandler.handle(
                        file: file,
                        useThumbnailAsZoomPreview: viewModel.useThumbnailAsZoomPreview,
                        setNSImage: { nsImage = $0 },
                        setCGImage: { cgImage = $0 },
                        openWindow: { id in openWindow(id: id) },
                    )
                }
            } else {
                ZStack {
                    Color(red: 0.118, green: 0.106, blue: 0.094)
                        .ignoresSafeArea()
                    RadialGradient(
                        colors: [Color(red: 0.71, green: 0.55, blue: 0.39).opacity(0.10), .clear],
                        center: UnitPoint(x: 0.3, y: 0.4),
                        startRadius: 0,
                        endRadius: 400,
                    )
                    .ignoresSafeArea()
                    RadialGradient(
                        colors: [Color(red: 0.31, green: 0.39, blue: 0.55).opacity(0.08), .clear],
                        center: UnitPoint(x: 0.75, y: 0.7),
                        startRadius: 0,
                        endRadius: 380,
                    )
                    .ignoresSafeArea()
                    grainOverlay
                        .ignoresSafeArea()

                    VStack(spacing: 0) {
                        Image(nsImage: NSApp.applicationIconImage)
                            .resizable()
                            .frame(width: 72, height: 72)
                            .clipShape(RoundedRectangle(cornerRadius: 16))
                            .padding(.bottom, 22)

                        Text("Ready when you are.")
                            .font(.system(size: 17, weight: .medium))
                            .foregroundStyle(.primary.opacity(0.85))
                            .padding(.bottom, 7)

                        Text("Select a photo to begin culling.")
                            .font(.system(size: 13, weight: .regular))
                            .foregroundStyle(.secondary.opacity(0.7))
                    }
                }
            }
        }
    }

    var files: [FileItem] {
        viewModel.files
    }

    var grainOverlay: some View {
        Canvas { context, size in
            var rng = SystemRandomNumberGenerator()
            for _ in 0 ..< Int(size.width * size.height * 0.015) {
                let x = CGFloat.random(in: 0 ..< size.width, using: &rng)
                let y = CGFloat.random(in: 0 ..< size.height, using: &rng)
                let opacity = Double.random(in: 0.01 ... 0.045, using: &rng)
                context.fill(
                    Path(CGRect(x: x, y: y, width: 1, height: 1)),
                    with: .color(.white.opacity(opacity)),
                )
            }
        }
        .allowsHitTesting(false)
        .blendMode(.screen)
    }

    var focusPoints: [FocusPoint]? {
        viewModel.getFocusPoints()
    }
}
