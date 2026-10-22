import OSLog
import RawCullCore
import SwiftUI

struct BurstWorkspaceHeader: View {
    let viewModel: RawCullViewModel
    let groupID: Int

    private var burstNumber: Int {
        (viewModel.similarityFeature.burstGroups.firstIndex { $0.id == groupID } ?? groupID) + 1
    }

    private var isReviewed: Bool {
        viewModel.burstGroupReviewState(groupID: groupID) == .reviewed
    }

    var body: some View {
        HStack(spacing: 16) {
            Spacer()
            Text("\(viewModel.selectedSource?.name ?? "Catalog")  ·  \(groupID == -1 ? "Single Images" : "Burst \(burstNumber.formatted(.number.precision(.integerLength(2))))")")
                .font(.headline.monospaced())
                .foregroundStyle(.secondary)
            Spacer()

            Button {
                viewModel.returnToActiveBurstGroupView()
            } label: {
                Label("Burst list", systemImage: "chevron.left")
            }
            .buttonStyle(.bordered)
            .controlSize(.large)

            reviewButton
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 10)
        .background(.ultraThinMaterial)
    }

    @ViewBuilder
    private var reviewButton: some View {
        if isReviewed {
            reviewButtonContent
                .buttonStyle(.borderedProminent)
        } else {
            reviewButtonContent
                .buttonStyle(.bordered)
        }
    }

    private var reviewButtonContent: some View {
        Button {
            viewModel.toggleBurstGroupReviewed(groupID: groupID)
        } label: {
            Label(
                "Mark Reviewed",
                systemImage: isReviewed ? "checkmark.circle.fill" : "checkmark.circle",
            )
        }
        .controlSize(.large)
        .help(isReviewed ? "Unmark this burst as reviewed" : "Mark this burst as reviewed")
        .accessibilityValue(isReviewed ? "Selected" : "Not selected")
    }
}
