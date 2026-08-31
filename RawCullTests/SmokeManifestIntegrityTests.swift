import Foundation
import Testing

@Suite("Smoke manifest integrity")
struct SmokeManifestIntegrityTests {
    @Test
    func `manifest is ordered unique and unchanged`() throws {
        let actual = try smokeManifestSelectors()

        #expect(actual == expectedSmokeSelectors)
        #expect(Set(actual).count == actual.count)
    }

    @Test
    func `every source smoke declaration has a suite selector`() throws {
        let taggedSuites = try sourceSuitesTaggedForSmoke()
        let selectedSuites = try Set(smokeManifestSelectors().filter {
            $0.split(separator: "/").count == 2
        }.compactMap { $0.split(separator: "/").last.map(String.init) })

        #expect(taggedSuites == expectedTaggedSuites)
        #expect(taggedSuites.isSubset(of: selectedSuites))
    }
}

private let expectedSmokeSelectors = """
RawCullTests/AICacheBoundaryTests
RawCullTests/AccessibilityPresentationTests
RawCullTests/ApertureHintTests
RawCullTests/BurstAnalysisCoordinatorTests
RawCullTests/BurstAnalysisPipelineValuesTests
RawCullTests/BurstFrameCachePolicyTests
RawCullTests/BurstReviewKeyActionTests
RawCullTests/ComparisonGridDisplayStateTests
RawCullTests/ComparisonGridNavigationTests
RawCullTests/CullingGridCoordinatorTests
RawCullTests/FocusNumericHelperTests
RawCullTests/HistogramLoadingTests
RawCullTests/ISOScalingTests
RawCullTests/ImageSourceSelectionStateTests
RawCullTests/LoupeImageKeyActionTests
RawCullTests/PerFileAnalysisArtifactStoreTests
RawCullTests/PhotoAnalysisKitIntegrationTests
RawCullTests/RawCullSimilarityFeatureTests
RawCullTests/ReleaseMetadataTests
RawCullTests/SharpnessScoringTests
RawCullTests/SmokeManifestIntegrityTests
RawCullTests/ThumbnailKeyActionTests
RawCullTests/ZoomOverlayKeyActionTests
RawCullTests/ZoomOverlayNavigationContextTests
RawCullTests/ZoomViewportMathTests
RawCullTests/CullingModelTests/`cancelling similarity ranking stops its owned distance helper`()
RawCullTests/CullingModelTests/`similarity indexing cancellation stops structured embedding workers`()
RawCullTests/CullingModelTests/`superseded similarity indexing cannot commit or clear newer run state`()
""".split(separator: "\n").map(String.init)

private let expectedTaggedSuites: Set<String> = [
    "AICacheBoundaryTests",
    "AccessibilityPresentationTests",
    "ApertureHintTests",
    "BurstAnalysisCoordinatorTests",
    "BurstAnalysisPipelineValuesTests",
    "BurstFrameCachePolicyTests",
    "BurstReviewKeyActionTests",
    "ComparisonGridDisplayStateTests",
    "ComparisonGridNavigationTests",
    "CullingGridCoordinatorTests",
    "FocusNumericHelperTests",
    "HistogramLoadingTests",
    "ISOScalingTests",
    "ImageSourceSelectionStateTests",
    "LoupeImageKeyActionTests",
    "PerFileAnalysisArtifactStoreTests",
    "PhotoAnalysisKitIntegrationTests",
    "RawCullSimilarityFeatureTests",
    "ReleaseMetadataTests",
    "SharpnessScoringTests",
    "ThumbnailKeyActionTests",
    "ZoomOverlayKeyActionTests",
    "ZoomOverlayNavigationContextTests",
    "ZoomViewportMathTests"
]

private func smokeManifestSelectors() throws -> [String] {
    let repositoryRoot = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
    let manifestURL = repositoryRoot
        .appendingPathComponent("TestManifests", isDirectory: true)
        .appendingPathComponent("SmokeTests.txt")
    return try String(contentsOf: manifestURL, encoding: .utf8)
        .split(whereSeparator: \.isNewline)
        .map(String.init)
}

private func sourceSuitesTaggedForSmoke() throws -> Set<String> {
    let testsDirectory = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
    let sourceURLs = try FileManager.default.contentsOfDirectory(
        at: testsDirectory,
        includingPropertiesForKeys: nil,
    ).filter { $0.pathExtension == "swift" }

    var taggedSuites: Set<String> = []
    for sourceURL in sourceURLs {
        let lines = try String(contentsOf: sourceURL, encoding: .utf8)
            .split(whereSeparator: \.isNewline)
            .map(String.init)
        var currentTopLevelStruct: String?
        var pendingTaggedSuite = false
        var attributeKind: TestAttributeKind?
        var attributeText = ""
        var attributeParenthesisDepth = 0

        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if attributeKind == nil {
                if trimmed.hasPrefix("@Suite") {
                    attributeKind = .suite
                } else if trimmed.hasPrefix("@Test") {
                    attributeKind = .test
                }
            }

            if let activeAttribute = attributeKind {
                attributeText += line
                attributeParenthesisDepth += line.filter { $0 == "(" }.count
                attributeParenthesisDepth -= line.filter { $0 == ")" }.count
                if attributeParenthesisDepth <= 0 {
                    let isSmoke = attributeText.contains(".tags(.smoke)")
                    if activeAttribute == .suite, isSmoke {
                        pendingTaggedSuite = true
                    } else if activeAttribute == .test, isSmoke,
                              let currentTopLevelStruct {
                        taggedSuites.insert(currentTopLevelStruct)
                    }
                    attributeKind = nil
                    attributeText = ""
                    attributeParenthesisDepth = 0
                }
                continue
            }

            if let structName = topLevelStructName(in: line) {
                currentTopLevelStruct = structName
                if pendingTaggedSuite {
                    taggedSuites.insert(structName)
                    pendingTaggedSuite = false
                }
                continue
            }
        }
    }
    return taggedSuites
}

private enum TestAttributeKind {
    case suite
    case test
}

private func topLevelStructName(in line: String) -> String? {
    let prefixes = ["struct ", "private struct "]
    guard let prefix = prefixes.first(where: line.hasPrefix) else { return nil }
    return line.dropFirst(prefix.count).split(whereSeparator: { $0 == " " || $0 == ":" }).first.map(String.init)
}
