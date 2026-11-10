import CoreGraphics
import Vision

nonisolated enum AnimalCloseUpDetector {
    enum Kind: Sendable {
        case head
        case eye
    }

    struct Region: Sendable {
        let kind: Kind
        let bounds: CGRect
    }

    static func regions(in preview: CGImage) throws -> [Region] {
        try Task.checkCancellation()
        let request = VNDetectAnimalBodyPoseRequest()
        try VNImageRequestHandler(cgImage: preview, orientation: .up).perform([request])
        try Task.checkCancellation()

        let width = CGFloat(preview.width)
        let height = CGFloat(preview.height)
        let imageBounds = CGRect(x: 0, y: 0, width: width, height: height)
        return try (request.results ?? []).flatMap { observation -> [Region] in
            let points = try observation.recognizedPoints(.head).compactMapValues { point -> CGPoint? in
                let location = point.location
                guard point.confidence >= 0.5, (0...1).contains(location.x), (0...1).contains(location.y) else {
                    return nil
                }
                return CGPoint(x: location.x * width, y: (1 - location.y) * height)
            }
            let eyes = [VNAnimalBodyPoseObservation.JointName.leftEye, .rightEye].compactMap { points[$0] }
            return crops(headPoints: Array(points.values), eyes: eyes, in: imageBounds)
        }
    }

    static func crops(headPoints: [CGPoint], eyes: [CGPoint], in imageBounds: CGRect) -> [Region] {
        guard let minX = headPoints.map(\.x).min(), let maxX = headPoints.map(\.x).max(),
              let minY = headPoints.map(\.y).min(), let maxY = headPoints.map(\.y).max()
        else { return [] }

        let span = max(maxX - minX, maxY - minY)
        guard span >= 12 else { return [] }

        func square(center: CGPoint, side: CGFloat) -> CGRect {
            CGRect(x: center.x - side / 2, y: center.y - side / 2, width: side, height: side)
        }

        func normalized(_ crop: CGRect) -> CGRect {
            CGRect(x: (crop.minX - imageBounds.minX) / imageBounds.width,
                   y: (crop.minY - imageBounds.minY) / imageBounds.height,
                   width: crop.width / imageBounds.width, height: crop.height / imageBounds.height)
        }

        let center = CGPoint(x: (minX + maxX) / 2, y: (minY + maxY) / 2)
        let head = square(center: center, side: span * 1.25).intersection(imageBounds)
        let eyeRegions = eyes.compactMap { eye -> Region? in
            guard head.contains(eye) else { return nil }
            let crop = square(center: eye, side: max(12, span * 0.35)).intersection(head)
            return Region(kind: .eye, bounds: normalized(crop))
        }
        return [Region(kind: .head, bounds: normalized(head))] + eyeRegions
    }
}
