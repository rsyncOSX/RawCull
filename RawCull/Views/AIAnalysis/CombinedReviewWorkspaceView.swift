import SwiftUI

struct AIAnalysisThumbnailStrip: View {
    @Environment(SelectionModel.self) private var selection
    @Environment(RatingsModel.self) private var ratings
    let files: [FileItem]
    let inputSource: AIAnalysisInputSource
    let thumbnailSize: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(inputSource == .gridSelection ? "Selected Images" : "Tagged Images")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.secondary)
                Spacer()
                Text("\(files.count) items")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }

            ScrollViewReader { proxy in
                ScrollView(.horizontal, showsIndicators: false) {
                    LazyHStack(spacing: 8) {
                        ForEach(files) { file in
                            ImageItemView(file: file,
                                          isSelected: selection.selectedFileID == file.id,
                                          thumbnailSize: thumbnailSize,
                                          ratingValue: ratings.getRating(for: file),
                                          ratingDisplay: ratingDisplay(for: file),
                                          ratingColor: ratingColor(for: file),
                                          onSelect: { selection.select(file) })
                                .id(file.id)
                        }
                    }
                    .padding(.vertical, 2)
                }
                .onAppear {
                    guard let selectedFileID = selection.selectedFileID,
                          files.contains(where: { $0.id == selectedFileID }) else { return }
                    DispatchQueue.main.async {
                        proxy.scrollTo(selectedFileID, anchor: .center)
                    }
                }
                .onChange(of: selection.selectedFileID) { _, selectedFileID in
                    guard let selectedFileID,
                          files.contains(where: { $0.id == selectedFileID }) else { return }
                    withAnimation(.easeInOut(duration: 0.2)) {
                        proxy.scrollTo(selectedFileID, anchor: .center)
                    }
                }
            }
            .frame(height: CGFloat(thumbnailSize) + 30)
            .thumbnailKeyNavigation(axis: .horizontal)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private func ratingDisplay(for file: FileItem) -> RatingDisplay {
        RatingDisplay(
            rating: ratings.getRating(for: file),
            isExplicit: ratings.taggedNamesCache.contains(file.name),
        )
    }

    private func ratingColor(for file: FileItem) -> Color? {
        switch ratings.getRating(for: file) {
        case -1: .red
        case 2: .yellow
        case 3: .green
        case 4: .blue
        case 5: .purple
        default: nil
        }
    }
}

struct CombinedReviewWorkspaceView: View {
    @Environment(SelectionModel.self) private var selection
    @Environment(CatalogController.self) private var catalogController
    let feature: CombinedReviewFeature

    @State private var inputSource = AIAnalysisInputSource.gridSelection

    private var inputFiles: [FileItem] {
        catalogController.aiAnalysisFiles(for: inputSource)
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Spacer()

                AIAnalysisInputPicker(
                    selection: $inputSource,
                    selectedCount: catalogController.aiAnalysisFiles(for: .gridSelection).count,
                    taggedCount: catalogController.aiAnalysisFiles(for: .taggedImages).count,
                    isRunning: feature.isRunning,
                    preserveGridSelection: catalogController.preserveAIAnalysisGridSelection,
                )
                .frame(maxWidth: 260)

                Spacer()
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
            .background(.ultraThinMaterial)

            Divider()

            CombinedReviewView(feature: feature, selection: selection, files: inputFiles)

            if !inputFiles.isEmpty {
                Divider()
                AIAnalysisThumbnailStrip(
                    files: inputFiles,
                    inputSource: inputSource,
                    thumbnailSize: SettingsViewModel.shared.thumbnailSizeGrid,
                )
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .task {
            if inputFiles.isEmpty, !catalogController.aiAnalysisFiles(for: .taggedImages).isEmpty {
                AIAnalysisInputSelection.binding(
                    selection: $inputSource, preserveGridSelection: catalogController.preserveAIAnalysisGridSelection,
                ).wrappedValue = .taggedImages
            }
        }
        .task(id: inputFiles.map(\.id)) {
            let availableIDs = Set(inputFiles.map(\.id))
            if selection.selectedFileID.map(availableIDs.contains) != true {
                selection.selectedFileID = inputFiles.first?.id
            }
        }
        .thumbnailKeyNavigation(axis: .horizontal) { inputFiles }
    }
}
