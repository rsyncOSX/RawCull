import Foundation
import PhotoAIContracts
@testable import RawCull
import Testing

@MainActor
@Suite("Accessibility presentation", .tags(.smoke))
struct AccessibilityPresentationTests {
    @Test
    func `saved rows announce content and selection`() {
        #expect(RawCullAccessibilityPresentation.savedCatalogValue(
            fileCount: 3,
            date: "4 August 2026",
            isSelected: true,
        ) == "3 files, 4 August 2026, Selected")
        #expect(RawCullAccessibilityPresentation.savedRecordValue(
            rating: 4,
            dateTagged: "Today",
            isSelected: false,
        ) == "4-star rating, Tagged Today, Not selected")
    }

    @Test
    func `image tiles announce rating selection and semantic rank`() {
        #expect(RawCullAccessibilityPresentation.imageValue(
            rating: .keeper,
            isSelected: false,
            isMultiSelected: true,
            semanticRank: 2,
            semanticResultCount: 12,
        ) == "Keeper, Included in selection, Semantic result 2 of 12")
    }

    @Test
    func `AI capability and downloads announce readiness licence progress and failure`() {
        #expect(RawCullAccessibilityPresentation.capabilityValue(
            status: .missing(expectedLocations: [URL(fileURLWithPath: "/Models/SAM3")]),
            availableMessage: "SAM 3 is installed.",
            missingMessage: "SAM 3 is not installed.",
        ) == "Missing. SAM 3 is not installed. Expected location: /Models/SAM3")
        #expect(RawCullAccessibilityPresentation.capabilityValue(
            status: .available(location: URL(fileURLWithPath: "/temporary/model")),
            availableMessage: "DataComp CLIP is installed.",
            missingMessage: "DataComp CLIP is not installed.",
        ) == "Available. DataComp CLIP is installed.")
        #expect(RawCullAccessibilityPresentation.modelDownloadValue(
            state: .downloading(progress: 0.42),
            licenceAccepted: true,
        ) == "Downloading 42 percent. Licence accepted.")
        #expect(RawCullAccessibilityPresentation.modelDownloadValue(
            state: .installed(location: URL(fileURLWithPath: "/temporary/model")),
            licenceAccepted: true,
        ) == "Installed and managed by macOS. Licence accepted.")
        #expect(RawCullAccessibilityPresentation.modelDownloadValue(
            state: .failed(message: "Checksum mismatch"),
            licenceAccepted: false,
        ) == "Download failed. Checksum mismatch. Licence not accepted.")
    }

    @Test
    func `semantic search announces CLIP backend coverage and result count`() {
        let backend = SimilarityBackendDescriptor(
            backend: "clip",
            modelFingerprint: "accessibility-model-v1",
            representation: "float32-l2-normalized",
            preprocessingVersion: "accessibility-preprocess-v1",
            normalizationVersion: "accessibility-normalization-v1",
            configurationVersion: "accessibility-config-v1",
        )
        let presentation = SemanticSearchUIPresentation(
            capability: .ready(location: nil, backend: backend),
            searchState: .results(RawCullSemanticSearchResultSummary(
                query: "red fox",
                resultCount: 5,
                rankedImageCount: 8,
                indexedFileCount: 7,
                excludedFileCount: 3,
                scoringFailureCount: 0,
            )),
            indexedFileCount: 7,
            catalogFileCount: 10,
            isIndexing: false,
            indexingProgress: 0,
            indexingTotal: 0,
            indexingPhase: .idle,
            activeBackendCanIndex: true,
        )

        #expect(RawCullAccessibilityPresentation.semanticSearchValue(presentation)
            == "Ready using CLIP model accessibility-model-v1. 7 of 10 images indexed. Showing 5 of 8 ranked images.")
    }

    @Test
    func `Deep Review announces SAM 3 progress and confidence`() {
        let progress = DeepAIReviewProgress(
            groupID: 7,
            completedCount: 2,
            totalCount: 5,
            currentFileName: "frame-3.ARW",
            candidates: [],
        )
        #expect(RawCullAccessibilityPresentation.deepReviewValue(
            state: .running(progress),
            cachedResult: nil,
            groupID: 7,
        ) == "Running SAM 3 Deep Review, 2 of 5 candidates complete.")

        let winnerID = UUID()
        let winner = DeepAIReviewCandidate(
            fileID: winnerID,
            fileName: "winner.ARW",
            rank: 1,
            isCompleted: true,
            deepScore: 0.9,
            normalSharpnessScore: 0.8,
            broadSubjectScore: 0.7,
            localDetailScore: 0.9,
            fineDetailScore: 0.8,
            maskPromptUsed: .subject,
            maskConfidence: 0.9,
            maskCoverage: 0.4,
            autofocusInsideMask: true,
            promptVerified: true,
            usedFallbackMask: false,
            issues: [],
        )
        let result = DeepAIReviewResult(
            groupID: 7,
            groupSignature: BurstGroupSignature(memberKeys: ["winner.ARW"]),
            preset: .fullSubject,
            candidates: [winner],
            recommendedFileID: winnerID,
            confidence: .high,
            reasons: [.strongestSubjectDetail],
            cautions: [],
            timestamp: Date(timeIntervalSince1970: 0),
        )
        #expect(RawCullAccessibilityPresentation.deepReviewValue(
            state: .completed(result),
            cachedResult: result,
            groupID: 7,
        ) == "Completed. Recommends winner.ARW. High confidence.")
    }
}
