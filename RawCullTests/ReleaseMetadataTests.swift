import CryptoKit
import Foundation
import Testing

@Suite("Release metadata", .tags(.smoke))
struct ReleaseMetadataTests {
    @Test
    func `app and extension metadata are aligned for version 3`() throws {
        let project = try repositoryText("RawCull.xcodeproj/project.pbxproj")
        let appBlocks = buildSettingBlocks(
            in: project,
            bundleIdentifier: "no.blogspot.RawCull",
        )
        let extensionBlocks = buildSettingBlocks(
            in: project,
            bundleIdentifier: "no.blogspot.RawCull.ModelDownloader",
        )

        #expect(appBlocks.count == 2)
        #expect(extensionBlocks.count == 2)
        for block in appBlocks + extensionBlocks {
            #expect(buildSetting("MARKETING_VERSION", in: block) == "3.0.0")
            #expect(buildSetting("CURRENT_PROJECT_VERSION", in: block) == "303")
            #expect(buildSetting("MACOSX_DEPLOYMENT_TARGET", in: block) == "27.0")
            #expect(buildSetting("ENABLE_APP_SANDBOX", in: block) == "YES")
            #expect(buildSetting("ENABLE_HARDENED_RUNTIME", in: block) == "YES")
        }
        #expect(project.components(separatedBy: "ARCHS = arm64;").count - 1 == 2)
        #expect(!project.contains("MACOSX_DEPLOYMENT_TARGET = 26"))

        let appEntitlements = try propertyList("RawCull.entitlements")
        let extensionEntitlements = try propertyList(
            "RawCullModelDownloader/RawCullModelDownloader.entitlements",
        )
        for entitlements in [appEntitlements, extensionEntitlements] {
            #expect(entitlements["com.apple.security.app-sandbox"] as? Bool == true)
            #expect(
                entitlements["com.apple.security.application-groups"] as? [String]
                    == ["group.no.blogspot.RawCull.model-assets"],
            )
        }

        let appInfo = try propertyList("RawCull-Info.plist")
        #expect(appInfo["CFBundleShortVersionString"] as? String == "$(MARKETING_VERSION)")
        #expect(appInfo["CFBundleVersion"] as? String == "$(CURRENT_PROJECT_VERSION)")
        #expect(appInfo["LSMinimumSystemVersion"] as? String == "$(MACOSX_DEPLOYMENT_TARGET)")
        #expect(appInfo["BAAppGroupID"] as? String == "group.no.blogspot.RawCull.model-assets")
        #expect(
            appInfo["BAManifestURL"] as? String
                == "https://github.com/rsyncOSX/RawCull-AI-Models/releases/download/v1/manifest.json",
        )
        #expect(appInfo["BAUsesAppleHosting"] as? Bool == false)

        let about = try repositoryText("RawCull/Views/Tools/AboutRawCullView.swift")
        #expect(about.contains("CFBundleShortVersionString"))
        #expect(about.contains("CFBundleVersion"))
        #expect(about.contains("CLIP semantic search"))
        #expect(about.contains("SAM 3 Deep Review"))
        #expect(about.contains("Vision fallback"))
    }

    @Test
    func `README documents every exact resolved package pin`() throws {
        let resolvedData = try repositoryData(
            "RawCull.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved",
        )
        let resolved = try JSONDecoder().decode(ResolvedPackages.self, from: resolvedData)
        let tableRows = try repositoryText("README.md")
            .split(whereSeparator: \.isNewline)
            .map(String.init)
            .filter { $0.hasPrefix("|") }

        #expect(resolved.pins.count == 21)
        for pin in resolved.pins {
            let expectedPin = pin.state.version ?? pin.state.revision
            let matchingRows = tableRows.filter { row in
                row.contains("`\(pin.identity)`")
                    && row.contains("`\(expectedPin)`")
            }
            #expect(matchingRows.count == 1, "Missing or duplicate README row for \(pin.identity)")
        }
    }

    @Test
    func `model manifest catalog and destinations agree`() throws {
        let manifestData = try repositoryData("ModelAssets/manifest.template.json")
        let manifest = try JSONDecoder().decode(ModelManifest.self, from: manifestData)
        let expectedDestinations = [
            "no.blogspot.RawCull.models.clip-datacomp": "Models/CLIP-DataComp",
            "no.blogspot.RawCull.models.clip-openai": "Models/CLIP-OpenAI",
            "no.blogspot.RawCull.models.sam3": "Models/SAM3"
        ]
        var actualDestinations: [String: String] = [:]
        for assetPack in manifest.assetPacks {
            #expect(assetPack.fileSelectors.count == 1)
            let selector = try #require(assetPack.fileSelectors.first)
            actualDestinations[assetPack.assetPackID] = selector.directory.destination
        }

        #expect(actualDestinations == expectedDestinations)
        let catalog = try repositoryText(
            "RawCull/Model/AIIntegration/RawCullAIModelDownloadCatalog.swift",
        )
        for (assetPackID, destination) in expectedDestinations {
            #expect(catalog.contains("assetPackID: \"\(assetPackID)\""))
            #expect(catalog.contains("assetPackModelPath: \"\(destination)\""))
        }
        #expect(catalog.components(separatedBy: "expectedArchiveSHA256: nil").count - 1 == 2)
        #expect(catalog.components(separatedBy: "releaseReadiness: .blocked").count - 1 == 2)

        let documentation = try repositoryText("ModelAssets/README.md")
        for (assetPackID, destination) in expectedDestinations {
            #expect(documentation.contains("`\(assetPackID)`"))
            #expect(documentation.contains("`\(destination)`"))
        }
        #expect(documentation.contains("releases/download/v1/manifest.json"))
        #expect(documentation.contains("BAUsesAppleHosting"))
    }

    @Test
    func `Background Assets metadata is complete`() throws {
        let appInfo = try propertyList("RawCull-Info.plist")
        let initialRestrictions = try #require(
            appInfo["BAInitialDownloadRestrictions"] as? [String: Any],
        )
        #expect(initialRestrictions["BADownloadAllowance"] as? Int == 0)
        #expect(initialRestrictions["BAEssentialDownloadAllowance"] as? Int == 0)
        #expect(
            initialRestrictions["BADownloadDomainAllowList"] as? [String]
                == ["github.com", "*.githubusercontent.com"],
        )

        let infoPlist = try PropertyListSerialization.propertyList(
            from: repositoryData("RawCullModelDownloader/Info.plist"),
            format: nil,
        )
        let root = try #require(infoPlist as? [String: Any])
        let attributes = try #require(
            root["EXAppExtensionAttributes"] as? [String: Any],
        )

        #expect(
            attributes["EXExtensionPointIdentifier"] as? String
                == "com.apple.background-asset-downloader-extension",
        )
    }

    @Test
    func `model provenance notice hashes are complete and blocked`() throws {
        let provenancePaths = [
            "ModelAssets/Notices/CLIP-DataComp/PROVENANCE.json",
            "ModelAssets/Notices/CLIP-OpenAI/PROVENANCE.json",
            "ModelAssets/Notices/SAM3/PROVENANCE.json"
        ]

        for path in provenancePaths {
            let provenance = try JSONDecoder().decode(
                ModelProvenance.self,
                from: repositoryData(path),
            )
            #expect(provenance.releaseStatus == "blocked")
            #expect(!provenance.releaseBlocker.isEmpty)

            let directory = repositoryRoot
                .appendingPathComponent(path)
                .deletingLastPathComponent()
            for licence in provenance.licences {
                let data = try Data(
                    contentsOf: directory.appendingPathComponent(licence.file),
                )
                #expect(sha256(data) == licence.sha256)
            }
        }

        let bundledLicenceHashes = [
            "OpenCLIP-DataComp-MIT.txt": "6e355cc8399a572ed3db329d178a1188400fbbaed4397c28bd5b5fbac2696986",
            "OpenAI-CLIP-Tokenizer-MIT.txt": "893951b3bf94db8df1b13e05da5cdeb499400960e4d44a3962a8b33ed0b4f28e",
            "SAM3-SAM-License-2025-11-19.txt": "b08db9d32c687054e99cbd41eb1dad19c76936dfb9e2b58e186a01204d8be9ab"
        ]
        for (filename, expectedHash) in bundledLicenceHashes {
            let data = try repositoryData("RawCull/Resources/ModelLicences/\(filename)")
            #expect(sha256(data) == expectedHash)
        }
    }
}

private struct ResolvedPackages: Decodable {
    struct Pin: Decodable {
        struct State: Decodable {
            let revision: String
            let version: String?
        }

        let identity: String
        let state: State
    }

    let pins: [Pin]
}

private struct ModelManifest: Decodable {
    struct AssetPack: Decodable {
        struct FileSelector: Decodable {
            struct Directory: Decodable {
                let destination: String
            }

            let directory: Directory
        }

        let assetPackID: String
        let fileSelectors: [FileSelector]
    }

    let assetPacks: [AssetPack]
}

private struct ModelProvenance: Decodable {
    struct Licence: Decodable {
        let file: String
        let sha256: String
    }

    let releaseStatus: String
    let releaseBlocker: String
    let licences: [Licence]

    enum CodingKeys: String, CodingKey {
        case releaseStatus = "release_status"
        case releaseBlocker = "release_blocker"
        case licences
    }
}

private enum ReleaseMetadataTestError: Error {
    case invalidPropertyList(String)
}

private let repositoryRoot = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent()
    .deletingLastPathComponent()

private func repositoryData(_ path: String) throws -> Data {
    try Data(contentsOf: repositoryRoot.appendingPathComponent(path))
}

private func repositoryText(_ path: String) throws -> String {
    try String(contentsOf: repositoryRoot.appendingPathComponent(path), encoding: .utf8)
}

private func propertyList(_ path: String) throws -> [String: Any] {
    let value = try PropertyListSerialization.propertyList(
        from: repositoryData(path),
        format: nil,
    )
    guard let dictionary = value as? [String: Any] else {
        throw ReleaseMetadataTestError.invalidPropertyList(path)
    }
    return dictionary
}

private func buildSettingBlocks(
    in project: String,
    bundleIdentifier: String,
) -> [String] {
    project.components(separatedBy: "buildSettings = {")
        .dropFirst()
        .compactMap { $0.components(separatedBy: "\n\t\t\t};").first }
        .filter { $0.contains("PRODUCT_BUNDLE_IDENTIFIER = \(bundleIdentifier);") }
}

private func buildSetting(_ name: String, in block: String) -> String? {
    let prefix = "\(name) = "
    guard let line = block.split(whereSeparator: \.isNewline).first(where: {
        $0.trimmingCharacters(in: .whitespaces).hasPrefix(prefix)
    }) else {
        return nil
    }
    return String(line.trimmingCharacters(in: .whitespaces)
        .dropFirst(prefix.count)
        .dropLast())
        .trimmingCharacters(in: CharacterSet(charactersIn: "\""))
}

private func sha256(_ data: Data) -> String {
    SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
}
