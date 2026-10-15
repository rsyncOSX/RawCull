import SwiftUI

struct AIAnalysisView: View {
    @Bindable var viewModel: RawCullViewModel
    @Bindable var qwenAnalysisFeature: RawCullQwenAnalysisFeature
    @Bindable var objectAnalysisFeature: RawCullObjectAnalysisFeature
    let combinedReviewFeature: CombinedReviewFeature
    let deepAIReviewController: DeepAIReviewController

    @State private var inputSource = AIAnalysisInputSource.gridSelection
    @State private var selectedTool = AIAnalysisTool.samCLIP

    private var inputSourceSelection: Binding<AIAnalysisInputSource> {
        Binding(
            get: { inputSource },
            set: { source in
                if inputSource == .gridSelection, source == .taggedImages {
                    viewModel.preserveAIAnalysisGridSelection()
                }
                inputSource = source
            },
        )
    }

    private var inputFiles: [FileItem] {
        viewModel.aiAnalysisFiles(for: inputSource)
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

                    Picker("Source", selection: inputSourceSelection) {
                        Text("Selected (\(viewModel.aiAnalysisFiles(for: .gridSelection).count))")
                            .tag(AIAnalysisInputSource.gridSelection)
                        Text("Tagged (\(viewModel.aiAnalysisFiles(for: .taggedImages).count))")
                            .tag(AIAnalysisInputSource.taggedImages)
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .frame(maxWidth: 220)
                    .accessibilityLabel("Image source")
                    .disabled(isAnalysisRunning)

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
                            viewModel: viewModel,
                            controller: deepAIReviewController,
                            files: inputFiles,
                            selection: $viewModel.selectedFileID,
                            focusMaskModel: viewModel.sharpnessModel.focusMaskModel,
                            focusConfig: viewModel.sharpnessModel.effectiveFocusConfig,
                        )
                        .disabled(combinedReviewFeature.lease.isHeld)

                    case .qwen:
                        QwenAnalysisView(
                            feature: qwenAnalysisFeature,
                            files: inputFiles,
                            selection: $viewModel.selectedFileID,
                        )
                        .disabled(combinedReviewFeature.lease.isHeld)

                    case .objects:
                        ObjectAnalysisView(
                            feature: objectAnalysisFeature,
                            files: inputFiles,
                            selection: $viewModel.selectedFileID,
                            focusMaskModel: viewModel.sharpnessModel.focusMaskModel,
                            focusConfig: viewModel.sharpnessModel.effectiveFocusConfig,
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
                    viewModel: viewModel,
                    files: inputFiles,
                    inputSource: inputSource,
                    thumbnailSize: SettingsViewModel.shared.thumbnailSizeGrid,
                )
            }
        }
        .task {
            if inputFiles.isEmpty, !viewModel.aiAnalysisFiles(for: .taggedImages).isEmpty {
                inputSourceSelection.wrappedValue = .taggedImages
            }
        }
        .task(id: inputFiles.map(\.id)) {
            let availableIDs = Set(inputFiles.map(\.id))
            if viewModel.selectedFileID.map(availableIDs.contains) != true {
                viewModel.selectedFileID = inputFiles.first?.id
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
        .thumbnailKeyNavigation(viewModel: viewModel, axis: .horizontal) { inputFiles }
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
    @Bindable var viewModel: RawCullViewModel
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
                            ImageItemView(
                                viewModel: viewModel,
                                file: file,
                                isSelected: viewModel.selectedFileID == file.id,
                                thumbnailSize: thumbnailSize,
                                ratingValue: viewModel.getRating(for: file),
                                ratingDisplay: ratingDisplay(for: file),
                                ratingColor: ratingColor(for: file),
                                onSelect: { viewModel.selectFile(file) },
                            )
                            .id(file.id)
                        }
                    }
                    .padding(.vertical, 2)
                }
                .onAppear {
                    guard let selectedFileID = viewModel.selectedFileID,
                          files.contains(where: { $0.id == selectedFileID }) else { return }
                    DispatchQueue.main.async {
                        proxy.scrollTo(selectedFileID, anchor: .center)
                    }
                }
                .onChange(of: viewModel.selectedFileID) { _, selectedFileID in
                    guard let selectedFileID,
                          files.contains(where: { $0.id == selectedFileID }) else { return }
                    withAnimation(.easeInOut(duration: 0.2)) {
                        proxy.scrollTo(selectedFileID, anchor: .center)
                    }
                }
            }
            .frame(height: CGFloat(thumbnailSize) + 30)
            .thumbnailKeyNavigation(viewModel: viewModel, axis: .horizontal)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private func ratingDisplay(for file: FileItem) -> RatingDisplay {
        RatingDisplay(
            rating: viewModel.getRating(for: file),
            isExplicit: viewModel.taggedNamesCache.contains(file.name),
        )
    }

    private func ratingColor(for file: FileItem) -> Color? {
        switch viewModel.getRating(for: file) {
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
    @Bindable var viewModel: RawCullViewModel
    let feature: CombinedReviewFeature
    let isEnabled: Bool

    @State private var inputSource = AIAnalysisInputSource.gridSelection

    private var inputSourceSelection: Binding<AIAnalysisInputSource> {
        Binding(
            get: { inputSource },
            set: { source in
                if inputSource == .gridSelection, source == .taggedImages {
                    viewModel.preserveAIAnalysisGridSelection()
                }
                inputSource = source
            },
        )
    }

    private var inputFiles: [FileItem] {
        viewModel.aiAnalysisFiles(for: inputSource)
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                
                Spacer()
                
                Picker("", selection: inputSourceSelection) {
                    Text("Selected (\(viewModel.aiAnalysisFiles(for: .gridSelection).count))")
                        .tag(AIAnalysisInputSource.gridSelection)
                    Text("Tagged (\(viewModel.aiAnalysisFiles(for: .taggedImages).count))")
                        .tag(AIAnalysisInputSource.taggedImages)
                }
                .pickerStyle(.segmented)
                .frame(maxWidth: 260)
                .disabled(feature.isRunning)
                
                Spacer()
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
            .background(.ultraThinMaterial)

            Divider()

            if !isEnabled {
                ContentUnavailableView(
                    "Combined Review Disabled",
                    systemImage: "viewfinder",
                    description: Text("Enable Combined Review in AI settings to use this workspace."),
                )
            } else {
                CombinedReviewView(feature: feature, viewModel: viewModel, files: inputFiles)
            }

            if !inputFiles.isEmpty {
                Divider()
                AIAnalysisThumbnailStrip(
                    viewModel: viewModel,
                    files: inputFiles,
                    inputSource: inputSource,
                    thumbnailSize: SettingsViewModel.shared.thumbnailSizeGrid,
                )
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .task {
            if inputFiles.isEmpty, !viewModel.aiAnalysisFiles(for: .taggedImages).isEmpty {
                inputSourceSelection.wrappedValue = .taggedImages
            }
        }
        .task(id: inputFiles.map(\.id)) {
            let availableIDs = Set(inputFiles.map(\.id))
            if viewModel.selectedFileID.map(availableIDs.contains) != true {
                viewModel.selectedFileID = inputFiles.first?.id
            }
        }
        .thumbnailKeyNavigation(viewModel: viewModel, axis: .horizontal) { inputFiles }
    }
}
