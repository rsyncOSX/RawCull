import CryptoKit
import Foundation

/// Stable identifiers for optional model bundles that RawCull can manage.
nonisolated enum RawCullAIModelDownloadID: String, CaseIterable, Codable, Identifiable, Sendable {
    case clipDataComp = "clip-datacomp"
    case clipOpenAI = "clip-openai"
    case efficientSAM = "efficient-sam"
    case sam3
    case qwen3VL2B = "qwen3-vl-2b"

    var id: String {
        rawValue
    }

    var clipModel: RawCullCLIPModel? {
        switch self {
        case .clipDataComp: .dataComp
        case .clipOpenAI: .openAI
        case .efficientSAM, .sam3, .qwen3VL2B: nil
        }
    }
}

/// Code-only switches controlling which AI models RawCull presents in Settings
/// and in the model-download sheet.
nonisolated enum RawCullAIModelInclusion {
    static let includeOpenAICLIP = false
    static let includeDataCompCLIP = true
    static let includeEfficientSAM = false
    static let includeSAM3 = true
    static let includeEfficientSAMDownload = false
    static let includeSAM3Download = true
    static let includeQwen3VL2BDownload = true

    static var clipModels: [RawCullCLIPModel] {
        RawCullCLIPModel.allCases.filter { model in
            switch model {
            case .dataComp: includeDataCompCLIP
            case .openAI: includeOpenAICLIP
            }
        }
    }

    static var segmentationModels: [RawCullSegmentationModel] {
        RawCullSegmentationModel.allCases.filter { model in
            switch model {
            case .sam3: includeSAM3
            case .efficientSAM: includeEfficientSAM
            }
        }
    }

    fileprivate static var downloadIDs: Set<RawCullAIModelDownloadID> {
        var ids: Set<RawCullAIModelDownloadID> = []
        if includeDataCompCLIP {
            ids.insert(.clipDataComp)
        }
        if includeOpenAICLIP {
            ids.insert(.clipOpenAI)
        }
        if includeEfficientSAMDownload {
            ids.insert(.efficientSAM)
        }
        if includeSAM3Download {
            ids.insert(.sam3)
        }
        if includeQwen3VL2BDownload {
            ids.insert(.qwen3VL2B)
        }
        return ids
    }
}

nonisolated struct RawCullAIModelLicenceDescriptor: Equatable, Sendable {
    let name: String
    let version: String?
    let summary: LocalizedStringResource
    let completeTextURL: URL
    let bundledTextResourceName: String?
    let textSHA256: String?
    let requiresExplicitAcceptance: Bool

    func verifiedBundledText(in bundle: Bundle) -> String? {
        guard let bundledTextResourceName,
              let textSHA256,
              let url = bundle.url(
                  forResource: bundledTextResourceName,
                  withExtension: "txt",
              ),
              let data = try? Data(contentsOf: url),
              SHA256.hash(data: data)
              .map({ String(format: "%02x", $0) })
              .joined() == textSHA256
        else {
            return nil
        }
        return String(data: data, encoding: .utf8)
    }
}

nonisolated enum RawCullAIModelReleaseReadiness: Equatable, Sendable {
    case ready
    case blocked(reason: LocalizedStringResource)

    var isReady: Bool {
        if case .ready = self {
            true
        } else {
            false
        }
    }
}

/// Distribution metadata owned by RawCull rather than by the download host.
///
/// Keeping licence and provenance metadata in the application means the same
/// review flow works for both self-hosted and Apple-hosted asset packs.
nonisolated struct RawCullAIModelDownloadDescriptor: Equatable, Identifiable, Sendable {
    let id: RawCullAIModelDownloadID
    let displayName: String
    let purpose: LocalizedStringResource
    let publisher: String
    let modelVersion: String
    let upstreamRevision: String?
    let resourceName: String
    let assetPackID: String
    let assetPackModelPath: String
    let upstreamSourceURL: URL
    let modelCardURL: URL
    let conversionInformationURL: URL?
    let expectedArchiveSHA256: String?
    let downloadByteCount: Int64?
    let installedByteCount: Int64?
    let licence: RawCullAIModelLicenceDescriptor
    let releaseReadiness: RawCullAIModelReleaseReadiness
}

nonisolated struct RawCullAIModelDownloadCatalog: Equatable, Sendable {
    let models: [RawCullAIModelDownloadDescriptor]

    func descriptor(
        for id: RawCullAIModelDownloadID,
    ) -> RawCullAIModelDownloadDescriptor? {
        models.first { $0.id == id }
    }

    static let prepared = Self(
        models: [
            RawCullAIModelDownloadDescriptor(
                id: .clipDataComp,
                displayName: "DataComp CLIP",
                purpose: "Image similarity, burst grouping, and semantic search.",
                publisher: "LAION / OpenCLIP",
                modelVersion: "ViT-B/32 256px, datacomp_s34b_b86k",
                upstreamRevision: "4afec35ffe57a943d569ff7ee888061830164da8",
                resourceName: "CLIP-DataComp",
                assetPackID: "rawcull-clip-datacomp",
                assetPackModelPath: "Models/CLIP-DataComp",
                upstreamSourceURL: requiredURL(
                    "https://huggingface.co/laion/CLIP-ViT-B-32-256x256-DataComp-s34B-b86K/tree/4afec35ffe57a943d569ff7ee888061830164da8",
                ),
                modelCardURL: requiredURL(
                    "https://huggingface.co/laion/CLIP-ViT-B-32-256x256-DataComp-s34B-b86K",
                ),
                conversionInformationURL: requiredURL(
                    "https://github.com/apple/coreai-models/tree/bffc38fe48f50e4e962ac9772b64a5b55a605286/models/clip",
                ),
                expectedArchiveSHA256: "994939e74dbbe9844214d509267642939f5ddc535ae3bce4be36c8855bdfa600",
                downloadByteCount: 282_967_354,
                installedByteCount: 307_800_172,
                licence: RawCullAIModelLicenceDescriptor(
                    name: "MIT License",
                    version: nil,
                    summary: "The OpenCLIP/DataComp copyright and permission notice must accompany redistributed copies.",
                    completeTextURL: requiredURL(
                        "https://github.com/mlfoundations/open_clip/blob/main/LICENSE",
                    ),
                    bundledTextResourceName: "OpenCLIP-DataComp-MIT",
                    textSHA256: "6e355cc8399a572ed3db329d178a1188400fbbaed4397c28bd5b5fbac2696986",
                    requiresExplicitAcceptance: false,
                ),
                releaseReadiness: .ready,
            ),
            RawCullAIModelDownloadDescriptor(
                id: .sam3,
                displayName: "Meta SAM 3",
                purpose: "Local subject segmentation for Deep Review.",
                publisher: "Meta",
                modelVersion: "SAM 3",
                upstreamRevision: "3c879f39826c281e95690f02c7821c4de09afae7",
                resourceName: "SAM3",
                assetPackID: "rawcull-sam3",
                assetPackModelPath: "Models/SAM3",
                upstreamSourceURL: requiredURL(
                    "https://huggingface.co/facebook/sam3/tree/3c879f39826c281e95690f02c7821c4de09afae7",
                ),
                modelCardURL: requiredURL(
                    "https://huggingface.co/facebook/sam3/tree/3c879f39826c281e95690f02c7821c4de09afae7",
                ),
                conversionInformationURL: requiredURL(
                    "https://github.com/apple/coreai-models/tree/bffc38fe48f50e4e962ac9772b64a5b55a605286/models/sam3",
                ),
                expectedArchiveSHA256: "08c9a4f58242d6eecaa322d65521fd788589ea682aa92a5cea03fa1e2f2681d4",
                downloadByteCount: 1_542_689_931,
                installedByteCount: 1_667_570_378,
                licence: RawCullAIModelLicenceDescriptor(
                    name: "SAM License",
                    version: "November 19, 2025",
                    summary: "The SAM License contains redistribution, prohibited-use, trade-control, termination, warranty, liability, and indemnification terms.",
                    completeTextURL: requiredURL(
                        "https://huggingface.co/facebook/sam3/blob/3c879f39826c281e95690f02c7821c4de09afae7/LICENSE",
                    ),
                    bundledTextResourceName: "SAM3-SAM-License-2025-11-19",
                    textSHA256: "b08db9d32c687054e99cbd41eb1dad19c76936dfb9e2b58e186a01204d8be9ab",
                    requiresExplicitAcceptance: true,
                ),
                releaseReadiness: .ready,
            ),
            RawCullAIModelDownloadDescriptor(
                id: .qwen3VL2B,
                displayName: "Qwen3-VL-2B-Instruct",
                purpose: "Local vision-language photo analysis and assessment.",
                publisher: "Qwen Team / Alibaba Cloud",
                modelVersion: "Qwen3-VL-2B-Instruct",
                upstreamRevision: "78448d793a7eb2f7a987a1da76d464384aa1becd",
                resourceName: "Qwen",
                assetPackID: "rawcull-qwen3-vl-2b",
                assetPackModelPath: "Models/Qwen/qwen3_vl_2b",
                upstreamSourceURL: requiredURL(
                    "https://huggingface.co/Qwen/Qwen3-VL-2B-Instruct/tree/78448d793a7eb2f7a987a1da76d464384aa1becd",
                ),
                modelCardURL: requiredURL(
                    "https://huggingface.co/Qwen/Qwen3-VL-2B-Instruct",
                ),
                conversionInformationURL: requiredURL(
                    "https://github.com/apple/coreai-models",
                ),
                expectedArchiveSHA256: "115eebbfdff7cb688b26dd6e2dd6c110b3fce5d27f6d5e8f40f69192d1ca2364",
                downloadByteCount: 3_754_599_603,
                installedByteCount: 5_395_195_663,
                licence: RawCullAIModelLicenceDescriptor(
                    name: "Apache License 2.0",
                    version: "2.0",
                    summary: "Qwen3-VL-2B-Instruct is distributed under Apache License 2.0; redistributed copies must include the licence and preserve applicable notices.",
                    completeTextURL: requiredURL(
                        "https://huggingface.co/Qwen/Qwen3-VL-2B-Instruct/blob/78448d793a7eb2f7a987a1da76d464384aa1becd/LICENSE",
                    ),
                    bundledTextResourceName: "Qwen3-VL-Apache-2.0",
                    textSHA256: "c71d239df91726fc519c6eb72d318ec65820627232b2f796219e87dcf35d0ab4",
                    requiresExplicitAcceptance: false,
                ),
                releaseReadiness: .ready,
            )
        ],
    )

    static let production = Self(
        models: prepared.models.filter {
            RawCullAIModelInclusion.downloadIDs.contains($0.id)
        },
    )

    private static func requiredURL(_ string: String) -> URL {
        guard let url = URL(string: string) else {
            preconditionFailure("Invalid built-in model catalogue URL: \(string)")
        }
        return url
    }
}
