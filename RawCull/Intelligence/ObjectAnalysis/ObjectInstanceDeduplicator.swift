import CoreGraphics
import Foundation
import PhotoAIContracts

/// Filters weak masks and collapses nearly identical regions across concepts.
nonisolated enum ObjectInstanceDeduplicator {
    struct Candidate: Sendable {
        let concept: SegmentationConcept
        let mask: CGImage
        let score: Float
        let normalizedBoundingBox: CGRect
        let sourceInstanceID: String

        init(concept: SegmentationConcept, mask: CGImage, score: Float,
             normalizedBoundingBox: CGRect, sourceInstanceID: String = "0") {
            self.concept = concept
            self.mask = mask
            self.score = score
            self.normalizedBoundingBox = normalizedBoundingBox
            self.sourceInstanceID = sourceInstanceID
        }
    }

    struct Retained: Sendable {
        let descriptor: ObjectInstanceDescriptor
        let mask: CGImage
    }

    static func retain(_ candidates: [Candidate], maximumCount: Int = 8,
                       minimumScore: Float = 0.5) -> [Retained] {
        struct Work {
            let candidate: Candidate
            let pixels: [UInt8]
            let area: Int
            var aliases: [String]
        }
        let prepared: [Work] = candidates.compactMap { candidate in
            guard candidate.score.isFinite, candidate.score >= minimumScore,
                  candidate.normalizedBoundingBox.width > 0,
                  candidate.normalizedBoundingBox.height > 0,
                  let pixels = sample(candidate.mask) else { return nil }
            let area = pixels.reduce(0) { $0 + ($1 > 127 ? 1 : 0) }
            guard area >= 64, area < pixels.count * 95 / 100 else { return nil }
            return Work(candidate: candidate, pixels: pixels, area: area, aliases: [])
        }.sorted { a, b in
            if a.candidate.score != b.candidate.score {
                return a.candidate.score > b.candidate.score
            }
            if a.candidate.normalizedBoundingBox.minX != b.candidate.normalizedBoundingBox.minX {
                return a.candidate.normalizedBoundingBox.minX < b.candidate.normalizedBoundingBox.minX
            }
            return a.candidate.normalizedBoundingBox.minY < b.candidate.normalizedBoundingBox.minY
        }
        var retained: [Work] = []
        for candidate in prepared {
            if let index = retained.firstIndex(where: { existing in
                guard existing.candidate.normalizedBoundingBox.intersects(candidate.candidate.normalizedBoundingBox) else {
                    return false
                }
                let smallerRatio = Double(min(existing.area, candidate.area))
                    / Double(max(existing.area, candidate.area))
                guard smallerRatio >= 0.8 else { return false }
                let intersection = zip(existing.pixels, candidate.pixels).reduce(0) { count, pair in
                    count + ((pair.0 > 127 && pair.1 > 127) ? 1 : 0)
                }
                let union = existing.area + candidate.area - intersection
                let iou = union > 0 ? Double(intersection) / Double(union) : 0
                let containment = Double(intersection) / Double(min(existing.area, candidate.area))
                return iou >= 0.85 || containment >= 0.90
            }) {
                let alias = candidate.candidate.concept.query
                if alias != retained[index].candidate.concept.query,
                   !retained[index].aliases.contains(alias) {
                    retained[index].aliases.append(alias)
                }
            } else {
                retained.append(candidate)
            }
        }
        return retained.prefix(maximumCount).enumerated().map { index, work in
            Retained(
                descriptor: ObjectInstanceDescriptor(
                    id: String(index + 1), concept: work.candidate.concept.query,
                    aliases: work.aliases, score: work.candidate.score,
                    normalizedBoundingBox: work.candidate.normalizedBoundingBox,
                    sourceInstanceID: work.candidate.sourceInstanceID,
                ),
                mask: work.candidate.mask,
            )
        }
    }

    private static func sample(_ image: CGImage) -> [UInt8]? {
        let side = 256
        var pixels = [UInt8](repeating: 0, count: side * side)
        guard let context = CGContext(data: &pixels, width: side, height: side,
                                      bitsPerComponent: 8, bytesPerRow: side,
                                      space: CGColorSpaceCreateDeviceGray(),
                                      bitmapInfo: CGImageAlphaInfo.none.rawValue) else { return nil }
        context.interpolationQuality = .none
        context.draw(image, in: CGRect(x: 0, y: 0, width: side, height: side))
        return pixels
    }
}
