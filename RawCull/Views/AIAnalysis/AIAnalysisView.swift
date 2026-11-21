import SwiftUI

struct AIAnalysisView: View {
    @Environment(CatalogWorkspace.self) private var catalog
    @Environment(SelectionModel.self) private var selection
    @Environment(CatalogController.self) private var catalogController
    @Environment(SharpnessScoringModel.self) private var sharpnessModel
    @Bindable var qwenAnalysisFeature: RawCullQwenAnalysisFeature
    @Bindable var objectAnalysisFeature: RawCullObjectAnalysisFeature
    let combinedReviewFeature: CombinedReviewFeature
    let deepAIReviewController: DeepAIReviewController

    @State private var inputSource = AIAnalysisInputSource.gridSelection
    @State private var selectedTool = AIAnalysisTool.samCLIP

    private var inputFiles: [FileItem] {
        catalogController.aiAnalysisFiles(for: inputSource)
    }

    private var isAnalysisRunning: Bool {
        deepAIReviewController.isRunning
            || qwenAnalysisFeature.isRunning
            || objectAnalysisFeature.isRunning
            || combinedReviewFeature.isRunning
    }

    private var hasStoredResults: Bool {
        switch selectedTool {
        case .samCLIP:
            !deepAIReviewController.completedCandidates.isEmpty

        case .qwen:
            !qwenAnalysisFeature.results.isEmpty

        case .objects:
            !objectAnalysisFeature.results.isEmpty
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header & Control Bar
            VStack(spacing: 12) {
                HStack(spacing: 16) {
                    Picker("Analysis Tool", selection: $selectedTool) {
                        ForEach(AIAnalysisTool.allCases) { tool in
                            Label(tool.title, systemImage: tool.systemImage)
                                .tag(tool)
                        }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .frame(maxWidth: 620)
                    .accessibilityLabel("Analysis mode")
                    .disabled(isAnalysisRunning)

                    AIAnalysisInputPicker(
                        selection: $inputSource,
                        selectedCount: catalogController.aiAnalysisFiles(for: .gridSelection).count,
                        taggedCount: catalogController.aiAnalysisFiles(for: .taggedImages).count,
                        isRunning: isAnalysisRunning,
                        preserveGridSelection: catalogController.preserveAIAnalysisGridSelection,
                    )
                    .frame(maxWidth: 220)

                    Spacer(minLength: 0)
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
            .background(.ultraThinMaterial)

            Divider()

            // Main Content Body
            Group {
                if inputFiles.isEmpty, !hasStoredResults {
                    ContentUnavailableView(
                        "No Images to Analyze",
                        systemImage: "sparkles.rectangle.stack",
                        description: Text(emptyDescription),
                    )
                } else {
                    switch selectedTool {
                    case .samCLIP:
                        SAMCLIPAnalysisView(
                            catalog: catalog,
                            controller: deepAIReviewController,
                            files: inputFiles,
                            selection: Bindable(selection).selectedFileID,
                            focusMaskModel: sharpnessModel.focusMaskModel,
                            focusConfig: sharpnessModel.effectiveFocusConfig,
                        )
                        .disabled(combinedReviewFeature.lease.isHeld)

                    case .qwen:
                        QwenAnalysisView(
                            feature: qwenAnalysisFeature,
                            files: inputFiles,
                            selection: Bindable(selection).selectedFileID,
                        )
                        .disabled(combinedReviewFeature.lease.isHeld)

                    case .objects:
                        ObjectAnalysisView(
                            feature: objectAnalysisFeature,
                            files: inputFiles,
                            selection: Bindable(selection).selectedFileID,
                            focusMaskModel: sharpnessModel.focusMaskModel,
                            focusConfig: sharpnessModel.effectiveFocusConfig,
                        )
                        .disabled(combinedReviewFeature.lease.isHeld)
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            // Bottom Thumbnail Bar (Only shown when files are present)
            if !inputFiles.isEmpty {
                Divider()
                AIAnalysisThumbnailStrip(
                    files: inputFiles,
                    inputSource: inputSource,
                    thumbnailSize: SettingsViewModel.shared.thumbnailSizeGrid,
                )
            }
        }
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
        .onChange(of: selectedTool) { _, newTool in
            if newTool != .samCLIP {
                deepAIReviewController.cancel()
            }
            if newTool != .qwen {
                qwenAnalysisFeature.cancel()
            }
            if newTool != .objects {
                objectAnalysisFeature.cancel()
            }
        }
        .onChange(of: inputSource) { _, _ in
            deepAIReviewController.cancel()
            qwenAnalysisFeature.cancel()
            objectAnalysisFeature.cancel()
        }
        .thumbnailKeyNavigation(axis: .horizontal) { inputFiles }
    }

    private var emptyDescription: String {
        switch inputSource {
        case .gridSelection:
            "Select one or more images in Grid View, then return to AI Analysis."

        case .taggedImages:
            "Tag images with two or more stars before opening AI Analysis."
        }
    }
}

// MARK: - Subviews & Controls

private enum AIAnalysisTool: String, CaseIterable, Identifiable {
    case samCLIP
    case qwen
    case objects

    var id: String {
        rawValue
    }

    var title: String {
        switch self {
        case .samCLIP: "SAM 3 + CLIP"
        case .qwen: "Qwen Vision"
        case .objects: "Objects"
        }
    }

    var systemImage: String {
        switch self {
        case .samCLIP: "sparkle.magnifyingglass"
        case .qwen: "text.bubble"
        case .objects: "square.3.layers.3d"
        }
    }
}

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
