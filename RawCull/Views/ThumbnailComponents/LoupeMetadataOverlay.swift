import SwiftUI

struct LoupeMetadataOverlay: View {
    @Environment(RatingsModel.self) private var ratings
    @Environment(WorkspacePresentationModel.self) private var presentation
    @Environment(WorkspaceNavigationModel.self) private var navigation
    @Environment(SharpnessScoringModel.self) private var sharpnessModel
    @Environment(RawCullSimilarityFeature.self) private var similarityFeature
    let file: FileItem
    let image: NSImage?
    let previewSource: ImagePreviewSource
    let semanticSearchFeature: RawCullSemanticSearchFeature

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            CurrentRatingBadgeView(
                rating: ImageReviewFeaturePolicy.ratingDisplay(for: file, using: ratings),
                density: .compact,
            )

            if presentation.showsLoupeMetadataPanel {
                ZoomMetadataPanel(
                    file: file,
                    image: image,
                    cullingMetadata: ZoomCullingMetadata.make(
                        for: file,
                        sharpnessModel: sharpnessModel,
                        similarityFeature: similarityFeature,
                        semanticSearchFeature: semanticSearchFeature,
                    ),
                    onHide: {
                        withAnimation(.snappy) {
                            presentation.showsLoupeMetadataPanel = false
                        }
                    },
                    previewSource: previewSource,
                    onOpenZoom: { navigation.openZoomOverlay(initialSource: .embeddedJPG) },
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
