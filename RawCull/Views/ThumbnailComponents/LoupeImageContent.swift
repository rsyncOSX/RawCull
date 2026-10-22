import SwiftUI

struct LoupeImageContent: View {
    let session: LoupeSessionModel
    let url: URL
    let thumbnailSizePreview: Int

    var body: some View {
        @Bindable var session = session
        switch session.sourceSelection.selected {
        case .thumbnail:
            ThumbnailImageView(
                url: url,
                targetSize: thumbnailSizePreview,
                style: .list,
                showsShimmer: false,
                contentMode: .fit,
                image: $session.thumbnailImage,
            )

        case .embeddedJPG:
            if let embeddedJPGImage = session.embeddedJPGImage {
                Image(decorative: embeddedJPGImage, scale: 1.0, orientation: .up)
                    .resizable()
                    .scaledToFit()
            } else if session.isLoadingSource {
                ProgressView()
                    .fixedSize()
            } else {
                VStack(spacing: 6) {
                    Image(systemName: "photo.badge.exclamationmark")
                        .font(.title3)
                    Text("No extracted JPG")
                        .font(.caption)
                }
                .foregroundStyle(.secondary)
            }

        case .developedRAW:
            if let developedRAWImage = session.developedRAWImage {
                Image(decorative: developedRAWImage, scale: 1.0, orientation: .up)
                    .resizable()
                    .scaledToFit()
            } else {
                ProgressView()
                    .fixedSize()
            }
        }
    }
}
