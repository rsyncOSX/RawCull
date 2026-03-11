import OSLog
import SwiftUI
import UniformTypeIdentifiers

extension KeyPath<FileItem, String>: @unchecked @retroactive Sendable {}

struct RawCullView: View {
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
                offset: $viewModel.offset
            )
        } else {
            NavigationSplitView(columnVisibility: $columnVisibility) {
                ARWCatalogSidebarView(
                    sources: $viewModel.sources,
                    selectedSource: $viewModel.selectedSource,
                    isShowingPicker: $viewModel.isShowingPicker,
                    cullingModel: viewModel.cullingModel
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
                    max: viewModel.max
                )
                .navigationTitle((viewModel.selectedSource?.name ?? "Files") +
                    " (\(viewModel.filteredFiles.count) ARW files)")
                .searchable(
                    text: $viewModel.searchText,
                    placement: .toolbar,
                    prompt: "Search in \(viewModel.selectedSource?.name ?? "catalog")..."
                )
                .toolbar { toolbarContent }
                .sheet(isPresented: $viewModel.showcopyARWFilesView) {
                    CopyARWFilesView(
                        viewModel: viewModel,
                        sheetType: $viewModel.sheetType,
                        selectedSource: $viewModel.selectedSource,
                        remotedatanumbers: $viewModel.remotedatanumbers,
                        showcopytask: $viewModel.showcopyARWFilesView
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
                FileDetailView(
                    viewModel: viewModel,
                    cgImage: $cgImage,
                    nsImage: $nsImage,
                    selectedFileID: $viewModel.selectedFileID,
                    scale: $viewModel.scale,
                    lastScale: $viewModel.lastScale,
                    offset: $viewModel.offset,
                    file: viewModel.selectedFile
                )

                // Move the conditional labels inside the ZStack so they participate in the ViewBuilder
                if viewModel.focustagimage == true { labeltageimage }
                if viewModel.focusaborttask { labelaborttask }
                if viewModel.focushideInspector == true { labelhideinspector }
                if viewModel.focusExtractJPGs { labelextractjpgs }
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
                    memorypressurewarning: viewModel.memorypressurewarning
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
            .onChange(of: viewModel.sortOrder) {
                Task(priority: .background) {
                    await viewModel.handleSortOrderChange()
                }
            }
            .onChange(of: viewModel.searchText) {
                Task(priority: .background) {
                    await viewModel.handleSearchTextChange()
                }
            }
            .overlay(alignment: .bottom) {
                if viewModel.memorypressurewarning {
                    memoryWarningLabel
                        .transition(.move(edge: .top).combined(with: .opacity))
                }
            }
            .onChange(of: viewModel.memorypressurewarning) {
                if viewModel.memorypressurewarning {
                    startMemoryWarningFlash()
                }
            }
        }
    }

    var labelhideinspector: some View {
        Label("", systemImage: "play.fill")
            .onAppear {
                viewModel.focushideInspector = false
                if viewModel.hideInspector == true {
                    viewModel.hideInspector = false
                } else {
                    viewModel.hideInspector = true
                }
            }
    }

    var labeltageimage: some View {
        Label("", systemImage: "play.fill")
            .onAppear {
                viewModel.focustagimage = false
                if let index = viewModel.files.firstIndex(where: { $0.id == viewModel.selectedFileID }) {
                    let fileitem = viewModel.files[index]
                    handleToggleSelection(for: fileitem)
                }
            }
    }

    var labelaborttask: some View {
        Label("", systemImage: "play.fill")
            .onAppear {
                viewModel.focusaborttask = false
                abort()
            }
    }

    var labelextractjpgs: some View {
        Label("", systemImage: "play.fill")
            .onAppear {
                guard viewModel.selectedSource != nil else { return }
                viewModel.alertType = .extractJPGs
                viewModel.showingAlert = true
            }
    }

    var memoryWarningLabel: some View {
        HStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 16, weight: .semibold))

            VStack(alignment: .leading, spacing: 2) {
                Text("⚠️ Memory Warning")
                    .font(.system(size: 14, weight: .semibold))
                Text("System memory pressure detected. Cache has been reduced.")
                    .font(.system(size: 12, weight: .regular))
                    .foregroundStyle(.secondary)
            }

            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(Color.red.opacity(memoryWarningOpacity))
        .foregroundStyle(.white)
        .cornerRadius(8)
        .padding(12)
        .onAppear {
            startMemoryWarningFlash()
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

extension View {
    @ViewBuilder
    func `if`<Content: View>(_ condition: Bool, transform: (Self) -> Content) -> some View {
        if condition { transform(self) } else { self }
    }
}
