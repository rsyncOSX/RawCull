import OSLog
import SwiftUI
import UniformTypeIdentifiers

extension KeyPath<FileItem, String>: @unchecked @retroactive Sendable {}

struct RawCullView: View {
    @Environment(\.openWindow) var openWindow
    @Environment(GridThumbnailViewModel.self) var gridthumbnailviewmodel

    @Binding var nsImage: NSImage?
    @Binding var cgImage: CGImage?
    @Binding var zoomCGImageWindowFocused: Bool
    @Binding var zoomNSImageWindowFocused: Bool

    @State var viewModel = RawCullViewModel()
    @State var savedSettings: SavedSettings?
    @State private var memoryWarningOpacity: Double = 0.3

    var body: some View {
        NavigationSplitView {
            // --- SIDEBAR ---
            CatalogSidebarView(
                sources: $viewModel.sources,
                selectedSource: $viewModel.selectedSource,
                isShowingPicker: $viewModel.isShowingPicker,
                cullingManager: viewModel.cullingModel
            )
        } content: {
            // --- MIDDLE COLUMN (TABLE) ---
            FileContentView(
                viewModel: viewModel,
                isShowingPicker: $viewModel.isShowingPicker,
                progress: $viewModel.progress,
                selectedSource: $viewModel.selectedSource,
                scanning: $viewModel.scanning,
                creatingThumbnails: $viewModel.creatingthumbnails,

                files: viewModel.files,
                issorting: viewModel.issorting,
                max: viewModel.max,

                filetableview: AnyView(filetableview)
            )
            .navigationTitle((viewModel.selectedSource?.name ?? "Files") +
                " (\(viewModel.filteredFiles.count) ARW files)")
            .searchable(
                text: $viewModel.searchText,
                placement: .toolbar,
                prompt: "Search in \(viewModel.selectedSource?.name ?? "catalog")..."
            )
            .toolbar { toolbarContent }
            .focusedSceneValue(\.togglerow, $viewModel.focustogglerow)
            .focusedSceneValue(\.pressEnter, $viewModel.focusPressEnter)
            .focusedSceneValue(\.hideInspector, $viewModel.focushideInspector)
            .focusedSceneValue(\.extractJPGs, $viewModel.focusExtractJPGs)
            .sheet(isPresented: $viewModel.showcopytask) {
                RawCullSheetContent(
                    viewModel: viewModel,
                    sheetType: $viewModel.sheetType,
                    selectedSource: $viewModel.selectedSource,
                    remotedatanumbers: $viewModel.remotedatanumbers,
                    showcopytask: $viewModel.showcopytask
                )
            }
            .alert(isPresented: $viewModel.showingAlert) {
                RawCullAlertView.alert(
                    type: viewModel.alertType,
                    selectedSource: viewModel.selectedSource,
                    cullingModel: viewModel.cullingModel,
                    actions: (
                        extractJPGS: extractAllJPGS,
                        clearCaches: {
                            Task {
                                await viewModel.clearMemoryCachesandTagging()
                            }
                        }
                    )
                )
            }
        } detail: {
            // --- DETAIL VIEW ---
            FileDetailView(
                cgImage: $cgImage,
                nsImage: $nsImage,
                selectedFileID: $viewModel.selectedFileID,
                scale: $viewModel.scale,
                lastScale: $viewModel.lastScale,
                offset: $viewModel.offset,
                files: viewModel.files,
                file: viewModel.selectedFile
            )

            // Move the conditional labels inside the ZStack so they participate in the ViewBuilder
            if viewModel.focustogglerow == true { labeltogglerow }
            if viewModel.focusaborttask { labelaborttask }
            if viewModel.focushideInspector == true { labelhideinspector }
            if viewModel.focusExtractJPGs { labelextractjpgs }
        }
        .task {
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

    var labeltogglerow: some View {
        Label("", systemImage: "play.fill")
            .onAppear {
                viewModel.focustogglerow = false
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

    /// MUST FIX
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
        if condition {
            transform(self)
        } else {
            self
        }
    }
}
