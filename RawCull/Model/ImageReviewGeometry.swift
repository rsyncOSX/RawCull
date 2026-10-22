import CoreGraphics

nonisolated enum ImageReviewGeometry {
    static func aspectFitRect(imageSize: CGSize, in viewportSize: CGSize) -> CGRect {
        guard isFinitePositive(imageSize),
              isFinitePositive(viewportSize)
        else { return .zero }

        let scale = min(viewportSize.width / imageSize.width, viewportSize.height / imageSize.height)
        guard scale.isFinite, scale > 0 else { return .zero }
        let size = CGSize(width: imageSize.width * scale, height: imageSize.height * scale)
        guard isFinitePositive(size) else { return .zero }
        return CGRect(
            x: (viewportSize.width - size.width) / 2,
            y: (viewportSize.height - size.height) / 2,
            width: size.width,
            height: size.height,
        )
    }

    private static func isFinitePositive(_ size: CGSize) -> Bool {
        size.width.isFinite && size.height.isFinite && size.width > 0 && size.height > 0
    }
}
