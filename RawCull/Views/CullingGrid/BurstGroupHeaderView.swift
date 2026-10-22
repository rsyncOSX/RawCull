import AppKit
import RawCullCore
import SwiftUI

struct BurstGroupHeaderView: View {
    let groupNumber: Int
    let groupID: Int
    let files: [FileItem]
    let analysis: BurstAnalysisResult?
    let onReviewed: (Int) -> Void
    let onDeferred: (Int) -> Void
    @Bindable var viewModel: RawCullViewModel

    private var isReviewed: Bool {
        viewModel.burstGroupReviewState(groupID: groupID) == .reviewed
    }

    private var isDeferred: Bool {
        viewModel.burstGroupReviewState(groupID: groupID) == .deferred
    }

    var body: some View {
        HStack(spacing: 12) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text(groupID == -1 ? "Single Images" : "Burst \(groupNumber.formatted(.number.precision(.integerLength(2))))")
                    .font(.headline)
                Text(groupID == -1 ? "\(files.count) images" : "\(files.count) frames")
                    .font(.callout.monospacedDigit())
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 12)

            Button {
                viewModel.compareBurstGroup(files)
            } label: {
                Label("Open burst", systemImage: "arrow.right")
            }
            .controlSize(.regular)
            .buttonStyle(.borderedProminent)
            .help("Open this burst for review")

            if groupID == -1 || analysis != nil {
                Button {
                    onReviewed(groupID)
                } label: {
                    Label("Mark Reviewed", systemImage: isReviewed ? "checkmark.circle.fill" : "checkmark.circle")
                }
                .controlSize(.regular)
                .buttonStyle(.bordered)
                .tint(isReviewed ? .green : nil)
                .help("Mark this burst as reviewed")
                .accessibilityValue(isReviewed ? "Selected" : "Not selected")

                Button {
                    onDeferred(groupID)
                } label: {
                    Label("Defer", systemImage: isDeferred ? "clock.badge.checkmark.fill" : "clock.arrow.circlepath")
                }
                .controlSize(.regular)
                .buttonStyle(.bordered)
                .tint(isDeferred ? .orange : nil)
                .help("Defer this burst for later review")
                .accessibilityValue(isDeferred ? "Selected" : "Not selected")
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }
}
