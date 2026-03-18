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

    @State private var rotation: Double = 0

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
                        endRadius: 400
                    )
                    .ignoresSafeArea()
                    RadialGradient(
                        colors: [Color(red: 0.31, green: 0.39, blue: 0.55).opacity(0.08), .clear],
                        center: UnitPoint(x: 0.75, y: 0.7),
                        startRadius: 0,
                        endRadius: 380
                    )
                    .ignoresSafeArea()
                    grainOverlay
                        .ignoresSafeArea()

                    VStack(spacing: 16) {
                        apertureIcon
                        Text("Ready when you are.")
                            .font(.custom("Georgia", size: 24))
                            .italic()
                            .fontWeight(.light)
                            .foregroundStyle(Color.white.opacity(0.72))
                        Text("Select a photo to begin culling.")
                            .font(.system(.callout, design: .monospaced))
                            .foregroundStyle(Color.white.opacity(0.32))
                            .multilineTextAlignment(.center)
                            .frame(maxWidth: 280)
                    }
                    .padding()
                }
            }
        }
    }

    var files: [FileItem] {
        viewModel.files
    }

    var apertureIcon: some View {
        Canvas { context, size in
            let center = CGPoint(x: size.width / 2, y: size.height / 2)
            let outerR: CGFloat = size.width / 2
            let innerR: CGFloat = outerR * 0.55
            let spokeColor = Color(red: 0.82, green: 0.73, blue: 0.58).opacity(0.45)

            context.stroke(
                Path(ellipseIn: CGRect(x: 0, y: 0, width: size.width, height: size.height)),
                with: .color(spokeColor),
                lineWidth: 0.8
            )
            let innerRect = CGRect(
                x: size.width / 2 - innerR, y: size.height / 2 - innerR,
                width: innerR * 2, height: innerR * 2
            )
            context.stroke(
                Path(ellipseIn: innerRect),
                with: .color(spokeColor.opacity(0.6)),
                lineWidth: 0.6
            )
            for i in 0..<8 {
                let angle = Double(i) * .pi / 4
                let spokeStart = CGPoint(
                    x: center.x + cos(angle) * innerR,
                    y: center.y + sin(angle) * innerR
                )
                let spokeEnd = CGPoint(
                    x: center.x + cos(angle) * outerR,
                    y: center.y + sin(angle) * outerR
                )
                var path = Path()
                path.move(to: spokeStart)
                path.addLine(to: spokeEnd)
                context.stroke(
                    path,
                    with: .color(spokeColor.opacity(i % 2 == 0 ? 0.7 : 0.35)),
                    lineWidth: 0.8
                )
            }
            let dotR: CGFloat = 4
            context.fill(
                Path(ellipseIn: CGRect(
                    x: center.x - dotR, y: center.y - dotR,
                    width: dotR * 2, height: dotR * 2
                )),
                with: .color(spokeColor)
            )
        }
        .frame(width: 52, height: 52)
        .rotationEffect(.degrees(rotation))
        .onAppear {
            withAnimation(.linear(duration: 24).repeatForever(autoreverses: false)) {
                rotation = 360
            }
        }
    }

    var grainOverlay: some View {
        Canvas { context, size in
            var rng = SystemRandomNumberGenerator()
            for _ in 0..<Int(size.width * size.height * 0.015) {
                let x = CGFloat.random(in: 0..<size.width, using: &rng)
                let y = CGFloat.random(in: 0..<size.height, using: &rng)
                let opacity = Double.random(in: 0.01...0.045, using: &rng)
                context.fill(
                    Path(CGRect(x: x, y: y, width: 1, height: 1)),
                    with: .color(.white.opacity(opacity))
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
