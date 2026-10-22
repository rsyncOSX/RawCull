import SwiftUI

extension DeepAIReviewCandidate {
    /// A "not yet analyzed" row for a file, used to populate the candidate
    /// table immediately when Deep Review is preparing to run, before any
    /// real scores exist.
    static func placeholder(rank: Int, file: FileItem) -> DeepAIReviewCandidate {
        DeepAIReviewCandidate(
            fileID: file.id,
            fileName: file.url.lastPathComponent,
            rank: rank,
            isCompleted: false,
            deepScore: nil,
            normalSharpnessScore: nil,
            broadSubjectScore: nil,
            localDetailScore: nil,
            fineDetailScore: nil,
            maskPromptUsed: nil,
            maskConfidence: nil,
            maskCoverage: nil,
            autofocusInsideMask: nil,
            promptVerified: nil,
            usedFallbackMask: false,
            issues: [],
        )
    }
}
