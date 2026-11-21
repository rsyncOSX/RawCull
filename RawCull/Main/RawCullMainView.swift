import OSLog
import RawCullCore
import SwiftUI
import UniformTypeIdentifiers

struct RawCullMainView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.openWindow) var openWindow

    @Bindable var viewModel: RawCullViewModel
    let similarityFeature: RawCullSimilarityFeature
    let semanticSearchFeature: RawCullSemanticSearchFeature
    let deepAIReviewController: DeepAIReviewController
    let qwenAnalysisFeature: RawCullQwenAnalysisFeature
    let objectAnalysisFeature: RawCullObjectAnalysisFeature
    let combinedReviewFeature: CombinedReviewFeature
    let aiSettingsModel: RawCullAISettingsModel
    let assessmentNavigation: AIAssessmentNavigation
    let assessmentPhotoAccess: (AnalysisJobStore.FollowUpRequest) throws -> RawCullCatalogGrant

    @State private var memoryWarningOpacity: Double = 0.3
    @State private var dismissedMemoryPressureWarning = false
    @State var columnVisibility = NavigationSplitViewVisibility.doubleColumn

    // Periphery 3.8 does not follow projected-value reads from SDK 27's macro-backed @State.
    // periphery:ignore
    @State private var cgImage: CGImage?
    // periphery:ignore
    @State private var nsImage: NSImage?
    // periphery:ignore
    @State private var showCandidateInspector = false

    private var showsJPGExtractionProgressOverlay: Bool {
        viewModel.fileOperations.currentExtractAndSaveJPGsActor != nil && viewModel.navigation.mainViewMode != .loupe
    }

    var body: some View {
        ZStack {
            if assessmentNavigation.presentedID != nil {
                AIAssessmentWorkspace(
                    navigation: assessmentNavigation,
                    photoAccess: assessmentPhotoAccess,
                )
                .navigationTitle("AI Assessment")
            } else {
                switch viewModel.navigation.mainViewMode {
                case .loupe:
                    loupeSplit

                case .grid:
                    gridSplit

                case .similarityGrid:
                    similarityGridSplit

                case .ratedGrid:
                    ratedGridSplit

                case .comparisonGrid:
                    comparisonGridSplit

                case .aiAnalysis:
                    aiAnalysisSplit

                case .combinedReview:
                    combinedReviewSplit
                }
            }

            if viewModel.zoomOverlay.isVisible {
                ZoomOverlayView()
                    .transition(.opacity)
                    .zIndex(10)
            }

            if showsJPGExtractionProgressOverlay {
                VStack {
                    Spacer()

                    ProgressCount(
                        completed: viewModel.fileOperations.fileOperationCompleted,
                        total: viewModel.fileOperations.fileOperationTotal,
                        estimatedSeconds: viewModel.fileOperations.fileOperationEstimatedSeconds,
                        statusText: "Extracting JPGs",
                    )
                    .frame(maxWidth: 480)
                    .padding(16)
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(Color.primary.opacity(0.12), lineWidth: 1),
                    )
                    .shadow(color: .black.opacity(0.25), radius: 12, y: 4)
                    .padding(.bottom, 24)
                }
                .transition(.move(edge: .bottom).combined(with: .opacity))
                .zIndex(12)
            }
        }
        .sheet(item: Bindable(viewModel.presentation).activeSheet) { sheet in
            switch sheet {
            case .stats:
                ScanStatsSheetView()

            case .scoringParams:
                ScoringParametersSheetView(
                    config: Bindable(viewModel.sharpnessModel.focusMaskModel).config,
                    thumbnailMaxPixelSize: Bindable(viewModel.sharpnessModel).thumbnailMaxPixelSize,
                    scoringQuality: Bindable(viewModel.sharpnessModel).scoringQuality,
                    scoringSource: Bindable(viewModel.sharpnessModel).scoringSource,
                )

            case .extractJPGs:
                ExtractJPGsSheetView()
            }
        }
        .sheet(isPresented: Bindable(viewModel.presentation).showCopyARWFilesView) {
            CopyARWFilesView(
                sheetType: Bindable(viewModel.presentation).sheetType,
                remoteDataNumbers: Bindable(viewModel.fileOperations).remoteDataNumbers,
                showcopytask: Bindable(viewModel.presentation).showCopyARWFilesView,
            )
        }
        .alert(item: Bindable(viewModel.presentation).operationFailurePresentation) { presentation in
            Alert(
                title: Text(presentation.title),
                message: Text(presentation.message),
                dismissButton: .default(Text("OK")),
            )
        }
        .alert(persistenceAlertTitle, isPresented: persistenceErrorIsPresented) {
            Button("Retry") {
                Task {
                    await viewModel.culling.retryCullingPersistence()
                }
            }
            if viewModel.ratings.cullingModel.persistenceLoadFailure != nil {
                Button("Archive Damaged File and Reset", role: .destructive) {
                    Task {
                        await viewModel.culling.archiveCullingStoreAndReset()
                    }
                }
            }
        } message: {
            Text(persistenceAlertMessage)
        }
        .alert("Full Burst Re-index?", isPresented: burstFullReindexIsPresented) {
            if viewModel.burstWorkflow.hasExistingBurstGroupIndex {
                Button("Use Existing Index") {
                    viewModel.burstWorkflow.burstFullReindexRequest = nil
                    viewModel.burstWorkflow.useExistingBurstGroupIndex()
                }
            }

            Button("Full Re-index", role: .destructive) {
                let request = viewModel.burstWorkflow.burstFullReindexRequest
                viewModel.burstWorkflow.burstFullReindexRequest = nil
                Task {
                    await viewModel.burstWorkflow.reindexBurstAnalysis()
                    guard !Task.isCancelled,
                          request == .semanticReview,
                          viewModel.burstWorkflow.hasExistingBurstGroupIndex
                    else { return }
                    viewModel.burstWorkflow.useExistingBurstGroupIndex()
                }
            }

            Button("Cancel", role: .cancel) {
                viewModel.burstWorkflow.burstFullReindexRequest = nil
            }
        } message: {
            Text(
                "This will rescore sharpness and recompute similarity for all \(viewModel.catalog.files.count) catalog files. It may take several minutes. Clear Search never performs this operation.",
            )
        }
        .transaction { transaction in
            if reduceMotion {
                transaction.animation = nil
                transaction.disablesAnimations = true
            }
        }
        .onChange(of: reduceMotion) { _, reduced in
            if reduced {
                memoryWarningOpacity = 0.8
            } else if viewModel.presentation.memoryPressureWarning {
                startMemoryWarningFlash()
            }
        }
        .onChange(of: viewModel.burstWorkflow.activeBurstComparisonGroupID) { oldGroupID, newGroupID in
            if oldGroupID != newGroupID {
                viewModel.burstWorkflow.showsDetailedBurstComparison = false
            }
        }
        .focusedSceneValue(\.extractJPGs, Bindable(viewModel.presentation).focusExtractJPGs)
        .focusedSceneValue(\.aborttask, Bindable(viewModel.presentation).focusAbortTask)
        .focusedSceneValue(\.addCatalog, Bindable(viewModel.presentation).isShowingPicker)
        .focusedSceneValue(\.copyTaggedFiles, Bindable(viewModel.presentation).focusCopyTaggedFiles)
        .focusedSceneValue(
            \.canCopyTaggedFiles,
            viewModel.catalog.selectedSource != nil && !viewModel.catalog.isCreatingThumbnails,
        )
        .onChange(of: viewModel.presentation.focusExtractJPGs) { _, shouldPresent in
            guard shouldPresent else { return }
            viewModel.presentation.focusExtractJPGs = false
            viewModel.fileOperations.presentExtractJPGsSheet()
        }
        .onChange(of: viewModel.presentation.focusCopyTaggedFiles) { _, shouldPresent in
            guard shouldPresent else { return }
            viewModel.presentation.focusCopyTaggedFiles = false
            viewModel.presentation.sheetType = .copytasksview
            viewModel.presentation.showCopyARWFilesView = true
        }
    }

    private var persistenceErrorIsPresented: Binding<Bool> {
        Binding(
            get: { !viewModel.ratings.cullingModel.isTerminationPending && viewModel.ratings.cullingModel.persistenceError != nil },
            set: { _ in },
        )
    }

    private var persistenceAlertTitle: String {
        viewModel.ratings.cullingModel.persistenceLoadFailure == nil
            ? "Changes Not Saved"
            : "Saved Culling Data Is Damaged"
    }

    private var persistenceAlertMessage: String {
        if viewModel.ratings.cullingModel.persistenceLoadFailure != nil {
            return "RawCull preserved the damaged file and blocked rating changes so it cannot be overwritten. Retry after repairing the file, or archive it and start with an empty saved-data store.\n\n\(viewModel.ratings.cullingModel.persistenceError ?? "Unknown error")"
        }
        return "RawCull could not save ratings and culling changes. Your changes remain in memory. Retry before quitting.\n\n\(viewModel.ratings.cullingModel.persistenceError ?? "Unknown error")"
    }

    private var burstFullReindexIsPresented: Binding<Bool> {
        Binding(
            get: { viewModel.burstWorkflow.burstFullReindexRequest != nil },
            set: { isPresented in
                if !isPresented {
                    viewModel.burstWorkflow.burstFullReindexRequest = nil
                }
            },
        )
    }

    // MARK: - Loupe mode (3-column split)

    private var loupeSplit: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            RAWCatalogSidebarView(
                sources: Bindable(viewModel.catalog).sources,
                selectedSource: Bindable(viewModel.catalog).selectedSource,
                cullingModel: viewModel.ratings.cullingModel,
            )
        } content: {
            SidebarARWCatalogFileView(
                selectedSource: Bindable(viewModel.catalog).selectedSource,
                scanning: Bindable(viewModel.catalog).scanning,
                creatingThumbnails: Bindable(viewModel.catalog).isCreatingThumbnails,
                nsImage: $nsImage,
                cgImage: $cgImage,
                isSorting: viewModel.catalog.isSorting,
            )
            .navigationTitle((viewModel.catalog.selectedSource?.name ?? "Files") +
                " (\(viewModel.catalog.filteredFiles.count) files)")
            .toolbar { toolbarContent }
            .alert(viewModel.presentation.alertTitle, isPresented: Bindable(viewModel.presentation).showingAlert) {
                switch viewModel.presentation.alertType {
                case .createJPGDiskCache:
                    Button("Create Cache") {
                        viewModel.fileOperations.startScanAndExtractJPGs()
                    }
                    .frame(width: 100)

                case .clearRatedFiles:
                    Button("Clear", role: .destructive) {
                        viewModel.culling.clearCurrentCatalogCullingState()
                    }
                    .frame(width: 100)

                case .none:
                    EmptyView()
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text(viewModel.presentation.alertMessage(catalogFileCount: viewModel.catalog.files.count))
            }
        } detail: {
            RawCullDetailContainerView(semanticSearchFeature: semanticSearchFeature,
                                       cgImage: $cgImage,
                                       nsImage: $nsImage,
                                       selectedFileID: Bindable(viewModel.selection).selectedFileID,
                                       abort: abort)
        }
        .toolbar(removing: .sidebarToggle)
        .task {
            columnVisibility = .doubleColumn
        }
        .task {
            let handlers = CreateFileHandlers().createFileHandlers(
                fileHandler: { _ in },
                maxfilesHandler: { _ in },
                estimatedTimeHandler: { _ in },
                memorypressurewarning: viewModel.catalogController.setMemoryPressureWarning,
                onExtractionNeeded: {},
            )
            await SharedMemoryCache.shared.setFileHandlers(handlers)
        }
        .fileImporter(isPresented: Bindable(viewModel.presentation).isShowingPicker, allowedContentTypes: [.folder]) { result in
            handlePickerResult(result)
        }
        .task(id: viewModel.catalog.selectedSource) {
            viewModel.catalogController.startCatalogLoad(for: viewModel.catalog.selectedSource)
        }
        .onChange(of: viewModel.catalog.sortOrder) { _, _ in
            Task(priority: .background) {
                await viewModel.catalogController.handleSortOrderChange()
            }
        }
        .overlay(alignment: .bottom) {
            if viewModel.presentation.memoryPressureWarning, !dismissedMemoryPressureWarning {
                MemoryWarningLabelView(
                    memoryWarningOpacity: $memoryWarningOpacity,
                    onAppearAction: startMemoryWarningFlash,
                    onClose: {
                        dismissedMemoryPressureWarning = true
                    },
                )
                .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .onChange(of: viewModel.presentation.memoryPressureWarning) { _, newValue in
            if newValue {
                startMemoryWarningFlash()
            } else {
                dismissedMemoryPressureWarning = false
            }
        }
    }

    // MARK: - Grid mode

    private var gridSplit: some View {
        GridThumbnailView(
            similarityFeature: similarityFeature,
            semanticSearchFeature: semanticSearchFeature,
            nsImage: $nsImage,
            cgImage: $cgImage,
        )
        .navigationTitle((viewModel.catalog.selectedSource?.name ?? "Files") +
            " (\(viewModel.catalog.filteredFiles.count) files)")
        .toolbar { toolbarContent }
    }

    // MARK: - Similarity grid mode

    private var similarityGridSplit: some View {
        SimilarityGridView(
            similarityFeature: similarityFeature,
            semanticSearchFeature: semanticSearchFeature,
            nsImage: $nsImage,
            cgImage: $cgImage,
        )
        .navigationTitle((viewModel.catalog.selectedSource?.name ?? "Files") +
            " (\(viewModel.catalog.filteredFiles.count) files)")
        .toolbar { toolbarContent }
    }

    // MARK: - Rated grid mode

    private var ratedGridSplit: some View {
        RatedPhotoGridView(
            catalogURL: viewModel.catalog.selectedSource?.url,
            onPhotoSelected: { file in
                viewModel.selection.selectedFileID = file.id
            },
        )
        .navigationTitle("Rated images")
        .toolbar { toolbarContent }
    }

    // MARK: - Comparison grid mode

    @ViewBuilder
    private var comparisonGridSplit: some View {
        if let groupID = viewModel.burstWorkflow.activeBurstComparisonGroupID,
           !viewModel.burstWorkflow.showsDetailedBurstComparison {
            BurstCullingWorkspaceView(
                groupID: groupID,
                onCompare: { viewModel.burstWorkflow.showsDetailedBurstComparison = true },
            )
            .navigationTitle((viewModel.catalog.selectedSource?.name ?? "Catalog") + " — Burst")
            .toolbar { toolbarContent }
        } else {
            NavigationSplitView(columnVisibility: $columnVisibility) {
                RAWCatalogSidebarView(
                    sources: Bindable(viewModel.catalog).sources,
                    selectedSource: Bindable(viewModel.catalog).selectedSource,
                    cullingModel: viewModel.ratings.cullingModel,
                )
            } detail: {
                ComparisonGridView(
                    sharpnessModel: viewModel.sharpnessModel,
                    selection: viewModel.selection,
                    showCandidateInspector: $showCandidateInspector,
                )
                .navigationTitle("Compare images")
                .toolbar { toolbarContent }
                .inspector(isPresented: $showCandidateInspector) {
                    CandidateInspectorView(context: candidateInspectorContext)
                }
            }
            .toolbar(removing: .sidebarToggle)
            .task {
                columnVisibility = .detailOnly
            }
            .fileImporter(isPresented: Bindable(viewModel.presentation).isShowingPicker, allowedContentTypes: [.folder]) { result in
                handlePickerResult(result)
            }
            .task(id: viewModel.catalog.selectedSource) {
                viewModel.catalogController.startCatalogLoad(for: viewModel.catalog.selectedSource)
            }
        }
    }

    // MARK: - AI analysis mode

    private var aiAnalysisSplit: some View {
        AIAnalysisView(
            qwenAnalysisFeature: qwenAnalysisFeature,
            objectAnalysisFeature: objectAnalysisFeature,
            combinedReviewFeature: combinedReviewFeature,
            deepAIReviewController: deepAIReviewController,
        )
        .navigationTitle("AI Analysis")
        .toolbar { toolbarContent }
    }

    private var combinedReviewSplit: some View {
        CombinedReviewWorkspaceView(
            feature: combinedReviewFeature,
            isEnabled: aiSettingsModel.combinedReviewEnabled,
        )
        .navigationTitle("Combined Review")
        .toolbar { toolbarContent }
    }

    private var candidateInspectorContext: CandidateInspectorContext? {
        guard let groupID = viewModel.burstWorkflow.activeBurstComparisonGroupID else { return nil }
        return CandidateInspectorContext.make(
            selectedFile: viewModel.selectedFile,
            result: viewModel.burstWorkflow.burstAnalysisResult(for: groupID),
            files: viewModel.catalog.files,
            saliencyInfo: viewModel.sharpnessModel.saliencyInfo,
            sharpnessScores: viewModel.sharpnessModel.scores,
            sharpnessBreakdowns: viewModel.sharpnessModel.breakdowns,
            focusPoints: viewModel.catalog.focusPoints,
            rating: viewModel.selectedFile.map { viewModel.ratings.getRating(for: $0) } ?? 0,
        )
    }

    // MARK: - Actions

    func abort() {
        viewModel.catalogController.abort()
    }

    private func startMemoryWarningFlash() {
        guard !reduceMotion else {
            memoryWarningOpacity = 0.8
            return
        }
        withAnimation(.easeInOut(duration: 1.5).repeatForever(autoreverses: true)) {
            memoryWarningOpacity = 0.8
        }
    }
}
