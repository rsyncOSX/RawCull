//
//  ThumbnailImageView.swift
//  RawCull
//
//  Created by Thomas Evensen on 15/03/2026.
//

import SwiftUI

enum ThumbnailStyle {
    case grid
    case list
}

struct ThumbnailImageView: View {
    private let file: FileItem?
    private let url: URL?
    let targetSize: Int
    let style: ThumbnailStyle
    let showsShimmer: Bool
    let contentMode: ContentMode
    private let imageBinding: Binding<NSImage?>?

    @State private var thumbnailImage: NSImage?
    @State private var isLoading = false
    @State private var shimmerOffset: CGFloat = -1.0
    
   
    var body: some View {
        ZStack {
            if let thumbnailImage {
                Image(nsImage: thumbnailImage)
                    .resizable()
                    .aspectRatio(contentMode: contentMode)
            } else if isLoading {
                if showsShimmer {
                    shimmerPlaceholder
                } else {
                    ProgressView()
                }
            } else {
                Rectangle().fill(Color(white: 0.15))
            }
        }
        .task(id: url ?? file?.url) {
            guard url != nil || file != nil else { return }
            isLoading = true
            let loadedImage = await loadThumbnail()
            await MainActor.run {
                thumbnailImage = loadedImage
                imageBinding?.wrappedValue = loadedImage
            }
            isLoading = false
        }
    }

    init(
        file: FileItem,
        targetSize: Int,
        style: ThumbnailStyle,
        showsShimmer: Bool = false,
        contentMode: ContentMode = .fill,
        image: Binding<NSImage?>? = nil
    ) {
        self.file = file
        self.url = nil
        self.targetSize = targetSize
        self.style = style
        self.showsShimmer = showsShimmer
        self.contentMode = contentMode
        self.imageBinding = image
    }

    init(
        url: URL,
        targetSize: Int,
        style: ThumbnailStyle,
        showsShimmer: Bool = false,
        contentMode: ContentMode = .fill,
        image: Binding<NSImage?>? = nil
    ) {
        self.file = nil
        self.url = url
        self.targetSize = targetSize
        self.style = style
        self.showsShimmer = showsShimmer
        self.contentMode = contentMode
        self.imageBinding = image
    }

    private func loadThumbnail() async -> NSImage? {
        switch style {
        case .grid:
            if let file { return await ThumbnailLoader.shared.thumbnailLoader(file: file) }
            return nil
        case .list:
            guard let url else { return nil }
            let cgThumb = await RequestThumbnail().requestThumbnail(for: url, targetSize: targetSize)
            return cgThumb.map { NSImage(cgImage: $0, size: .zero) }
        }
    }

    private var shimmerPlaceholder: some View {
        Rectangle()
            .fill(Color(white: 0.15))
            .overlay(
                GeometryReader { geo in
                    Rectangle()
                        .fill(
                            LinearGradient(
                                colors: [
                                    .clear,
                                    Color(white: 0.3).opacity(0.4),
                                    .clear
                                ],
                                startPoint: .leading,
                                endPoint: .trailing,
                            ),
                        )
                        .frame(width: geo.size.width * 0.5)
                        .offset(x: shimmerOffset * geo.size.width)
                }
                .clipped(),
            )
            .onAppear {
                withAnimation(.linear(duration: 1.4).repeatForever(autoreverses: false)) {
                    shimmerOffset = 1.5
                }
            }
    }
}
