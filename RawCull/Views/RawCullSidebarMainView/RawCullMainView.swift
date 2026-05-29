import OSLog
import SwiftUI
import UniformTypeIdentifiers

extension KeyPath: @unchecked @retroactive Sendable where Root == FileItem {}

struct RawCullMainView: View {
    @Environment(\.openWindow) var openWindow
    @Environment(GridThumbnailViewModel.self) var gridthumbnailviewmodel

    @Bindable var viewModel: RawCullViewModel

    @State private var memoryWarningOpacity: Double = 0.3
    @State private var memoryMonitorModel = MemoryViewModel(pressureThresholdFactor: 0.85)
    @State var columnVisibility = NavigationSplitViewVisibility.doubleColumn

    @State private var cgImage: CGImage?
    @State private var nsImage: NSImage?
    @State private var showCandidateInspector = false

    var body: some View {
        ZStack {
            Group {
                switch viewModel.mainViewMode {
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
                }
            }

            if viewModel.zoomOverlayVisible {
                ZoomOverlayView(viewModel: viewModel)
                    .transition(.opacity)
                    .zIndex(10)
            }
        }
        .sheet(item: $viewModel.activeSheet) { sheet in
            switch sheet {
            case .stats:
                ScanStatsSheetView(viewModel: viewModel)

            case .scoringParams:
                ScoringParametersSheetView(
                    config: Bindable(viewModel.sharpnessModel.focusMaskModel).config,
                    thumbnailMaxPixelSize: Bindable(viewModel.sharpnessModel).thumbnailMaxPixelSize,
                    scoringQuality: Bindable(viewModel.sharpnessModel).scoringQuality,
                    scoringSource: Bindable(viewModel.sharpnessModel).scoringSource,
                )
            }
        }
        .sheet(isPresented: $viewModel.showSavedFiles) {
            SavedFilesView()
        }
        .sheet(item: $viewModel.rawDiagnosticsPresentation) { presentation in
            RawFileDiagnosticsView(log: presentation.log) {
                viewModel.rawDiagnosticsPresentation = nil
            }
        }
        .sheet(isPresented: $viewModel.showcopyARWFilesView) {
            CopyARWFilesView(
                viewModel: viewModel,
                sheetType: $viewModel.sheetType,
                selectedSource: $viewModel.selectedSource,
                remotedatanumbers: $viewModel.remotedatanumbers,
                showcopytask: $viewModel.showcopyARWFilesView,
            )
        }
        .onChange(of: viewModel.mainViewMode) { _, newMode in
            if newMode == .grid || newMode == .similarityGrid {
                gridthumbnailviewmodel.open(
                    cullingModel: viewModel.cullingModel,
                    selectedSource: viewModel.selectedSource,
                    filteredFiles: viewModel.filteredFiles,
                )
            } else {
                gridthumbnailviewmodel.close()
            }
        }
    }

    // MARK: - Loupe mode (3-column split)

    private var loupeSplit: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            RAWCatalogSidebarView(
                sources: $viewModel.sources,
                selectedSource: $viewModel.selectedSource,
                isShowingPicker: $viewModel.isShowingPicker,
                cullingModel: viewModel.cullingModel,
            )
        } content: {
            SidebarARWCatalogFileView(
                viewModel: viewModel,
                isShowingPicker: $viewModel.isShowingPicker,
                progress: $viewModel.progress,
                selectedSource: $viewModel.selectedSource,
                scanning: $viewModel.scanning,
                creatingThumbnails: $viewModel.creatingthumbnails,
                nsImage: $nsImage,
                cgImage: $cgImage,
                issorting: viewModel.issorting,
                max: viewModel.max,
            )
            .navigationTitle((viewModel.selectedSource?.name ?? "Files") +
                " (\(viewModel.filteredFiles.count) files)")
            .toolbar { toolbarContent }
            .alert(viewModel.alertTitle, isPresented: $viewModel.showingAlert) {
                switch viewModel.alertType {
                case .extractJPGs:
                    Button("Extract", role: .destructive) {
                        extractFilteredFilesJPGS()
                    }
                    .frame(width: 100)

                case .createJPGDiskCache:
                    Button("Create Cache") {
                        viewModel.startScanAndExtractJPGs()
                    }
                    .frame(width: 100)

                case .clearRatedFiles:
                    Button("Clear", role: .destructive) {
                        viewModel.clearCurrentCatalogCullingState()
                    }
                    .frame(width: 100)

                case .none:
                    EmptyView()
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text(viewModel.alertMessage)
            }
        } detail: {
            RawCullDetailContainerView(
                viewModel: viewModel,
                cgImage: $cgImage,
                nsImage: $nsImage,
                selectedFileID: $viewModel.selectedFileID,
                abort: abort,
            )
        }
        .task {
            columnVisibility = .doubleColumn
        }
        .focusedSceneValue(\.extractJPGs, $viewModel.focusExtractJPGs)
        .focusedSceneValue(\.aborttask, $viewModel.focusaborttask)
        .task {
            let handlers = CreateFileHandlers().createFileHandlers(
                fileHandler: { _ in },
                maxfilesHandler: { _ in },
                estimatedTimeHandler: { _ in },
                memorypressurewarning: viewModel.setMemoryPressureWarning,
                onExtractionNeeded: {},
            )
            await SharedMemoryCache.shared.setFileHandlers(handlers)
        }
        .inspector(isPresented: $viewModel.hideInspector) {
            FileInspectorView(
                file: viewModel.selectedFile,
            )
        }
        .fileImporter(isPresented: $viewModel.isShowingPicker, allowedContentTypes: [.folder]) { result in
            handlePickerResult(result)
        }
        .task(id: viewModel.selectedSource) {
            viewModel.startCatalogLoad(for: viewModel.selectedSource)
        }
        .onChange(of: viewModel.sortOrder) { _, _ in
            Task(priority: .background) {
                await viewModel.handleSortOrderChange()
            }
        }
        .overlay(alignment: .bottom) {
            if viewModel.memoryPressureWarning {
                MemoryWarningLabelView(
                    style: .full,
                    memoryWarningOpacity: $memoryWarningOpacity,
                    onAppearAction: startMemoryWarningFlash,
                )
                .transition(.move(edge: .top).combined(with: .opacity))
            } else if viewModel.softMemoryWarning {
                MemoryWarningLabelView(style: .soft)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .task {
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(5))
                await memoryMonitorModel.updateMemoryStats()
                let exceeded = memoryMonitorModel.usedMemory >= memoryMonitorModel.memoryPressureThreshold
                if exceeded {
                    let macOSLevel = SharedMemoryCache.shared.currentPressureLevel
                    viewModel.softMemoryWarning = macOSLevel == .normal
                } else {
                    viewModel.softMemoryWarning = false
                }
            }
        }
        .onChange(of: viewModel.memoryPressureWarning) { _, newValue in
            if newValue {
                startMemoryWarningFlash()
            }
        }
    }

    // MARK: - Grid mode

    private var gridSplit: some View {
        GridThumbnailView(
            viewModel: viewModel,
            nsImage: $nsImage,
            cgImage: $cgImage,
        )
        .navigationTitle((viewModel.selectedSource?.name ?? "Files") +
            " (\(viewModel.filteredFiles.count) files)")
        .toolbar { toolbarContent }
    }

    // MARK: - Similarity grid mode

    private var similarityGridSplit: some View {
        SimilarityGridView(
            viewModel: viewModel,
            nsImage: $nsImage,
            cgImage: $cgImage,
        )
        .navigationTitle((viewModel.selectedSource?.name ?? "Files") +
            " (\(viewModel.filteredFiles.count) files)")
        .toolbar { toolbarContent }
    }

    // MARK: - Rated grid mode

    private var ratedGridSplit: some View {
        RatedPhotoGridView(
            viewModel: viewModel,
            catalogURL: viewModel.selectedSource?.url,
            onPhotoSelected: { file in
                viewModel.selectedFileID = file.id
            },
        )
        .navigationTitle("Rated images")
        .toolbar { toolbarContent }
    }

    // MARK: - Comparison grid mode

    private var comparisonGridSplit: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            RAWCatalogSidebarView(
                sources: $viewModel.sources,
                selectedSource: $viewModel.selectedSource,
                isShowingPicker: $viewModel.isShowingPicker,
                cullingModel: viewModel.cullingModel,
            )
        } detail: {
            ComparisonGridView(
                viewModel: viewModel,
                showCandidateInspector: $showCandidateInspector,
            )
            .navigationTitle("Compare images")
            .toolbar { toolbarContent }
            .inspector(isPresented: $showCandidateInspector) {
                CandidateInspectorView(context: candidateInspectorContext)
            }
        }
        .task {
            columnVisibility = .detailOnly
        }
        .fileImporter(isPresented: $viewModel.isShowingPicker, allowedContentTypes: [.folder]) { result in
            handlePickerResult(result)
        }
        .task(id: viewModel.selectedSource) {
            viewModel.startCatalogLoad(for: viewModel.selectedSource)
        }
    }

    private var candidateInspectorContext: CandidateInspectorContext? {
        guard let groupID = viewModel.activeBurstComparisonGroupID else { return nil }
        return CandidateInspectorContext.make(
            selectedFile: viewModel.selectedFile,
            result: viewModel.burstAnalysisResult(for: groupID),
            files: viewModel.files,
            saliencyInfo: viewModel.sharpnessModel.saliencyInfo,
            sharpnessScores: viewModel.sharpnessModel.scores,
            sharpnessBreakdowns: viewModel.sharpnessModel.breakdowns,
            focusPoints: viewModel.focusPoints,
            rating: viewModel.selectedFile.map { viewModel.getRating(for: $0) } ?? 0,
        )
    }

    // MARK: - Actions

    func abort() {
        viewModel.abort()
    }

    private func startMemoryWarningFlash() {
        withAnimation(.easeInOut(duration: 1.5).repeatForever(autoreverses: true)) {
            memoryWarningOpacity = 0.8
        }
    }
}
