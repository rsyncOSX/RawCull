//
//  VerticalMainThumbnailsListView.swift
//  RawCull
//
//  Created by Thomas Evensen on 07/03/2026.
//

import SwiftUI

struct VerticalMainThumbnailsListView: View {
    @Environment(\.openWindow) var openWindow
    @Environment(GridThumbnailViewModel.self) var gridthumbnailviewmodel

    @Bindable var viewModel: RawCullViewModel
    @Binding var showhorizontalvertical: Bool

    @Binding var cgImage: CGImage?
    @Binding var nsImage: NSImage?
    @Binding var scale: CGFloat
    @Binding var lastScale: CGFloat
    @Binding var offset: CGSize

    @State var showInspector: Bool = true

    var body: some View {
        // let _ = Self._printChanges()
        if let file = viewModel.selectedFile {
            VStack(spacing: 20) {
                MainCachedThumbnailView(
                    scale: $scale,
                    lastScale: $lastScale,
                    offset: $offset,
                    url: file.url,
                )
                .padding()

                HStack {
                    VStack {
                        Text(file.name)
                            .font(.headline)
                        Text(file.url.deletingLastPathComponent().path())
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            .inspector(isPresented: $showInspector) {
                FileInspectorView(
                    file: $viewModel.selectedFile,
                    showDetailsTagView: $viewModel.showDetailsTagView,
                )
            }
            .padding()
            .onTapGesture(count: 2) {
                guard let selectedID = viewModel.selectedFile?.id,
                      let file = files.first(where: { $0.id == selectedID }) else { return }

                ZoomPreviewHandler.handle(
                    file: file,
                    useThumbnailAsZoomPreview: viewModel.useThumbnailAsZoomPreview,
                    setNSImage: { nsImage = $0 },
                    setCGImage: { cgImage = $0 },
                    openWindow: { id in openWindow(id: id) },
                )
            }
        } else {
            Spacer()

            ContentUnavailableView(
                "No Selection",
                systemImage: "doc.text",
                description: Text("Select a Image to view its properties."),
            )
        }

        Spacer()

        ImageTableHorizontalView(
            viewModel: viewModel,
            selectedSource: viewModel.selectedSource,
        )
        .padding()
        .toolbar { toolbarContent }
        .focusedSceneValue(\.tagimage, $viewModel.focustagimage)

        if viewModel.focustagimage == true { labeltagimage }
    }

    var labeltagimage: some View {
        Label("", systemImage: "play.fill")
            .onAppear {
                viewModel.focustagimage = false
                if let index = viewModel.files.firstIndex(where: { $0.id == viewModel.selectedFileID }) {
                    let fileitem = viewModel.files[index]
                    viewModel.selectFile(fileitem)
                    Task {
                        await viewModel.toggleTag(for: fileitem)
                    }
                }
            }
    }

    var files: [FileItem] {
        viewModel.files
    }

    var cullingModel: CullingModel {
        viewModel.cullingModel
    }
}

extension VerticalMainThumbnailsListView {
    @ToolbarContentBuilder
    var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .status) {
            Button(action: openGridThumbnailWindow) {
                Label("Grid View", systemImage: "square.grid.2x2")
            }
            .disabled(viewModel.selectedSource == nil || viewModel.filteredFiles.isEmpty)
            .help("Open thumbnail grid view")
        }

        ToolbarItem(placement: .status) {
            Button(action: opentaggedGridThumbnailWindow) {
                Label("Grid Tagged Images", systemImage: "square.grid.2x2.fill")
            }
            .disabled(viewModel.selectedSource == nil || viewModel.filteredFiles.isEmpty || showGridtaggedThumbnailWindow() == false)
            .help("Open tagged thumbnail grid view")
        }

        ToolbarItem(placement: .status) {
            Button(action: toggleshowhorizontal) {
                Label("Horizontal", systemImage: "arrow.up.and.down.text.horizontal")
            }
            .disabled(viewModel.selectedSource == nil || viewModel.filteredFiles.isEmpty)
            .help("Show Vertical thumbnails")
            .labelStyle(.iconOnly)
        }

        ToolbarItem(placement: .status) {
            Button(action: toggleshowsavedfiles) {
                Label("Details", systemImage: "square.and.arrow.down")
            }
            .help("Show SavedFiles")
        }

        ToolbarItem(placement: .status) {
            Button(action: toggleshowinspector) {
                Label("Toggle Inspector", systemImage: "rectangle.portrait.and.arrow.right")
            }
            .disabled(viewModel.selectedSource == nil || viewModel.filteredFiles.isEmpty)
            .help("Toggle Inspector")
            .labelStyle(.iconOnly)
        }
    }

    func toggleshowinspector() {
        showInspector.toggle()
    }

    func toggleshowhorizontal() {
        showhorizontalvertical.toggle()
    }

    func openGridThumbnailWindow() {
        gridthumbnailviewmodel.open(
            cullingModel: viewModel.cullingModel,
            selectedSource: viewModel.selectedSource,
            filteredFiles: viewModel.filteredFiles,
        )
        openWindow(id: WindowIdentifier.gridThumbnails.rawValue)
    }

    func opentaggedGridThumbnailWindow() {
        openWindow(id: WindowIdentifier.gridTaggedThumbnails.rawValue)
    }

    private func showGridtaggedThumbnailWindow() -> Bool {
        guard let catalogURL = viewModel.selectedSource?.url,
              let index = viewModel.cullingModel.savedFiles.firstIndex(where: { $0.catalog == catalogURL })
        else {
            return false
        }
        if let records = viewModel.cullingModel.savedFiles[index].filerecords {
            return !records.isEmpty
        }
        return false
    }

    func toggleshowsavedfiles() {
        viewModel.showSavedFiles.toggle()
    }
}
