//
//  ThumbnailImageView.swift
//  RawCull
//
//  Created by Thomas Evensen on 15/03/2026.
//

import SwiftUI

nonisolated enum ThumbnailStyle: Hashable, Sendable {
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

    @State private var presentation = ThumbnailPresentationModel()

    private var request: ThumbnailRequest? {
        guard let sourceURL = url ?? file?.url else { return nil }
        return ThumbnailRequest(
            url: sourceURL, targetSize: targetSize, style: style,
            fileSize: file?.size, modificationDate: file?.dateModified,
        )
    }

    var body: some View {
        ZStack {
            if let thumbnailImage = presentation.image {
                Image(nsImage: thumbnailImage)
                    .resizable()
                    .aspectRatio(contentMode: contentMode)
            } else if presentation.isLoading {
                if showsShimmer {
                    shimmerPlaceholder
                } else {
                    ProgressView()
                }
            } else {
                Rectangle().fill(Color(white: 0.15))
            }
        }
        .task(id: request) {
            guard let request else { return }
            await presentation.load(
                request: request,
                imageLoader: { await loadThumbnail() },
                publish: { imageBinding?.wrappedValue = $0 },
            )
        }
    }

    init(
        file: FileItem,
        targetSize: Int,
        style: ThumbnailStyle,
        showsShimmer: Bool = false,
        contentMode: ContentMode = .fill,
        image: Binding<NSImage?>? = nil,
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
        image: Binding<NSImage?>? = nil,
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
            if let file {
                return await ThumbnailLoader.shared.thumbnailLoader(file: file, targetSize: targetSize)
            }
            return nil

        case .list:
            guard let url else { return nil }
            let cgThumb = await RequestThumbnail.shared.requestThumbnail(
                for: url,
                targetSize: targetSize,
                purpose: .preview,
            )
            return cgThumb.map { NSImage(cgImage: $0, size: .zero) }
        }
    }

    private var shimmerPlaceholder: some View {
        Rectangle()
            .fill(Color(white: 0.15))
            .overlay(
                ProgressView()
                    .controlSize(.small)
                    .tint(.secondary),
            )
    }
}
