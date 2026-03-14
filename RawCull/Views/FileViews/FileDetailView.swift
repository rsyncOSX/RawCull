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

                                Button(action: {
                                    viewModel.hideInspector.toggle()
                                }, label: {
                                    Image(systemName: "rectangle.portrait.and.arrow.right")
                                        .font(.system(size: 12))
                                })
                                .help("Toggle Inspector")
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
                ContentUnavailableView(
                    "No Selection",
                    systemImage: "doc.text",
                    description: Text("Select a File or Image to view its properties."),
                )
            }
        }
    }

    var files: [FileItem] {
        viewModel.files
    }

    var focusPoints: [FocusPoint]? {
        viewModel.getFocusPoints()
    }
}
