import SwiftUI

/// Display-only overlay. Source loading and visibility belong to the owning screen.
struct ImageReviewRasterOverlay: View {
    enum Kind { case focusMap, subjectOutline }

    let image: Image
    let size: CGSize
    var kind: Kind = .focusMap

    var body: some View {
        image
            .resizable()
            .scaledToFit()
            .frame(width: size.width, height: size.height)
            .colorMultiply(kind == .subjectOutline ? .orange : .white)
            .blendMode(.screen)
            .opacity(0.95)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }
}
