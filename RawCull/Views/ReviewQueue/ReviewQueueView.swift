import SwiftUI

struct ReviewQueueView: View {
    @Environment(\.dismiss) private var dismiss
    @Bindable var viewModel: RawCullViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            header
            filters
            Divider()
            queueList
        }
        .padding(18)
        .frame(minWidth: 780, minHeight: 560)
        .onAppear {
            viewModel.rebuildReviewQueue()
        }
    }

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text("Review Queue")
                    .font(.title2.weight(.semibold))
                Text(viewModel.reviewQueueSummaryText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button("Close") {
                dismiss()
            }
            .keyboardShortcut(.cancelAction)
        }
    }

    private var filters: some View {
        HStack(spacing: 12) {
            Picker("Category", selection: $viewModel.selectedReviewQueueCategory) {
                Text("All").tag(ReviewQueueCategory?.none)
                ForEach(ReviewQueueCategory.allCases) { category in
                    Text(category.title).tag(Optional(category))
                }
            }
            .pickerStyle(.segmented)

            Toggle("Show Resolved", isOn: $viewModel.showResolvedReviewQueueItems)
                .toggleStyle(.checkbox)
                .fixedSize()
        }
    }

    @ViewBuilder
    private var queueList: some View {
        if viewModel.visibleReviewQueueItems.isEmpty {
            ContentUnavailableView(
                "No Review Items",
                systemImage: "checkmark.circle",
                description: Text("There are no matching review items for this catalog."),
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            List(viewModel.visibleReviewQueueItems) { item in
                ReviewQueueRowView(
                    item: item,
                    onOpen: {
                        viewModel.openReviewQueueItem(item)
                        dismiss()
                    },
                    onResolve: {
                        viewModel.resolveReviewQueueItem(item)
                    },
                    onIgnore: {
                        viewModel.ignoreReviewQueueItem(item)
                    },
                    onReopen: {
                        viewModel.reopenReviewQueueItem(item)
                    },
                )
            }
            .listStyle(.inset)
        }
    }
}
