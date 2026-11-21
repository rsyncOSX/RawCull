import OSLog
import RawCullCore
import SwiftUI

struct BurstWorkspaceHeader: View {
    let catalog: CatalogWorkspace
    let burstWorkflow: BurstWorkflowController
    let similarityFeature: RawCullSimilarityFeature
    let groupID: Int
    @Binding var sortByAFPoint: Bool

    private var burstNumber: Int {
        (similarityFeature.burstGroups.firstIndex { $0.id == groupID } ?? groupID) + 1
    }

    private var isReviewed: Bool {
        burstWorkflow.burstGroupReviewState(groupID: groupID) == .reviewed
    }

    var body: some View {
        HStack(spacing: 12) {
            Button {
                burstWorkflow.returnToActiveBurstGroupView()
            } label: {
                Label("Burst list", systemImage: "chevron.left")
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.regular)
            .help("Return to Burst list (R)")

            Text("\(catalog.selectedSource?.name ?? "Catalog")  ·  \(groupID == -1 ? "Single Images" : "Burst \(burstNumber.formatted(.number.precision(.integerLength(2))))")")
                .font(.callout.monospaced())
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.middle)
            Spacer()

            if groupID != -1 {
                Picker(selection: $sortByAFPoint) {
                    Text("Best frame").tag(false)
                    Text("AF-point sharpness").tag(true)
                } label: {
                    Text("Sort burst")
                }
                .pickerStyle(.segmented)
                .controlSize(.small)
                .frame(width: 290)
                .fixedSize(horizontal: false, vertical: true)
                .help("Change the display order. AF-point sharpness places frames without a usable focus-point measurement last.")
            }

            BurstAssessmentButton(
                catalog: catalog,
                files: catalog.files.filter { file in
                    similarityFeature.burstGroups.first(where: { $0.id == groupID })?.fileIDs.contains(file.id) == true
                },
            )
            reviewButton
        }
        .padding(.horizontal, 16)
        .frame(height: 40)
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
            burstWorkflow.toggleBurstGroupReviewed(groupID: groupID)
        } label: {
            Label(
                "Mark Reviewed",
                systemImage: isReviewed ? "checkmark.circle.fill" : "checkmark.circle",
            )
        }
        .controlSize(.small)
        .help(isReviewed ? "Unmark this burst as reviewed" : "Mark this burst as reviewed")
        .accessibilityValue(isReviewed ? "Selected" : "Not selected")
    }
}
