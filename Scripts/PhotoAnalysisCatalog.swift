import CoreGraphics
import Foundation
import ImageIO
import PhotoAnalysisKit
import UniformTypeIdentifiers

struct Catalog: Decodable {
    let images: [Item]
    let maximumPixels: Int
    let preset: String
    let quality: String
    let threshold: Float
}

struct Item: Decodable, Sendable {
    let id: String
    let path: String
    let iso: Int?
    let aperture: Double?
    let afX: Double?
    let afY: Double?
    let burst: String
    let calibration: Bool
}

func json<T>(_ value: T?) -> Any {
    value.map { $0 as Any } ?? NSNull()
}

func rect(_ value: CGRect?) -> Any {
    json(value.map { [$0.minX, $0.minY, $0.width, $0.height] })
}

func decode(_ item: Item, maximumPixels: Int) -> PhotoAnalysisInput? {
    let url = URL(fileURLWithPath: item.path)
    guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
          let image = CGImageSourceCreateThumbnailAtIndex(source, 0, [
              kCGImageSourceCreateThumbnailFromImageIfAbsent: true,
              kCGImageSourceCreateThumbnailWithTransform: true,
              kCGImageSourceThumbnailMaxPixelSize: maximumPixels
          ] as CFDictionary)
    else { return nil }

    let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [String: Any]
    let exif = properties?[kCGImagePropertyExifDictionary as String] as? [String: Any]
    let iso = item.iso ?? (exif?[kCGImagePropertyExifISOSpeedRatings as String] as? [Int])?.first ?? 400
    let aperture = item.aperture ?? exif?[kCGImagePropertyExifFNumber as String] as? Double
    let af = item.afX.flatMap { x in item.afY.map { CGPoint(x: x, y: $0) } }
    return PhotoAnalysisInput(image: image, iso: iso, aperture: aperture, normalizedAFPoint: af)
}

func writeImage(_ image: CGImage, to url: URL, type: UTType) -> Bool {
    guard let destination = CGImageDestinationCreateWithURL(url as CFURL, type.identifier as CFString, 1, nil)
    else { return false }
    CGImageDestinationAddImage(destination, image, nil)
    return CGImageDestinationFinalize(destination)
}

func maskOutcome(_ image: CGImage?, output: URL, name: String) -> [String: Any] {
    guard let image else { return ["status": "unavailable"] }
    let path = "images/\(name).png"
    return [
        "status": writeImage(image, to: output.appendingPathComponent(path), type: .png) ? "saved" : "writeFailed",
        "file": path, "width": image.width, "height": image.height
    ]
}

func analysis(_ result: PhotoAnalysisResult?) -> [String: Any] {
    guard let result else { return ["status": "decodeFailed"] }
    var row: [String: Any] = ["status": result.breakdown == nil ? "unavailable" : "ok"]
    row["saliency"] = json(result.saliency.map {
        ["subjectLabel": json($0.subjectLabel), "subjectConfidence": json($0.subjectConfidence)]
    })
    if let b = result.breakdown {
        row["breakdown"] = breakdown(b)
    }
    return row
}

func encoded<T: Encodable>(_ value: T) throws -> Any {
    try JSONSerialization.jsonObject(with: JSONEncoder().encode(value))
}

@MainActor
func outcome(_ operation: () async throws -> Any) async -> [String: Any] {
    do { return ["status": "ok", "value": try await operation()] }
    catch { return ["status": "error", "error": String(describing: error)] }
}

func jsonSafe(_ value: Any) -> Any {
    switch value {
    case let object as [String: Any]:
        return object.mapValues(jsonSafe)
    case let array as [Any]:
        return array.map(jsonSafe)
    case let number as NSNumber where !number.doubleValue.isFinite:
        return String(describing: number)
    default:
        return value
    }
}

func elapsed(_ start: ContinuousClock.Instant) -> Double {
    let parts = start.duration(to: .now).components
    return Double(parts.seconds) * 1000 + Double(parts.attoseconds) / 1e15
}

@main
struct PhotoAnalysisCatalog {
    static func main() async throws {
        let input = URL(fileURLWithPath: CommandLine.arguments[1])
        let output = URL(fileURLWithPath: CommandLine.arguments[2], isDirectory: true)
        let catalog = try JSONDecoder().decode(Catalog.self, from: Data(contentsOf: input))
        let analyzer = PhotoAnalyzer()
        let faces = FaceEvidenceAnalyzer()
        let features = VisionFeaturePrintBackend()
        var configuration = (SharpnessPreset(rawValue: catalog.preset) ?? .automatic)
            .applying(to: .birdsInFlight)
        configuration = (SharpnessQuality(rawValue: catalog.quality) ?? .fast).applying(to: configuration)
        configuration.threshold = catalog.threshold

        let requests = catalog.images.map { item in
            PhotoAnalysisBatchRequest(id: item.id) { decode(item, maximumPixels: catalog.maximumPixels) }
        }
        let batchStart = ContinuousClock.now
        let batch = await analyzer.analyzeBatch(requests, configuration: configuration, maximumConcurrentTasks: 1)
        let batchMilliseconds = elapsed(batchStart)
        let batchByID = Dictionary(uniqueKeysWithValues: (batch ?? []).map { ($0.id, $0) })

        let calibrationItems = zip(catalog.images, requests).filter { $0.0.calibration }.map { $0.1 }
        let calibration = await analyzer.calibrate(
            from: calibrationItems, baseConfiguration: configuration,
            minimumSuccessfulImages: min(5, max(1, calibrationItems.count)), maximumConcurrentTasks: 1
        )
        let calibrationResult: [String: Any] = calibration.map {
            ["status": "ok", "threshold": $0.threshold, "sampleCount": $0.sampleCount,
             "p50": $0.p50, "p90": $0.p90, "p95": $0.p95, "p99": $0.p99]
        } ?? ["status": "unavailable"]

        var rows: [[String: Any]] = []
        var burstReferences: [String: (id: String, print: VisionFeaturePrint)] = [:]
        for (index, item) in catalog.images.enumerated() {
            FileHandle.standardError.write(Data("[\(index + 1)/\(catalog.images.count)] \(item.id)\n".utf8))
            let decodeStart = ContinuousClock.now
            let decoded = decode(item, maximumPixels: catalog.maximumPixels)
            var row: [String: Any] = [
                "id": item.id, "batch": analysis(batchByID[item.id]?.analysis),
                "decodeMilliseconds": elapsed(decodeStart)
            ]
            guard let decoded else {
                row["status"] = "decodeFailed"
                rows.append(row)
                continue
            }
            row["status"] = "ok"
            row["input"] = ["width": decoded.image.width, "height": decoded.image.height,
                            "iso": decoded.iso, "aperture": json(decoded.aperture),
                            "af": json(decoded.normalizedAFPoint.map { [$0.x, $0.y] })]
            let preview = "images/\(item.id).jpg"
            if writeImage(decoded.image, to: output.appendingPathComponent(preview), type: .jpeg) {
                row["preview"] = preview
            }

            row["scalar"] = analysis(await analyzer.analyze(decoded, configuration: configuration))
            let start = ContinuousClock.now
            let result = await analyzer.analyzeWithFocusMask(decoded, configuration: configuration)
            row["combinedMilliseconds"] = elapsed(start)
            row["combined"] = analysis(result)
            let evidence = result.breakdown?.focusEvidence
            let reused = await analyzer.focusMask(for: decoded, configuration: configuration, evidence: evidence)
            let fresh = await analyzer.focusMask(for: decoded, configuration: configuration)
            var globalConfig = configuration
            globalConfig.isolateMaskToSubject = false
            let global = await analyzer.focusMask(for: decoded, configuration: globalConfig)
            var rawConfig = configuration
            rawConfig.showRawLaplacian = true
            let raw = await analyzer.focusMask(for: decoded, configuration: rawConfig, evidence: evidence)
            row["masks"] = [
                "combined": maskOutcome(result.focusMask, output: output, name: item.id + "-combined"),
                "reused": maskOutcome(reused, output: output, name: item.id + "-reused"),
                "fresh": maskOutcome(fresh, output: output, name: item.id + "-fresh"),
                "global": maskOutcome(global, output: output, name: item.id + "-global"),
                "raw": maskOutcome(raw, output: output, name: item.id + "-raw")
            ]
            row["suppliedEvidence"] = evidence != nil
            row["faces"] = await outcome { try await encoded(faces.analyze(decoded.image)) }
            row["animals"] = await outcome {
                try AnimalCloseUpDetector.regions(in: decoded.image).map {
                    ["kind": String(describing: $0.kind), "bounds": rect($0.bounds)]
                }
            }
            do {
                let feature = try await features.featurePrint(for: decoded.image)
                let reference = burstReferences[item.burst] ?? (item.id, feature)
                if !item.burst.isEmpty { burstReferences[item.burst] = reference }
                row["featurePrint"] = [
                    "status": "ok", "revision": feature.revision,
                    "representationVersion": feature.representationVersion,
                    "payloadBytes": feature.payload.count,
                    "reference": reference.id,
                    "distance": json(try features.distance(from: reference.print, to: feature))
                ]
            } catch {
                row["featurePrint"] = ["status": "error", "error": String(describing: error)]
            }
            rows.append(row)
        }
        let report: [String: Any] = [
            "descriptor": try encoded(PhotoAnalyzer.sharpnessDescriptor(for: configuration)),
            "batchStatus": batch == nil ? "unavailable" : "ok",
            "batchMilliseconds": batchMilliseconds,
            "calibration": calibrationResult, "images": rows
        ]
        let data = try JSONSerialization.data(withJSONObject: jsonSafe(report), options: [.sortedKeys])
        try data.write(to: output.appendingPathComponent("analysis.json"), options: .atomic)
    }
}

func breakdown(_ b: SharpnessBreakdown) -> [String: Any] {
    [
        "finalScore": b.finalScore,
        "globalScore": json(b.globalScore),
        "subjectScore": json(b.subjectScore),
        "afPointScore": json(b.afPointScore),
        "blurGateSigma": b.blurGateSigma,
        "subjectLabel": json(b.subjectLabel),
        "subjectConfidence": json(b.subjectConfidence),
        "focusFailureKind": b.focusFailureKind.rawValue,
        "focusMaskRegionSource": json(b.focusMaskRegionSource?.rawValue),
        "focusMaskVisualThreshold": json(b.focusMaskVisualThreshold),
        "focusEvidence": json(b.focusEvidence.map(focusEvidence)),
    ]
}

func focusEvidence(_ e: FocusEvidence) -> [String: Any] {
    [
        "winningRegion": e.winningRegion.rawValue,
        "afCenterScore": json(e.afCenterScore),
        "afNeighborhoodScore": json(e.afNeighborhoodScore),
        "effectiveVisualThreshold": json(e.effectiveVisualThreshold),
        "maskCoverage": json(e.maskCoverage),
        "relaxedForVisibility": e.relaxedForVisibility,
        "visualizedRegion": json(e.visualizedRegion?.rawValue),
        "afDistanceFromCentroid": json(e.afDistanceFromCentroid),
        "patchRankings": e.patchRankings.map(patch),
        "overlayStyle": json(e.overlayStyle?.rawValue),
        "focusEvidenceConfidence": json(e.focusEvidenceConfidence?.rawValue),
        "focusEvidenceConfidenceReason": json(e.focusEvidenceConfidenceReason),
        "spatialAlignmentScore": json(e.spatialAlignmentScore),
        "localPatchDominance": json(e.localPatchDominance),
        "silhouettePenaltyApplied": e.silhouettePenaltyApplied,
        "scoringAFLocalPatchScore": json(e.scoringAFLocalPatchScore),
        "scoringSubjectInteriorPatchScore": json(e.scoringSubjectInteriorPatchScore),
        "scoringLocalDetailScore": json(e.scoringLocalDetailScore),
        "saliencyCandidateCount": e.saliencyCandidateCount,
        "winningSaliencyRect": rect(e.winningSaliencyRect),
        "saliencySelectionReason": json(e.saliencySelectionReason),
    ]
}

func patch(_ p: FocusPatchRanking) -> [String: Any] {
    [
        "normalizedRect": rect(p.normalizedRect),
        "robustTailScore": p.robustTailScore,
        "microContrast": p.microContrast,
        "coverage": p.coverage,
        "distanceToAF": json(p.distanceToAF),
        "silhouetteFraction": p.silhouetteFraction,
        "ringDetailScore": p.ringDetailScore,
        "compactDetailScore": p.compactDetailScore,
        "linearEdgePenalty": p.linearEdgePenalty,
        "belowAFPenalty": p.belowAFPenalty,
        "eyeHeadHeuristicAdjustment": p.eyeHeadHeuristicAdjustment,
        "compositeScore": p.compositeScore,
        "containsAFPoint": p.containsAFPoint,
    ]
}
