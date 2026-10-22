import SwiftUI

struct DeepAIReviewProgressHeader: View {
    let completedCount: Int
    let totalCount: Int
    let currentFileName: String?

    var body: some View {
        AIAnalysisProgressView(
            completedCount: completedCount,
            totalCount: totalCount,
            message: currentFileName.map { "Analyzing \($0)" } ?? "Preparing subject-detail analysis…",
        )
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Deep Review progress")
        .accessibilityValue(progressAccessibilityValue)
    }

    private var progressAccessibilityValue: String {
        var value = "\(completedCount) of \(totalCount) candidates complete"
        if let currentFileName {
            value += ". Analyzing \(currentFileName)"
        }
        return value
    }
}
