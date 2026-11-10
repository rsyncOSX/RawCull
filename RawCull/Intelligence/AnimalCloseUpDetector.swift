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
            guard let minX = points.values.map(\.x).min(), let maxX = points.values.map(\.x).max(),
                  let minY = points.values.map(\.y).min(), let maxY = points.values.map(\.y).max()
            else { return [] }

            // A single landmark cannot establish a reliable crop scale.
            let span = max(maxX - minX, maxY - minY)
            guard span >= 12 else { return [] }

            func normalizedCrop(center: CGPoint, side: CGFloat) -> CGRect {
                let crop = CGRect(x: center.x - side / 2, y: center.y - side / 2, width: side, height: side)
                    .intersection(imageBounds)
                return CGRect(x: crop.minX / width, y: crop.minY / height,
                              width: crop.width / width, height: crop.height / height)
            }

            let center = CGPoint(x: (minX + maxX) / 2, y: (minY + maxY) / 2)
            let head = Region(kind: .head, bounds: normalizedCrop(center: center, side: span * 1.25))
            let eyes = [VNAnimalBodyPoseObservation.JointName.leftEye, .rightEye].compactMap { joint in
                points[joint].map { Region(kind: .eye, bounds: normalizedCrop(center: $0, side: max(12, span * 0.35))) }
            }
            return [head] + eyes
        }
    }
}
