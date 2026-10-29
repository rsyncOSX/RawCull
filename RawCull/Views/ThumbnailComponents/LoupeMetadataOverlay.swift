import SwiftUI

struct LoupeMetadataOverlay: View {
    let viewModel: RawCullViewModel
    let file: FileItem
    let image: NSImage?
    let previewSource: ImagePreviewSource
    let semanticSearchFeature: RawCullSemanticSearchFeature

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            CurrentRatingBadgeView(
                rating: ImageReviewFeaturePolicy.ratingDisplay(for: file, using: viewModel),
                density: .compact,
            )

            if viewModel.showsLoupeMetadataPanel {
                ZoomMetadataPanel(
                    file: file,
                    image: image,
                    cullingMetadata: ZoomCullingMetadata.make(
                        for: file,
                        viewModel: viewModel,
                        semanticSearchFeature: semanticSearchFeature,
                    ),
                    onHide: {
                        withAnimation(.snappy) {
                            viewModel.showsLoupeMetadataPanel = false
                        }
                    },
                    previewSource: previewSource,
                    onOpenZoom: { viewModel.openZoomOverlay(initialSource: .embeddedJPG) },
                )
                .transition(.move(edge: .trailing).combined(with: .opacity))
            }
        }
        .padding(8)
        .frame(
            maxWidth: .infinity,
            maxHeight: .infinity,
            alignment: .topTrailing,
        )
    }
}
