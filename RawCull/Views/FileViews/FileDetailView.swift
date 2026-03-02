import SwiftUI

struct FileDetailView: View {
    @Environment(\.openWindow) var openWindow

    @Binding var cgImage: CGImage?
    @Binding var nsImage: NSImage?
    @Binding var selectedFileID: UUID?
    @Binding var scale: CGFloat
    @Binding var lastScale: CGFloat
    @Binding var offset: CGSize

    @State var showDetailsTagView: Bool = false

    let files: [FileItem]
    let file: FileItem?
    let focusPoints: [FocusPoint]?

    var body: some View {
        if showDetailsTagView, let url = file?.url {
            DeepDiveTagsView(
                showDetailsTagView: $showDetailsTagView,
                url: url
            )
        } else {
            if let file = file {
                VStack(spacing: 20) {
                    CachedThumbnailView(
                        scale: $scale,
                        lastScale: $lastScale,
                        offset: $offset,
                        url: file.url
                    )

                    HStack {
                        VStack {
                            Text(file.name)
                                .font(.headline)
                            Text(file.url.deletingLastPathComponent().path())
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        ToggleViewDefault(
                            text: "Show Details",
                            binding: Binding<Bool>(
                                get: { showDetailsTagView },
                                set: { newValue in
                                    showDetailsTagView = newValue
                                }
                            )
                        )
                    }
                    .padding()
                }
                .padding()
                .frame(minWidth: 300, minHeight: 300)
                .onTapGesture(count: 2) {
                    guard let selectedID = selectedFileID,
                          let file = files.first(where: { $0.id == selectedID }) else { return }

                    JPGPreviewHandler.handle(
                        file: file,
                        setNSImage: { nsImage = $0 },
                        setCGImage: { cgImage = $0 },
                        openWindow: { id in openWindow(id: id) }
                    )
                }
            } else {
                ContentUnavailableView(
                    "No Selection",
                    systemImage: "doc.text",
                    description: Text("Select a file to view its properties.")
                )
            }
        }
    }
}
