import OSLog
import SwiftUI
import UniformTypeIdentifiers

extension KeyPath<FileItem, String>: @unchecked @retroactive Sendable {}

struct RawCullMainView: View {
    @Environment(\.openWindow) var openWindow
    @Environment(GridThumbnailViewModel.self) var gridthumbnailviewmodel
    @Bindable var viewModel: RawCullViewModel

    @Binding var nsImage: NSImage?
    @Binding var cgImage: CGImage?
    @Binding var zoomCGImageWindowFocused: Bool
    @Binding var zoomNSImageWindowFocused: Bool

    @State var savedSettings: SavedSettings?
    @State private var memoryWarningOpacity: Double = 0.3
    @State private var columnVisibility = NavigationSplitViewVisibility.doubleColumn
    @State var showDetailOnly: Bool = false

    @State var showSavedFiles: Bool = false

    var body: some View {
        // let _ = Self._printChanges()
        if showDetailOnly {
            DetailOnlyThumbnailsListView(
                viewModel: viewModel,
                showDetailOnly: $showDetailOnly,
                cgImage: $cgImage,
                nsImage: $nsImage,
                scale: $viewModel.scale,
                lastScale: $viewModel.lastScale,
                offset: $viewModel.offset,
            )
        } else {
            NavigationSplitView(columnVisibility: $columnVisibility) {
                ARWCatalogSidebarView(
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
                    zoomCGImageWindowFocused: $zoomCGImageWindowFocused,
                    zoomNSImageWindowFocused: $zoomNSImageWindowFocused,

                    issorting: viewModel.issorting,
                    max: viewModel.max,
                )
                .navigationTitle((viewModel.selectedSource?.name ?? "Files") +
                    " (\(viewModel.filteredFiles.count) ARW files)")
                .searchable(
                    text: $viewModel.searchText,
                    placement: .toolbar,
                    prompt: "Search in \(viewModel.selectedSource?.name ?? "catalog")...",
                )
                .toolbar { toolbarContent }
                .sheet(isPresented: $viewModel.showcopyARWFilesView) {
                    CopyARWFilesView(
                        viewModel: viewModel,
                        sheetType: $viewModel.sheetType,
                        selectedSource: $viewModel.selectedSource,
                        remotedatanumbers: $viewModel.remotedatanumbers,
                        showcopytask: $viewModel.showcopyARWFilesView,
                    )
                }
                .alert(viewModel.alertTitle, isPresented: $viewModel.showingAlert) {
                    switch viewModel.alertType {
                    case .extractJPGs:
                        Button("Extract", role: .destructive) {
                            extractAllJPGS()
                        }
                        .frame(width: 100)

                    case .clearToggledFiles:
                        Button("Clear", role: .destructive) {
                            if let url = viewModel.selectedSource?.url {
                                viewModel.cullingModel.resetSavedFiles(in: url)
                            }
                        }
                        .frame(width: 100)

                    case .resetSavedFiles:
                        Button("Reset", role: .destructive) {
                            viewModel.cullingModel.savedFiles.removeAll()
                            Task {
                                await WriteSavedFilesJSON(viewModel.cullingModel.savedFiles)
                            }
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
                    scale: $viewModel.scale,
                    lastScale: $viewModel.lastScale,
                    offset: $viewModel.offset,
                    handleToggleSelection: handleToggleSelection,
                    abort: abort,
                )
            }

            .sheet(isPresented: $showSavedFiles) {
                SavedFilesView()
            }
            .focusedSceneValue(\.tagimage, $viewModel.focustagimage)
            .focusedSceneValue(\.hideInspector, $viewModel.focushideInspector)
            .focusedSceneValue(\.extractJPGs, $viewModel.focusExtractJPGs)
            .focusedSceneValue(\.aborttask, $viewModel.focusaborttask)
            .task {
                // Only scan new files if there is a change of source
                // guard viewModel.sourcechange == false else { return}

                savedSettings = await SettingsViewModel.shared.asyncgetsettings()

                let handlers = CreateFileHandlers().createFileHandlers(
                    fileHandler: { _ in },
                    maxfilesHandler: { _ in },
                    estimatedTimeHandler: { _ in },
                    memorypressurewarning: viewModel.memorypressurewarning,
                )
                // Set the handler for reporting memorypressurewarning
                await SharedMemoryCache.shared.setFileHandlers(handlers)
            }
            // --- RIGHT INSPECTOR ---
            // Inside your body, replace the old .inspector with:
            .if(viewModel.hideInspector == false) { view in
                view.inspector(isPresented: $viewModel.isInspectorPresented) {
                    FileInspectorView(file: $viewModel.selectedFile)
                }
            }
            .fileImporter(isPresented: $viewModel.isShowingPicker, allowedContentTypes: [.folder]) { result in
                handlePickerResult(result)
            }
            .task(id: viewModel.selectedSource) {
                guard viewModel.currentselectedSource != viewModel.selectedSource else { return }
                viewModel.currentselectedSource = viewModel.selectedSource

                Task(priority: .background) {
                    if let url = viewModel.selectedSource?.url {
                        viewModel.scanning.toggle()
                        await viewModel.handleSourceChange(url: url)
                    }
                }
            }
            .onChange(of: viewModel.sortOrder) { _, _ in
                Task(priority: .background) {
                    await viewModel.handleSortOrderChange()
                }
            }
            .onChange(of: viewModel.searchText) { _, _ in
                Task(priority: .background) {
                    await viewModel.handleSearchTextChange()
                }
            }
            .overlay(alignment: .bottom) {
                if viewModel.memorypressurewarning {
                    MemoryWarningLabelView(
                        memoryWarningOpacity: $memoryWarningOpacity,
                        onAppearAction: startMemoryWarningFlash,
                    )
                    .transition(.move(edge: .top).combined(with: .opacity))
                }
            }
            .onChange(of: viewModel.memorypressurewarning) { _, newValue in
                if newValue {
                    startMemoryWarningFlash()
                }
            }
        }
    }

    func abort() {
        viewModel.abort()
    }

    private func startMemoryWarningFlash() {
        // Create a continuous slow flashing animation
        withAnimation(.easeInOut(duration: 1.5).repeatForever(autoreverses: true)) {
            memoryWarningOpacity = 0.8
        }
    }
}
