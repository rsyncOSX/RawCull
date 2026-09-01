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
    static let includeOpenAICLIP = true
    static let includeDataCompCLIP = true
    static let includeEfficientSAM = true
    static let includeSAM3 = false

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
        if includeSAM3 {
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

    static let production: Self = {
        let models = [
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
                conversionInformationURL: nil,
                expectedArchiveSHA256: "cf433dcd199b44635a4ff0260bd8e79177e4907a4cfcb2f72043066b8cbe4ef7",
                downloadByteCount: 282_966_632,
                installedByteCount: nil,
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
                id: .sam3,
                displayName: "Meta SAM 3",
                purpose: "Local subject segmentation for Deep Review.",
                publisher: "Meta",
                modelVersion: "SAM 3",
                upstreamRevision: nil,
                resourceName: "SAM3",
                assetPackID: "no.blogspot.RawCull.models.sam3",
                assetPackModelPath: "Models/SAM3",
                upstreamSourceURL: requiredURL(
                    "https://huggingface.co/facebook/sam3",
                ),
                modelCardURL: requiredURL(
                    "https://huggingface.co/facebook/sam3",
                ),
                conversionInformationURL: nil,
                expectedArchiveSHA256: nil,
                downloadByteCount: nil,
                installedByteCount: nil,
                licence: RawCullAIModelLicenceDescriptor(
                    name: "SAM License",
                    version: "November 19, 2025",
                    summary: "The SAM License contains redistribution, prohibited-use, trade-control, termination, warranty, liability, and indemnification terms.",
                    completeTextURL: requiredURL(
                        "https://huggingface.co/facebook/sam3/blob/main/LICENSE",
                    ),
                    bundledTextResourceName: "SAM3-SAM-License-2025-11-19",
                    textSHA256: "b08db9d32c687054e99cbd41eb1dad19c76936dfb9e2b58e186a01204d8be9ab",
                    requiresExplicitAcceptance: true,
                ),
                releaseReadiness: .blocked(
                    reason: "The complete SAM License is packaged, but redistribution remains disabled until RawCull confirms that an ungated converted download is compatible with Meta's licence and the official gated access conditions.",
                ),
            )
        ]
        return Self(
            models: models.filter {
                RawCullAIModelInclusion.downloadIDs.contains($0.id)
            },
        )
    }()

    private static func requiredURL(_ string: String) -> URL {
        guard let url = URL(string: string) else {
            preconditionFailure("Invalid built-in model catalogue URL: \(string)")
        }
        return url
    }
}
