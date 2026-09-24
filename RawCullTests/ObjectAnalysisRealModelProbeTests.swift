import CoreAISAM3Backend
import Foundation
import PhotoAIStorage
import PhotoAIWorkflows
@testable import RawCull
import RawCullCore
import Testing

@Suite("Local object model probe")
struct ObjectAnalysisRealModelProbeTests {
    @MainActor
    @Test(.enabled(if: ProcessInfo.processInfo.environment["OBJECT_PROBE_IMAGE"] != nil))
    func probeOnePhoto() async throws {
        let environment = ProcessInfo.processInfo.environment
        let imagePath = try #require(environment["OBJECT_PROBE_IMAGE"])
        let qwenPath = try #require(environment["OBJECT_PROBE_QWEN"])
        let samPath = try #require(environment["OBJECT_PROBE_SAM3"])
        let imageURL = URL(fileURLWithPath: imagePath)
        let attributes = try FileManager.default.attributesOfItem(atPath: imagePath)
        let file = FileItem(
            id: UUID(), url: imageURL, name: imageURL.lastPathComponent,
            size: (attributes[.size] as? NSNumber)?.int64Value ?? 0,
            dateModified: (attributes[.modificationDate] as? Date) ?? .distantPast,
            exifData: nil, afFocusNormalized: nil,
        )
        let inference = QwenInferenceRuntime()
        let qwenStatus = await inference.validate(url: URL(fileURLWithPath: qwenPath))
        #expect(qwenStatus.isAvailable)
        let provider = try CoreAISAM3Provider(modelBundleURL: URL(fileURLWithPath: samPath))
        let store = ObjectMaskMemoryStore()
        let segmentation = try ObjectSegmentationService(provider: provider, stores: [store], maxSide: 4_320)
        for mode in [ObjectDiscoveryMode.automatic, .specificConcepts] {
            let feature = RawCullObjectAnalysisFeature(inference: inference, maskStores: [store])
            feature.install(segmentation: segmentation, qwenStatus: qwenStatus)
            feature.discoveryMode = mode
            feature.manualConceptText = "bird"
            let start = ContinuousClock.now
            await feature.analyze([file])
            let elapsed = start.duration(to: .now)
            let result = try #require(feature.results.first)
            print("OBJECT PROBE file=\(file.name) mode=\(mode.rawValue) concepts=\(result.concepts) instances=\(result.instances.count) structured=\(result.assessment != nil) confidence=\(result.assessment?.confidence.description ?? "nil") failure=\(result.failure ?? "nil") elapsed=\(elapsed)")
        }
    }
}
