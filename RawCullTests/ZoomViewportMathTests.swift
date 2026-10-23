import CoreGraphics
import Foundation
@testable import RawCull
import Testing

@Suite("ZoomViewportMath")
struct ZoomViewportMathTests {
    @Test(.tags(.smoke))
    func `landscape inspection maps one image pixel to one display point`() {
        let scale = ZoomViewportMath.actualPixelsScale(
            imageSize: CGSize(width: 6000, height: 4000),
            viewportSize: CGSize(width: 1500, height: 1000),
        )

        #expect(scale == 4)
    }

    @Test(.tags(.smoke))
    func `portrait inspection maps one image pixel to one display point`() {
        let scale = ZoomViewportMath.actualPixelsScale(
            imageSize: CGSize(width: 4000, height: 6000),
            viewportSize: CGSize(width: 1000, height: 1500),
        )

        #expect(scale == 4)
    }

    @Test(.tags(.smoke))
    func `inspection scale reduces a fit-upscaled preview to actual pixels`() {
        let scale = ZoomViewportMath.actualPixelsScale(
            imageSize: CGSize(width: 800, height: 600),
            viewportSize: CGSize(width: 1600, height: 1200),
        )

        #expect(scale == 0.5)
    }

    @Test(.tags(.smoke))
    func `aspect mismatch still maps the fitted image to actual pixels`() {
        let fitRect = ZoomViewportMath.aspectFitRect(
            imageSize: CGSize(width: 6000, height: 4000),
            in: CGSize(width: 1200, height: 1200),
        )
        let scale = ZoomViewportMath.actualPixelsScale(
            imageSize: CGSize(width: 6000, height: 4000),
            viewportSize: CGSize(width: 1200, height: 1200),
        )

        #expect(fitRect == CGRect(x: 0, y: 200, width: 1200, height: 800))
        #expect(scale == 5)
        #expect(fitRect.width * scale == 6000)
        #expect(fitRect.height * scale == 4000)
    }

    @Test(.tags(.smoke))
    func `focus point pan centers a normalized point when there is room`() {
        let transform = ZoomViewportMath.actualPixelsTransform(
            imageSize: CGSize(width: 6000, height: 4000),
            viewportSize: CGSize(width: 1500, height: 1000),
            normalizedFocusPoint: CGPoint(x: 0.40, y: 0.50),
        )

        #expect(transform.scale == 4)
        #expect(transform.offset.width == 600)
        #expect(transform.offset.height == 0.0)
    }

    @Test(.tags(.smoke))
    func `focus point pan clamps at all four image edges`() {
        let imageSize = CGSize(width: 6000, height: 4000)
        let viewportSize = CGSize(width: 1500, height: 1000)

        let left = ZoomViewportMath.actualPixelsTransform(
            imageSize: imageSize,
            viewportSize: viewportSize,
            normalizedFocusPoint: CGPoint(x: 0, y: 0.5),
        )
        let right = ZoomViewportMath.actualPixelsTransform(
            imageSize: imageSize,
            viewportSize: viewportSize,
            normalizedFocusPoint: CGPoint(x: 1, y: 0.5),
        )
        let top = ZoomViewportMath.actualPixelsTransform(
            imageSize: imageSize,
            viewportSize: viewportSize,
            normalizedFocusPoint: CGPoint(x: 0.5, y: 0),
        )
        let bottom = ZoomViewportMath.actualPixelsTransform(
            imageSize: imageSize,
            viewportSize: viewportSize,
            normalizedFocusPoint: CGPoint(x: 0.5, y: 1),
        )

        #expect(left.offset == CGSize(width: 2250, height: 0))
        #expect(right.offset == CGSize(width: -2250, height: 0))
        #expect(top.offset == CGSize(width: 0, height: 1500))
        #expect(bottom.offset == CGSize(width: 0, height: -1500))
    }

    @Test(.tags(.smoke))
    func `out of range focus point clamps to an image edge`() {
        let transform = ZoomViewportMath.actualPixelsTransform(
            imageSize: CGSize(width: 6000, height: 4000),
            viewportSize: CGSize(width: 1500, height: 1000),
            normalizedFocusPoint: CGPoint(x: -2, y: 3),
        )

        #expect(transform.offset == CGSize(width: 2250, height: -1500))
    }

    @Test(.tags(.smoke))
    func `missing focus point keeps actual-pixels view centered`() {
        let transform = ZoomViewportMath.actualPixelsTransform(
            imageSize: CGSize(width: 6000, height: 4000),
            viewportSize: CGSize(width: 1500, height: 1000),
            normalizedFocusPoint: nil,
        )

        #expect(transform.scale == 4)
        #expect(transform.offset == .zero)
    }

    @Test(.tags(.smoke))
    func `invalid sizes use a finite centered fallback`() {
        let invalidSizes = [
            CGSize(width: 0, height: 4000),
            CGSize(width: -1, height: 4000),
            CGSize(width: CGFloat.infinity, height: 4000),
            CGSize(width: CGFloat.nan, height: 4000),
        ]

        for invalidSize in invalidSizes {
            let transform = ZoomViewportMath.actualPixelsTransform(
                imageSize: invalidSize,
                viewportSize: CGSize(width: 1500, height: 1000),
                normalizedFocusPoint: CGPoint(x: 0.5, y: 0.5),
            )

            #expect(transform.scale == 1)
            #expect(transform.scale.isFinite)
            #expect(transform.offset == .zero)
        }
    }

    @Test(.tags(.smoke))
    func `non finite focus point uses a centered fallback`() {
        let transform = ZoomViewportMath.actualPixelsTransform(
            imageSize: CGSize(width: 6000, height: 4000),
            viewportSize: CGSize(width: 1500, height: 1000),
            normalizedFocusPoint: CGPoint(x: CGFloat.nan, y: 0.5),
        )

        #expect(transform.scale == 4)
        #expect(transform.offset == .zero)
    }
}
