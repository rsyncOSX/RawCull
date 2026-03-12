import SwiftUI

struct HistogramPath: Shape {
    let bins: [CGFloat]

    func path(in rect: CGRect) -> Path {
        var path = Path()

        guard !bins.isEmpty else { return path }

        let stepX = rect.width / CGFloat(bins.count)

        // Start at bottom left
        path.move(to: CGPoint(x: rect.minX, y: rect.maxY))

        for (index, value) in bins.enumerated() {
            let xval = rect.minX + (CGFloat(index) * stepX)
            // Invert Y because 0 is at the top in UIKit/SwiftUI
            let height = rect.height * value
            let yval = rect.maxY - height

            path.addLine(to: CGPoint(x: xval, y: yval))
        }

        // Line to bottom right
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        path.closeSubpath()

        return path
    }
}
