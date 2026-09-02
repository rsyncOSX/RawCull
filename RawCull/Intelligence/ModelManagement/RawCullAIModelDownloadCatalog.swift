import CryptoKit
import Foundation

/// Stable identifiers for optional model bundles that RawCull can manage.
nonisolated enum RawCullAIModelDownloadID: String, CaseIterable, Codable, Identifiable, Sendable {
    case clipDataComp = "clip-datacomp"
    case clipOpenAI = "clip-openai"
    case efficientSAM = "efficient-sam"
    case sam3

    var id: String {
        rawValue
    }

    var clipModel: RawCullCLIPModel? {
        switch self {
        case .clipDataComp: .dataComp
        case .clipOpenAI: .openAI
        case .efficientSAM, .sam3: nil
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
                assetPackID: "no.blogspot.RawCull.models.clip-datacomp",
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
                expectedArchiveSHA256: "cf433dcd199b44635a4ff0260bd8e79177e4907a4cfcb2f72043066b8cbe4ef7",
                downloadByteCount: 282_966_632,
                installedByteCount: 307_801_147,
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
                id: .clipOpenAI,
                displayName: "OpenAI CLIP",
                purpose: "Image similarity, burst grouping, and semantic search.",
                publisher: "OpenAI",
                modelVersion: "ViT-B/32",
                upstreamRevision: "3d74acf9a28c67741b2f4f2ea7635f0aaf6f0268",
                resourceName: "CLIP-OpenAI",
                assetPackID: "no.blogspot.RawCull.models.clip-openai",
                assetPackModelPath: "Models/CLIP-OpenAI",
                upstreamSourceURL: requiredURL(
                    "https://huggingface.co/openai/clip-vit-base-patch32",
                ),
                modelCardURL: requiredURL(
                    "https://huggingface.co/openai/clip-vit-base-patch32",
                ),
                conversionInformationURL: nil,
                expectedArchiveSHA256: "e9181157c2d4012db2e6478949488f9906696a4ed78ecaa10235d9762621136c",
                downloadByteCount: 282_866_068,
                installedByteCount: nil,
                licence: RawCullAIModelLicenceDescriptor(
                    name: "MIT License",
                    version: nil,
                    summary: "The OpenAI CLIP copyright and permission notice must accompany redistributed copies.",
                    completeTextURL: requiredURL(
                        "https://github.com/openai/CLIP/blob/main/LICENSE",
                    ),
                    bundledTextResourceName: "OpenAI-CLIP-Tokenizer-MIT",
                    textSHA256: "893951b3bf94db8df1b13e05da5cdeb499400960e4d44a3962a8b33ed0b4f28e",
                    requiresExplicitAcceptance: false,
                ),
                releaseReadiness: .ready,
            ),
            RawCullAIModelDownloadDescriptor(
                id: .efficientSAM,
                displayName: "EfficientSAM",
                purpose: "Local subject segmentation for Deep Review.",
                publisher: "Y. Xiong et al.",
                modelVersion: "EfficientSAM-Ti, float16, 8×8 point grid",
                upstreamRevision: "d525f622e6f640acf5a0fc37c7ca1f243da5bde0",
                resourceName: "EfficientSAM",
                assetPackID: "no.blogspot.RawCull.models.efficient-sam",
                assetPackModelPath: "Models/EfficientSAM",
                upstreamSourceURL: requiredURL(
                    "https://github.com/yformer/EfficientSAM/tree/d525f622e6f640acf5a0fc37c7ca1f243da5bde0",
                ),
                modelCardURL: requiredURL(
                    "https://huggingface.co/merve/EfficientSAM/tree/38bb0b55425abf62274ba4a8c51249e3d7298b70",
                ),
                conversionInformationURL: requiredURL(
                    "https://github.com/apple/coreai-models/tree/bffc38fe48f50e4e962ac9772b64a5b55a605286/models/efficient-sam",
                ),
                expectedArchiveSHA256: nil,
                downloadByteCount: nil,
                installedByteCount: nil,
                licence: RawCullAIModelLicenceDescriptor(
                    name: "Apache License 2.0",
                    version: "2.0",
                    summary: "EfficientSAM is distributed under Apache License 2.0; redistributed copies must include the licence and preserve applicable notices.",
                    completeTextURL: requiredURL(
                        "https://github.com/yformer/EfficientSAM/blob/d525f622e6f640acf5a0fc37c7ca1f243da5bde0/LICENSE",
                    ),
                    bundledTextResourceName: "EfficientSAM-Apache-2.0",
                    textSHA256: "c71d239df91726fc519c6eb72d318ec65820627232b2f796219e87dcf35d0ab4",
                    requiresExplicitAcceptance: false,
                ),
                releaseReadiness: .blocked(
                    reason: "The source, checkpoint, conversion recipe, and licence are recorded, but the final converted bundle fingerprint and generated asset-pack archive size and SHA-256 have not been recorded or published.",
                ),
            ),
            RawCullAIModelDownloadDescriptor(
                id: .sam3,
                displayName: "Meta SAM 3",
                purpose: "Local subject segmentation for Deep Review.",
                publisher: "Meta",
                modelVersion: "SAM 3",
                upstreamRevision: "3c879f39826c281e95690f02c7821c4de09afae7",
                resourceName: "SAM3",
                assetPackID: "no.blogspot.RawCull.models.sam3",
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
                expectedArchiveSHA256: "dd0adc697060129435d4a70515011a37f547e1ad7cd530d943341bf3ca9184a9",
                downloadByteCount: 1_542_689_157,
                installedByteCount: 1_667_576_486,
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
