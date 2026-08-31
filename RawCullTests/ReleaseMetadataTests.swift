import Foundation
import Testing

@Suite("Release metadata", .tags(.smoke))
struct ReleaseMetadataTests {
    @Test
    func `application metadata has no model delivery surface`() throws {
        let project = try repositoryText("RawCull.xcodeproj/project.pbxproj")
        let appInfo = try propertyList("RawCull-Info.plist")
        let entitlements = try propertyList("RawCull.entitlements")

        #expect(project.contains("PRODUCT_BUNDLE_IDENTIFIER = no.blogspot.RawCull;"))
        #expect(!project.contains("RawCullModelDownloader"))
        #expect(!project.contains("BackgroundAssets.framework"))
        #expect(!project.contains("PhotoAIKit"))
        #expect(appInfo.keys.allSatisfy { !$0.hasPrefix("BA") })
        #expect(entitlements["com.apple.security.application-groups"] == nil)
        #expect(entitlements["com.apple.security.app-sandbox"] as? Bool == true)
    }

    @Test
    func `resolved graph and documentation describe Vision-only dependencies`() throws {
        let resolved = try repositoryText(
            "RawCull.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved",
        )
        let readme = try repositoryText("README.md")
        let about = try repositoryText("RawCull/Views/Tools/AboutRawCullView.swift")

        #expect(resolved.contains("photoanalysiskit"))
        #expect(!resolved.contains("photoaikit"))
        #expect(!resolved.contains("coreai-models"))
        #expect(readme.contains("VisionFeaturePrintBackend"))
        #expect(about.contains("Vision similarity"))
    }

    @Test
    func `model assets and downloader sources are absent`() {
        let removedPaths = [
            "ModelAssets/manifest.template.json",
            "ModelAssets/README.md",
            "RawCullModelDownloader/Info.plist",
            "RawCull/Intelligence/DeepReview/DeepAIReviewFeature.swift",
            "RawCull/Intelligence/SemanticSearch/RawCullSemanticSearchFeature.swift",
            "RawCull/Views/Settings/AISettingsTab.swift",
        ]

        for path in removedPaths {
            #expect(!FileManager.default.fileExists(
                atPath: repositoryRoot.appendingPathComponent(path).path,
            ))
        }
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
