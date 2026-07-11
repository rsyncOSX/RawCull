import RawCullCore
import SwiftUI

struct BurstCullingWorkspaceView: View {
    @Bindable var viewModel: RawCullViewModel
    let groupID: Int
    let onCompare: () -> Void

    @FocusState private var isFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            workspaceHeader
            Divider()
            shortcutBar
            Divider()

            HStack(spacing: 0) {
                VStack(spacing: 0) {
                    imageStage
                    Divider()
                    filmstrip
                }

                Divider()

                inspector
                    .frame(width: 340)
            }
        }
        .background(Color(nsColor: .windowBackgroundColor))
        .focusable()
        .focused($isFocused)
        .focusEffectDisabled(true)
        .onAppear {
            isFocused = true
            selectFirstFileIfNeeded()
        }
        .onKeyPress(.leftArrow) { navigate(by: -1); return .handled }
        .onKeyPress(.rightArrow) { navigate(by: 1); return .handled }
        .onKeyPress(.escape) { viewModel.returnToActiveBurstGroupView(); return .handled }
    }

    private var workspaceHeader: some View {
        HStack(spacing: 16) {
            Spacer()
            Text("\(viewModel.selectedSource?.name ?? "Catalog")  ·  Burst \(burstNumber.formatted(.number.precision(.integerLength(2))))")
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

            Button {
                viewModel.markBurstGroupReviewed(groupID: groupID)
            } label: {
                Label("Mark Reviewed", systemImage: "checkmark")
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 10)
        .background(.ultraThinMaterial)
    }

    private var shortcutBar: some View {
        HStack(spacing: 8) {
            Text("Groups  /  Bursts  /")
                .foregroundStyle(.secondary)
            Text(selectedFile?.name ?? "No frame selected")
                .fontWeight(.semibold)

            Spacer()

            Image(systemName: "arrow.left.square")
            Image(systemName: "arrow.right.square")
            Text("frame")
            keyCap("2–5")
            Text("rate")
            keyCap("P")
            Text("pick")
            keyCap("X")
            Text("reject")
        }
        .font(.callout.monospaced())
        .foregroundStyle(.secondary)
        .padding(.horizontal, 20)
        .padding(.vertical, 10)
    }

    private var imageStage: some View {
        ZStack {
            Color.black.opacity(0.2)

            if let selectedFile {
                ThumbnailImageView(
                    file: selectedFile,
                    targetSize: 1600,
                    style: .grid,
                    showsShimmer: true,
                    contentMode: .fit,
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(48)
                .overlay(alignment: .topLeading) {
                    tagStrip(for: selectedFile)
                        .padding(64)
                }
                .onTapGesture(count: 2) {
                    viewModel.openZoomOverlay(
                        navigationIDs: files.map(\.id),
                        initialSource: .embeddedJPG,
                        initialZoomMode: .fit,
                    )
                }
            } else {
                ContentUnavailableView("No burst frame", systemImage: "photo")
            }

            HStack {
                navigationButton(systemImage: "chevron.left", delta: -1)
                Spacer()
                navigationButton(systemImage: "chevron.right", delta: 1)
            }
            .padding(.horizontal, 24)
        }
        .frame(minHeight: 420)
    }

    private var filmstrip: some View {
        HStack(spacing: 18) {
            VStack(alignment: .leading, spacing: 5) {
                Text("Burst \(burstNumber.formatted(.number.precision(.integerLength(2))))")
                Text("\(selectedIndex + 1) / \(files.count)")
            }
            .font(.callout.monospaced())
            .foregroundStyle(.secondary)
            .frame(width: 76, alignment: .leading)

            ScrollView(.horizontal) {
                LazyHStack(spacing: 10) {
                    ForEach(files) { file in
                        BurstFilmstripThumbnail(
                            file: file,
                            isSelected: file.id == viewModel.selectedFileID,
                            isSuggested: analysis?.recommendedFileID == file.id,
                            isDeferred: analysis?.reviewState == .deferred,
                        ) {
                            viewModel.selectedFileID = file.id
                        }
                    }
                }
                .padding(.vertical, 2)
            }
            .scrollIndicators(.hidden)

            HStack(spacing: 8) {
                navigationButton(systemImage: "chevron.left", delta: -1)
                navigationButton(systemImage: "chevron.right", delta: 1)
            }
        }
        .padding(16)
        .frame(height: 144)
        .background(.quaternary.opacity(0.28))
    }

    private var inspector: some View {
        ScrollView {
            VStack(spacing: 16) {
                inspectorCard("Rating") {
                    WorkspaceRatingButtons(
                        currentRating: selectedRating,
                        onSelect: applyRating,
                    )
                }

                inspectorCard("Burst actions") {
                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                        Button("Defer") {
                            viewModel.toggleBurstGroupDeferred(groupID: groupID)
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.large)

                        Button("Compare", action: onCompare)
                            .buttonStyle(.bordered)
                            .controlSize(.large)

                        Button("Set pick") {
                            guard let selectedFile else { return }
                            viewModel.setManualBurstWinner(selectedFile, in: files)
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.large)
                        .disabled(selectedFile == nil)
                    }
                }

                inspectorCard("Tags") {
                    if let selectedFile {
                        tagStrip(for: selectedFile)
                    }
                }

                inspectorCard("File") {
                    fileDetails
                }
            }
            .padding(16)
        }
        .background(Color.black.opacity(0.13))
    }

    private var fileDetails: some View {
        VStack(spacing: 12) {
            detailRow("Name", selectedFile?.name ?? "—")
            detailRow("Burst", "\(burstNumber.formatted(.number.precision(.integerLength(2))))  ·  \(files.count) frames")
            detailRow("Catalog", viewModel.selectedSource?.name ?? "—")
            detailRow("Similarity", String(format: "%.2f group", viewModel.similarityModel.burstSensitivity))
            detailRow("Status", statusTitle)
        }
    }

    private func inspectorCard(
        _ title: String,
        @ViewBuilder content: () -> some View,
    ) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(title).font(.headline)
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(.quaternary.opacity(0.48), in: .rect(cornerRadius: 14))
        .overlay {
            RoundedRectangle(cornerRadius: 14)
                .stroke(.separator.opacity(0.65), lineWidth: 1)
        }
    }

    private func detailRow(_ title: String, _ value: String) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title).foregroundStyle(.secondary)
            Spacer()
            Text(value)
                .font(.callout.monospaced())
                .multilineTextAlignment(.trailing)
                .lineLimit(2)
        }
    }

    private func tagStrip(for file: FileItem) -> some View {
        HStack(spacing: 8) {
            let rating = RatingDisplay(
                rating: viewModel.getRating(for: file),
                isExplicit: viewModel.taggedNamesCache.contains(file.name),
            )
            WorkspaceTag(title: rating.label, color: rating.color)

            if analysis?.recommendedFileID == file.id {
                WorkspaceTag(title: "Suggested", color: .orange)
            }

            if let subject = viewModel.sharpnessModel.saliencyInfo[file.id]?.subjectLabel {
                WorkspaceTag(title: subject, color: .cyan)
            }
        }
    }

    private func keyCap(_ title: String) -> some View {
        Text(title)
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .background(.quaternary, in: .rect(cornerRadius: 5))
    }

    private func navigationButton(systemImage: String, delta: Int) -> some View {
        Button { navigate(by: delta) } label: {
            Image(systemName: systemImage)
                .font(.title3.weight(.semibold))
                .frame(width: 36, height: 36)
        }
        .buttonStyle(.bordered)
        .buttonBorderShape(.circle)
        .disabled(navigationDestination(by: delta) == nil)
    }

    private var files: [FileItem] {
        guard let group = viewModel.similarityModel.burstGroups.first(where: { $0.id == groupID }) else { return [] }
        let filesByID = Dictionary(uniqueKeysWithValues: viewModel.files.map { ($0.id, $0) })
        let rankedIDs = analysis?.candidates.map(\.fileID) ?? group.fileIDs
        return rankedIDs.compactMap { filesByID[$0] }
    }

    private var analysis: BurstAnalysisResult? {
        viewModel.burstAnalysisResult(for: groupID)
    }

    private var selectedFile: FileItem? {
        guard let selectedID = viewModel.selectedFileID else { return files.first }
        return files.first { $0.id == selectedID } ?? files.first
    }

    private var selectedIndex: Int {
        guard let selectedFile else { return 0 }
        return files.firstIndex { $0.id == selectedFile.id } ?? 0
    }
    private var selectedRating: Int? {
        guard let selectedFile else { return nil }
        let rating = viewModel.getRating(for: selectedFile)
        if rating == 0, !viewModel.taggedNamesCache.contains(selectedFile.name) {
            return nil
        }
        return rating
    }

    private var burstNumber: Int {
        (viewModel.similarityModel.burstGroups.firstIndex { $0.id == groupID } ?? groupID) + 1
    }

    private var statusTitle: String {
        switch analysis?.reviewState {
        case .deferred: "Deferred"
        case .reviewed: "Reviewed"
        case .decisionApplied: "Decision applied"
        case .manualWinnerOverride: "Manual pick"
        default: "Needs review"
        }
    }

    private func selectFirstFileIfNeeded() {
        guard !files.isEmpty else { return }
        if let selectedID = viewModel.selectedFileID, files.contains(where: { $0.id == selectedID }) {
            return
        }
        viewModel.selectedFileID = files[0].id
    }

    private func navigationDestination(by delta: Int) -> FileItem? {
        let destination = selectedIndex + delta
        guard files.indices.contains(destination) else { return nil }
        return files[destination]
    }

    private func navigate(by delta: Int) {
        guard let destination = navigationDestination(by: delta) else { return }
        viewModel.selectedFileID = destination.id
    }

    private func applyRating(_ rating: Int) {
        guard let selectedFile else { return }
        viewModel.updateRating(for: selectedFile, rating: rating)
    }
}

private struct BurstFilmstripThumbnail: View {
    let file: FileItem
    let isSelected: Bool
    let isSuggested: Bool
    let isDeferred: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 0) {
                ThumbnailImageView(file: file, targetSize: 180, style: .grid, showsShimmer: true)
                    .frame(width: 132, height: 82)
                    .clipped()
                    .overlay(alignment: .topTrailing) {
                        if isSuggested || isDeferred {
                            Circle()
                                .fill(isSuggested ? Color.green : Color.orange)
                                .frame(width: 9, height: 9)
                                .padding(7)
                        }
                    }
                Text(file.name)
                    .font(.caption2.monospaced())
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 5)
            }
            .frame(width: 132)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .compositingGroup()
        .clipShape(.rect(cornerRadius: 9))
        .overlay {
            RoundedRectangle(cornerRadius: 9)
                .stroke(
                    isSelected ? Color.accentColor : Color(nsColor: .separatorColor),
                    lineWidth: isSelected ? 3 : 1,
                )
        }
    }
}

private struct WorkspaceRatingButtons: View {
    let currentRating: Int?
    let onSelect: (Int) -> Void

    private let ratings: [(value: Int, title: String)] = [
        (-1, "X"), (0, "P"), (2, "2"), (3, "3"), (4, "4"), (5, "5"),
    ]

    var body: some View {
        HStack(spacing: 7) {
            ForEach(ratings, id: \.value) { rating in
                Button(rating.title) { onSelect(rating.value) }
                    .buttonStyle(.bordered)
                    .controlSize(.large)
                    .tint(currentRating == rating.value ? .accentColor : nil)
                    .accessibilityLabel(help(for: rating.value))
            }
        }
    }

    private func help(for rating: Int) -> String {
        switch rating {
        case -1: "Reject"
        case 0: "Pick"
        default: "\(rating) stars"
        }
    }
}

private struct WorkspaceTag: View {
    let title: String
    let color: Color

    var body: some View {
        Text(title)
            .font(.caption.weight(.semibold))
            .padding(.horizontal, 9)
            .padding(.vertical, 5)
            .foregroundStyle(color)
            .background(color.opacity(0.13), in: .rect(cornerRadius: 7))
            .overlay { RoundedRectangle(cornerRadius: 7).stroke(color.opacity(0.5), lineWidth: 1) }
    }
}
