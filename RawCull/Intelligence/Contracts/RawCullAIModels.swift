import Foundation
import PhotoAIContracts

/// The mutually exclusive CLIP model choices supported by RawCull.
///
/// PhotoAIKit reads each bundle's metadata and configures the corresponding
/// OpenAI or DataComp runtime. RawCull owns only installation and selection.
nonisolated enum RawCullCLIPModel: String, CaseIterable, Hashable, Identifiable, Sendable {
    case dataComp = "data-comp"
    case openAI = "openai"

    static let defaultSelection = Self.openAI

    var id: String {
        rawValue
    }

    var displayName: String {
        switch self {
        case .dataComp: "DataComp"
        case .openAI: "OpenAI"
        }
    }

    var resourceName: String {
        switch self {
        case .dataComp: "CLIP-DataComp"
        case .openAI: "CLIP-OpenAI"
        }
    }
}

/// The mutually exclusive subject-segmentation backends available to Deep Review.
nonisolated enum RawCullSegmentationModel: String, CaseIterable, Hashable, Identifiable, Sendable {
    case sam3
    case efficientSAM = "efficient-sam"

    static let defaultSelection = Self.sam3

    var id: String {
        rawValue
    }

    var displayName: String {
        switch self {
        case .sam3: "SAM 3"
        case .efficientSAM: "EfficientSAM"
        }
    }

    var resourceName: String {
        switch self {
        case .sam3: "SAM3"
        case .efficientSAM: "EfficientSAM"
        }
    }
}

/// RawCull-owned locations used by the AI integration boundary.
///
/// Existing application support and cache roots stay under RawCull's canonical
/// names so the AI branch does not create a second application data namespace.
nonisolated struct RawCullAIPaths: Equatable, Sendable {
    let applicationSupportDirectory: URL
    let modelsDirectory: URL
    let sam3ModelDirectory: URL
    let efficientSAMModelDirectory: URL
    let clipDataCompModelDirectory: URL
    let clipOpenAIModelDirectory: URL
    let modelLicenceAcceptancesURL: URL
    let subjectMaskDirectory: URL
    let burstAnalysisDirectory: URL

    init(
        applicationSupportRoot: URL,
        cachesRoot: URL,
    ) {
        let applicationSupportDirectory = applicationSupportRoot
            .appendingPathComponent("RawCull", isDirectory: true)
        let modelsDirectory = applicationSupportDirectory
            .appendingPathComponent("Models", isDirectory: true)

        self.applicationSupportDirectory = applicationSupportDirectory
        self.modelsDirectory = modelsDirectory
        self.sam3ModelDirectory = modelsDirectory
            .appendingPathComponent("SAM3", isDirectory: true)
        self.efficientSAMModelDirectory = modelsDirectory
            .appendingPathComponent("EfficientSAM", isDirectory: true)
        self.clipDataCompModelDirectory = modelsDirectory
            .appendingPathComponent(
                RawCullCLIPModel.dataComp.resourceName,
                isDirectory: true,
            )
        self.clipOpenAIModelDirectory = modelsDirectory
            .appendingPathComponent(
                RawCullCLIPModel.openAI.resourceName,
                isDirectory: true,
            )
        self.modelLicenceAcceptancesURL = applicationSupportDirectory
            .appendingPathComponent("ModelLicenceAcceptances.json")
        self.subjectMaskDirectory = cachesRoot
            .appendingPathComponent("no.blogspot.RawCull", isDirectory: true)
            .appendingPathComponent("SAM3Masks", isDirectory: true)
        self.burstAnalysisDirectory = applicationSupportDirectory
            .appendingPathComponent("BurstAnalysis", isDirectory: true)
    }

    static func live(fileManager: FileManager = .default) -> Self {
        let applicationSupportRoot = fileManager.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
        ).first ?? fileManager.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support", isDirectory: true)
        let cachesRoot = fileManager.urls(
            for: .cachesDirectory,
            in: .userDomainMask,
        ).first ?? fileManager.temporaryDirectory

        return Self(
            applicationSupportRoot: applicationSupportRoot,
            cachesRoot: cachesRoot,
        )
    }

    func clipModelDirectory(for model: RawCullCLIPModel) -> URL {
        switch model {
        case .dataComp: clipDataCompModelDirectory
        case .openAI: clipOpenAIModelDirectory
        }
    }
}

/// A common, structured capability state for model resources and host services.
nonisolated enum RawCullAICapabilityStatus: Equatable, Sendable {
    case checking(expectedLocations: [URL])
    case available(location: URL?)
    case missing(expectedLocations: [URL])
    case invalid(location: URL?, reason: String)
    case unavailable(reason: String)

    var isAvailable: Bool {
        if case .available = self {
            true
        } else {
            false
        }
    }
}

/// Explicit semantic-search readiness.
///
/// This is separate from the CLIP model status because Vision remains a valid
/// image-similarity backend while text search specifically requires a
/// validated CLIP provider with text support.
nonisolated enum RawCullSemanticSearchCapabilityStatus: Equatable, Sendable {
    case checking(expectedLocations: [URL])
    case ready(
        location: URL?,
        backend: SimilarityBackendDescriptor,
    )
    case unavailable(
        reason: String,
        expectedLocations: [URL],
    )
    case failed(
        location: URL?,
        reason: String,
    )
}

/// The Phase 1 readiness surface described by `doc/futureaiintegration.md`.
nonisolated struct RawCullAICapabilities: Equatable, Sendable {
    let segmentationModels: [RawCullSegmentationModel: RawCullAICapabilityStatus]
    let clipModels: [RawCullCLIPModel: RawCullAICapabilityStatus]
    let semanticSearchByCLIPModel: [
        RawCullCLIPModel: RawCullSemanticSearchCapabilityStatus
    ]
    let visionFeaturePrint: RawCullAICapabilityStatus
    let subjectMaskStorage: RawCullAICapabilityStatus
    let inProcessMaskGeneration: RawCullAICapabilityStatus

    var sam3Model: RawCullAICapabilityStatus {
        segmentationModelStatus(for: .sam3)
    }

    func segmentationModelStatus(
        for model: RawCullSegmentationModel,
    ) -> RawCullAICapabilityStatus {
        segmentationModels[model] ?? .unavailable(
            reason: "\(model.displayName) capability was not configured.",
        )
    }

    func clipModelStatus(
        for model: RawCullCLIPModel,
    ) -> RawCullAICapabilityStatus {
        clipModels[model] ?? .unavailable(
            reason: "\(model.displayName) CLIP capability was not configured.",
        )
    }

    func semanticSearchStatus(
        for model: RawCullCLIPModel,
    ) -> RawCullSemanticSearchCapabilityStatus {
        semanticSearchByCLIPModel[model] ?? .unavailable(
            reason: "Semantic search requires a valid \(model.displayName) CLIP model.",
            expectedLocations: [],
        )
    }
}

nonisolated enum RawCullSavedBurstBackend: Equatable, Sendable {
    case noSavedData
    case clip
    case visionFeaturePrint
    case visionFallback
    case mixed
}

/// Read-only descriptor evidence shown in Settings. Counts come from persisted
/// PhotoAIKit artifacts rather than the not-yet-connected backend preference.
nonisolated struct RawCullSavedBurstEvidence: Equatable, Sendable {
    let cacheFileCount: Int
    let decodedCatalogCount: Int
    let burstGroupCount: Int
    let clipEmbeddingCount: Int
    let visionEmbeddingCount: Int
    let clipFallbackCatalogCount: Int
    let skippedCacheFileCount: Int

    static let empty = Self(
        cacheFileCount: 0,
        decodedCatalogCount: 0,
        burstGroupCount: 0,
        clipEmbeddingCount: 0,
        visionEmbeddingCount: 0,
        clipFallbackCatalogCount: 0,
        skippedCacheFileCount: 0,
    )

    var totalEmbeddingCount: Int {
        clipEmbeddingCount + visionEmbeddingCount
    }

    var backend: RawCullSavedBurstBackend {
        guard totalEmbeddingCount > 0 else { return .noSavedData }
        if clipEmbeddingCount > 0, visionEmbeddingCount > 0 {
            return .mixed
        }
        if clipEmbeddingCount > 0 {
            return .clip
        }
        return clipFallbackCatalogCount > 0 ? .visionFallback : .visionFeaturePrint
    }
}

nonisolated enum RawCullSavedBurstEvidenceScanResult: Equatable, Sendable {
    case success(RawCullSavedBurstEvidence)
    case failure(reason: String)
}

/// Inspects RawCull's current burst cache without changing it.
nonisolated struct RawCullSavedBurstEvidenceScanner: Sendable {
    let cacheDirectory: URL

    @concurrent
    func scan() async throws -> RawCullSavedBurstEvidenceScanResult {
        try Task.checkCancellation()
        let cacheFiles: [URL]
        do {
            cacheFiles = try FileManager.default.contentsOfDirectory(
                at: cacheDirectory,
                includingPropertiesForKeys: nil,
                options: [.skipsHiddenFiles],
            )
            .filter { $0.pathExtension.lowercased() == "json" }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
        } catch let error as CocoaError where error.code == .fileReadNoSuchFile {
            return .success(.empty)
        } catch {
            return .failure(reason: String(describing: error))
        }

        var decodedCatalogCount = 0
        var burstGroupCount = 0
        var clipEmbeddingCount = 0
        var visionEmbeddingCount = 0
        var clipFallbackCatalogCount = 0
        var skippedCacheFileCount = 0

        for url in cacheFiles {
            try Task.checkCancellation()
            do {
                let data = try Data(contentsOf: url, options: .mappedIfSafe)
                try Task.checkCancellation()
                let probe = try JSONDecoder().decode(
                    RawCullSavedBurstCacheProbe.self,
                    from: data,
                )
                guard probe.schemaVersion == BurstAnalysisCache.schemaVersion else {
                    skippedCacheFileCount += 1
                    continue
                }

                var catalogClipCount = 0
                var catalogVisionCount = 0
                for (index, artifact) in probe.embeddings.values.enumerated() {
                    if index & 0x3F == 0 {
                        try Task.checkCancellation()
                    }
                    switch artifact.descriptor.backend {
                    case "clip": catalogClipCount += 1
                    case "vision-feature-print": catalogVisionCount += 1
                    default: continue
                    }
                }
                decodedCatalogCount += 1
                clipEmbeddingCount += catalogClipCount
                visionEmbeddingCount += catalogVisionCount
                if probe.similaritySignature.backendDescriptor.backend == "clip",
                   catalogClipCount == 0,
                   catalogVisionCount > 0 {
                    clipFallbackCatalogCount += 1
                }
                burstGroupCount += probe.groups.count { $0.fileIDs.count > 1 }
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                skippedCacheFileCount += 1
            }
        }

        return .success(
            RawCullSavedBurstEvidence(
                cacheFileCount: cacheFiles.count,
                decodedCatalogCount: decodedCatalogCount,
                burstGroupCount: burstGroupCount,
                clipEmbeddingCount: clipEmbeddingCount,
                visionEmbeddingCount: visionEmbeddingCount,
                clipFallbackCatalogCount: clipFallbackCatalogCount,
                skippedCacheFileCount: skippedCacheFileCount,
            ),
        )
    }
}

private nonisolated struct RawCullSavedBurstCacheProbe: Decodable {
    let schemaVersion: Int
    let similaritySignature: BurstSimilaritySignature
    let embeddings: [UUID: SimilarityArtifact]
    let groups: [RawCullSavedBurstGroupProbe]
}

private nonisolated struct RawCullSavedBurstGroupProbe: Decodable {
    let fileIDs: [UUID]
}
