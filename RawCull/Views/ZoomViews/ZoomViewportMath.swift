import AppKit
import RawCullCore
import SwiftUI

nonisolated enum ZoomViewportMath {
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

    static func actualPixelsScale(imageSize: CGSize, viewportSize: CGSize) -> CGFloat {
        let fitRect = aspectFitRect(imageSize: imageSize, in: viewportSize)
        guard fitRect.width > 0, fitRect.height > 0 else { return 1.0 }
        let fitScale = min(fitRect.width / imageSize.width, fitRect.height / imageSize.height)
        guard fitScale > 0, fitScale.isFinite else { return 1.0 }
        let actualPixelsScale = 1.0 / fitScale
        return actualPixelsScale.isFinite && actualPixelsScale > 0
            ? actualPixelsScale
            : 1.0
    }

    static func actualPixelsTransform(
        imageSize: CGSize,
        viewportSize: CGSize,
        normalizedFocusPoint: CGPoint?,
    ) -> ZoomViewportTransform {
        let scale = actualPixelsScale(imageSize: imageSize, viewportSize: viewportSize)
        guard let normalizedFocusPoint,
              normalizedFocusPoint.x.isFinite,
              normalizedFocusPoint.y.isFinite
        else {
            return ZoomViewportTransform(scale: scale, offset: .zero)
        }

        let fitRect = aspectFitRect(imageSize: imageSize, in: viewportSize)
        guard fitRect.width > 0, fitRect.height > 0 else {
            return ZoomViewportTransform(scale: scale, offset: .zero)
        }

        let clampedFocusPoint = CGPoint(
            x: min(max(normalizedFocusPoint.x, 0), 1),
            y: min(max(normalizedFocusPoint.y, 0), 1),
        )
        let point = CGPoint(
            x: fitRect.minX + clampedFocusPoint.x * fitRect.width,
            y: fitRect.minY + clampedFocusPoint.y * fitRect.height,
        )
        let viewportCenter = CGPoint(x: viewportSize.width / 2, y: viewportSize.height / 2)
        let desiredOffset = CGSize(
            width: (viewportCenter.x - point.x) * scale,
            height: (viewportCenter.y - point.y) * scale,
        )
        let scaledImageSize = CGSize(width: fitRect.width * scale, height: fitRect.height * scale)
        return ZoomViewportTransform(
            scale: scale,
            offset: clampedOffset(desiredOffset, scaledImageSize: scaledImageSize, viewportSize: viewportSize),
        )
    }

    private static func clampedOffset(
        _ offset: CGSize,
        scaledImageSize: CGSize,
        viewportSize: CGSize,
    ) -> CGSize {
        guard offset.width.isFinite,
              offset.height.isFinite,
              isFinitePositive(scaledImageSize),
              isFinitePositive(viewportSize)
        else { return .zero }

        let maxX = max(0, (scaledImageSize.width - viewportSize.width) / 2)
        let maxY = max(0, (scaledImageSize.height - viewportSize.height) / 2)
        return CGSize(
            width: min(max(offset.width, -maxX), maxX),
            height: min(max(offset.height, -maxY), maxY),
        )
    }

    private static func isFinitePositive(_ size: CGSize) -> Bool {
        size.width.isFinite && size.width > 0
            && size.height.isFinite && size.height > 0
    }
}
