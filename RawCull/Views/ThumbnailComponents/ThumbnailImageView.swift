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

    @State private var thumbnailImage: NSImage?
    @State private var isLoading = false
    
   
    var body: some View {
        ZStack {
            if let thumbnailImage {
                Image(nsImage: thumbnailImage)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } else if isLoading {
                ProgressView()
            } else {
                Rectangle().fill(Color(white: 0.15))
            }
        }
        .task(id: url ?? file?.url) {
            guard url != nil || file != nil else { return }
            isLoading = true
            thumbnailImage = await loadThumbnail()
            isLoading = false
        }
    }

    init(file: FileItem, targetSize: Int, style: ThumbnailStyle) {
        self.file = file
        self.url = nil
        self.targetSize = targetSize
        self.style = style
    }

    init(url: URL, targetSize: Int, style: ThumbnailStyle) {
        self.file = nil
        self.url = url
        self.targetSize = targetSize
        self.style = style
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
}

