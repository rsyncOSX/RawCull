import SwiftUI

struct FileDetailView: View {
    @Environment(\.openWindow) var openWindow

    @Binding var cgImage: CGImage?
    @Binding var nsImage: NSImage?
    @Binding var selectedFileID: UUID?
    @Binding var scale: CGFloat
    @Binding var lastScale: CGFloat
    @Binding var offset: CGSize

    /// Used if selectedFileID = nil and user double click on picture when
    /// inspector tab is hidded, e.g. selectedFileID == nil
    @State var savedselecetdFileID: UUID?

    let files: [FileItem]
    let file: FileItem?

    var body: some View {
        if let file = file {
            VStack(spacing: 20) {
                CachedThumbnailView(
                    url: file.url,
                    scale: $scale,
                    lastScale: $lastScale,
                    offset: $offset
                )

                VStack {
                    Text(file.name)
                        .font(.headline)
                    Text(file.url.deletingLastPathComponent().path())
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding()
            }
            .padding()
            .frame(minWidth: 300, minHeight: 300)
            .onTapGesture(count: 2) {
                if selectedFileID == nil, let savedselecetdFileID {
                    selectedFileID = savedselecetdFileID
                }

                guard let selectedID = selectedFileID,
                      let file = files.first(where: { $0.id == selectedID }) else { return }

                JPGPreviewHandler.handle(
                    file: file,
                    setNSImage: { nsImage = $0 },
                    setCGImage: { cgImage = $0 },
                    openWindow: { id in openWindow(id: id) }
                )
            }
            .onTapGesture(count: 1) {
                // Just save the ID.
                savedselecetdFileID = selectedFileID
                selectedFileID = nil
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
