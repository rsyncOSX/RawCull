import SwiftUI

struct CachedThumbnailView: View {
    let url: URL

    @Binding var scale: CGFloat
    @Binding var lastScale: CGFloat
    @Binding var offset: CGSize

    @State private var image: NSImage?
    @State private var isLoading = false

    var body: some View {
        ZStack {
            if let image {
                VStack {
                    // Image display with zoom
                    GeometryReader { geo in
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
            let cgImage = await SharedRequestThumbnail.shared.requestthumbnail(
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
}
