import Foundation
import ImageIO
import CoreImage
import Vision

// The most distant contour points define the long axis. Measure the
// perpendicular extent in image pixels so face aspect ratio and roll are respected.
func eyeGeometry(_ region: VNFaceLandmarkRegion2D, in face: CGRect) -> (width: Double, aperture: Double?)? {
    let points = region.normalizedPoints.map {
        CGPoint(x: $0.x * face.width, y: $0.y * face.height)
    }
    guard points.count >= 4 else { return nil }
    var axis = CGPoint.zero
    var width: CGFloat = 0
    for first in points {
        for second in points {
            let delta = CGPoint(x: second.x - first.x, y: second.y - first.y)
            let distance = hypot(delta.x, delta.y)
            if distance > width {
                axis = delta
                width = distance
            }
        }
    }
    guard width.isFinite, width > 0 else { return nil }
    guard width >= 8 else { return (width, nil) }
    let projections = points.map { ($0.y * axis.x - $0.x * axis.y) / width }
    guard let low = projections.min(), let high = projections.max() else { return nil }
    return (width, (high - low) / width)
}

func centerX(_ eye: VNFaceLandmarkRegion2D) -> CGFloat {
    eye.normalizedPoints.map(\.x).reduce(0, +) / CGFloat(eye.pointCount)
}

func overlaps(_ first: CGRect, _ second: CGRect) -> Bool {
    let intersection = first.intersection(second)
    guard !intersection.isNull else { return false }
    let shared = intersection.width * intersection.height
    let total = first.width * first.height + second.width * second.height - shared
    return total > 0 && shared / total >= 0.5
}

guard (3...4).contains(CommandLine.arguments.count),
      let size = Int(CommandLine.arguments[2]), size > 0 else {
    FileHandle.standardError.write(Data("Usage: people-assessment-pilot RAW_FOLDER MAX_PIXELS [LABEL_MANIFEST.json]\n".utf8))
    exit(2)
}
let root = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
let rawExtensions: Set<String> = ["arw", "cr2", "cr3", "crw", "dng", "nef", "raf", "orf", "rw2"]
let files = try FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil)
    .filter { rawExtensions.contains($0.pathExtension.lowercased()) }
    .sorted { $0.path < $1.path }
guard let detector = CIDetector(
    ofType: CIDetectorTypeFace,
    context: nil,
    options: [CIDetectorAccuracy: CIDetectorAccuracyHigh]
) else {
    FileHandle.standardError.write(Data("Core Image face detector unavailable\n".utf8))
    exit(1)
}
print("file_index,format,decode_ms,vision_ms,core_image_ms,vision_faces,vision_eyes,vision_quality_scores,core_image_faces,core_image_closed_flags,status")
var manifest: [[String: Any]] = []
for (index, file) in files.enumerated() {
    autoreleasepool {
        let clock = ContinuousClock()
        let start = clock.now
        guard let source = CGImageSourceCreateWithURL(file as CFURL, nil),
              let image = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                kCGImageSourceCreateThumbnailFromImageIfAbsent: false,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceThumbnailMaxPixelSize: size,
                kCGImageSourceShouldCacheImmediately: true
              ] as CFDictionary) else {
            print("\(index),\(file.pathExtension),,,,,,,,embedded_preview_unavailable")
            return
        }
        let decoded = clock.now
        let handler = VNImageRequestHandler(cgImage: image)
        let faces = VNDetectFaceRectanglesRequest()
        let landmarks = VNDetectFaceLandmarksRequest()
        let quality = VNDetectFaceCaptureQualityRequest()
        do {
            try handler.perform([faces])
            let detected = faces.results ?? []
            if !detected.isEmpty {
                landmarks.inputFaceObservations = detected
                quality.inputFaceObservations = detected
                try handler.perform([landmarks, quality])
            }
            let eyes = (landmarks.results ?? []).reduce(0) {
                $0 + ($1.landmarks?.leftEye == nil ? 0 : 1) + ($1.landmarks?.rightEye == nil ? 0 : 1)
            }
            let scores = (quality.results ?? []).filter { $0.faceCaptureQuality != nil }.count
            let vision = clock.now
            let ci = detector.features(in: CIImage(cgImage: image), options: [CIDetectorEyeBlink: true])
                .compactMap { $0 as? CIFaceFeature }
            let end = clock.now
            let closed = ci.reduce(0) { $0 + ($1.leftEyeClosed ? 1 : 0) + ($1.rightEyeClosed ? 1 : 0) }
            if CommandLine.arguments.count == 4 {
                let observations = landmarks.results ?? []
                let boxes = observations.map {
                    VNImageRectForNormalizedRect($0.boundingBox, image.width, image.height)
                }
                for (faceIndex, observation) in observations.enumerated() {
                    let box = boxes[faceIndex]
                    let matches = ci.filter { overlaps(box, $0.bounds) }
                    let candidate = matches.count == 1 ? matches.first : nil
                    let match = candidate.flatMap { feature in
                        boxes.filter { overlaps($0, feature.bounds) }.count == 1 ? feature : nil
                    }
                    let eyeRegions = [observation.landmarks?.leftEye, observation.landmarks?.rightEye]
                    let visionEyes = eyeRegions.compactMap { $0 }
                        .filter { $0.pointCount > 0 }
                        .sorted { centerX($0) < centerX($1) }
                    let imageOrderedFlags: [Bool]
                    if let match, match.hasLeftEyePosition, match.hasRightEyePosition,
                       match.leftEyePosition.x != match.rightEyePosition.x {
                        imageOrderedFlags = match.leftEyePosition.x < match.rightEyePosition.x
                            ? [match.leftEyeClosed, match.rightEyeClosed]
                            : [match.rightEyeClosed, match.leftEyeClosed]
                    } else {
                        imageOrderedFlags = []
                    }
                    guard visionEyes.count == 2 else { continue }
                    for (eyeIndex, eye) in visionEyes.enumerated() {
                        let geometry = eyeGeometry(eye, in: box)
                        manifest.append([
                            "file": file.lastPathComponent,
                            "faceIndex": faceIndex,
                            "faceBoxTopLeft": [box.minX / CGFloat(image.width),
                                               1 - box.maxY / CGFloat(image.height),
                                               box.width / CGFloat(image.width),
                                               box.height / CGFloat(image.height)],
                            "eyeInImage": eyeIndex == 0 ? "left" : "right",
                            "aperture": geometry?.aperture.map { $0 as Any } ?? NSNull(),
                            "eyeWidthPixels": geometry.map { $0.width as Any } ?? NSNull(),
                            "previewWidth": image.width,
                            "previewHeight": image.height,
                            "yawRadians": observation.yaw.map { $0 as Any } ?? NSNull(),
                            "pitchRadians": observation.pitch.map { $0 as Any } ?? NSNull(),
                            "coreImageClosed": imageOrderedFlags.indices.contains(eyeIndex)
                                ? imageOrderedFlags[eyeIndex] as Any : NSNull(),
                            "label": NSNull()
                        ])
                    }
                }
            }
            func ms(_ a: ContinuousClock.Instant, _ b: ContinuousClock.Instant) -> String {
                let parts = a.duration(to: b).components
                return String(format: "%.2f", Double(parts.seconds) * 1000 + Double(parts.attoseconds) / 1e15)
            }
            print("\(index),\(file.pathExtension),\(ms(start, decoded)),\(ms(decoded, vision)),\(ms(vision, end)),\(detected.count),\(eyes),\(scores),\(ci.count),\(closed),ok")
        } catch {
            FileHandle.standardError.write(Data("\(index): \(error)\n".utf8))
            print("\(index),\(file.pathExtension),,,,,,,,vision_failed")
        }
    }
}
if CommandLine.arguments.count == 4 {
    let data = try JSONSerialization.data(withJSONObject: manifest, options: [.prettyPrinted, .sortedKeys])
    try data.write(to: URL(fileURLWithPath: CommandLine.arguments[3]), options: .atomic)
}
