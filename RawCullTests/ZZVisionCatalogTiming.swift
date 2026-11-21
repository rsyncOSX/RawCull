// TEMPORARY — not for commit. Opt-in timing of concurrent Vision work on a real catalog.
import Foundation
import PhotoAIContracts
@testable import RawCull
import RawCullCore
import Testing

@Suite("ZZ Vision catalog timing", .serialized)
struct ZZVisionCatalogTiming {
    @Test(.enabled(if: ProcessInfo.processInfo.environment["ZZ_VISION_CATALOG"] != nil),
          .timeLimit(.minutes(60)))
    func timing() async throws {
        let env = ProcessInfo.processInfo.environment
        let catalog = URL(fileURLWithPath: env["ZZ_VISION_CATALOG"]!, isDirectory: true)
        let output = URL(fileURLWithPath: env["ZZ_VISION_OUTPUT"]!)
        let files = try FileManager.default.contentsOfDirectory(at: catalog, includingPropertiesForKeys: nil)
            .filter { $0.pathExtension.lowercased() == "arw" }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
        var lines = ["files: \(files.count)", "cores: \(ProcessInfo.processInfo.activeProcessorCount)",
                     "cap (visionSafeScoringTaskLimit): \(SharpnessScoringModel.visionSafeScoringTaskLimit)"]
        func log(_ line: String) {
            lines.append(line)
            print("ZZ: \(line)")
            try? lines.joined(separator: "\n").write(to: output, atomically: true, encoding: .utf8)
        }

        let model = await SharpnessScoringModel()
        let config = await model.effectiveFocusConfig
        let pixelSize = await model.effectiveThumbnailMaxPixelSize
        let source = await model.scoringSource
        log("sharpness: quality fast, \(pixelSize) px, source \(source.title)")

        var requests: [RawCullPhotoAnalysisRequest<URL>] = []
        for url in files {
            let metadata = await RawParserKitImageLoader.shared.fileMetadata(for: url)
            requests.append(.init(id: url, file: .init(
                url: url, iso: metadata?.exifMetadata.isoValue ?? 400,
                aperture: metadata?.exifMetadata.apertureValue,
                normalizedAFPoint: metadata?.focusPoint,
            )))
        }
        let sources = files.map { AIImageSource(id: UUID(), url: $0, displayName: $0.lastPathComponent) }
        let similarityPixels = SimilarityScoringModel.embeddingThumbnailMaxPixelSize
        log("similarity: Vision feature print, \(similarityPixels) px, decode concurrency \(RawCullVisionSimilarityService.defaultConcurrencyLimit)")

        func sharpness(_ tasks: Int) async -> (seconds: Double, scores: [URL: Float]) {
            let start = Date()
            let results = await RawCullPhotoAnalysisAdapter().analyzeBatch(
                requests: requests, configuration: config, maximumPixelSize: pixelSize,
                source: source, maximumConcurrentTasks: tasks,
            ) ?? []
            var scores: [URL: Float] = [:]
            for result in results { if let score = result.score { scores[result.id] = score } }
            return (Date().timeIntervalSince(start), scores)
        }
        func similarity() async throws -> (seconds: Double, count: Int, failures: Int) {
            let start = Date()
            let out = try await RawCullVisionSimilarityService().index(sources: sources, maxPixelSize: similarityPixels)
            return (Date().timeIntervalSince(start), out.artifacts.count, out.failures.count)
        }
        func fmt(_ s: Double) -> String { String(format: "%.1f s", s) }

        let warm = await sharpness(5)
        log("warm-up sharpness tasks=5: \(fmt(warm.seconds)), scored \(warm.scores.count)")
        let warmSim = try await similarity()
        log("warm-up similarity: \(fmt(warmSim.seconds)), artifacts \(warmSim.count), failures \(warmSim.failures)")

        var reference: [URL: Float]?
        for round in 1 ... 2 {
            for tasks in [5, 6] {
                let s = await sharpness(tasks)
                log("round \(round) sharpness alone tasks=\(tasks): \(fmt(s.seconds)), scored \(s.scores.count)")
                if let reference { log("  scores identical to first run: \(reference == s.scores)") } else { reference = s.scores }
            }
            let sim = try await similarity()
            log("round \(round) similarity alone: \(fmt(sim.seconds)), artifacts \(sim.count), failures \(sim.failures)")
            for tasks in [5, 6] {
                let start = Date()
                async let s = sharpness(tasks)
                async let i = similarity()
                let (sv, iv) = try await (s, i)
                log("round \(round) together tasks=\(tasks): wall \(fmt(Date().timeIntervalSince(start))) (sharpness \(fmt(sv.seconds)), similarity \(fmt(iv.seconds)), artifacts \(iv.count))")
                log("  scores identical to first run: \(reference == sv.scores)")
            }
        }

        let cores = ProcessInfo.processInfo.activeProcessorCount
        let start = Date()
        async let s = sharpness(cores)
        async let i = similarity()
        let (sv, iv) = try await (s, i)
        log("stress together tasks=\(cores) (cores): wall \(fmt(Date().timeIntervalSince(start))) (sharpness \(fmt(sv.seconds)), similarity \(fmt(iv.seconds)), artifacts \(iv.count))")
        log("  scores identical to first run: \(reference == sv.scores)")
        log("done")
    }
}
