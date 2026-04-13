//
//  HorizontalMainThumbnailsListView.swift
//  RawCull
//
//  Created by Thomas Evensen on 07/03/2026.
//

import SwiftUI

struct HorizontalMainThumbnailsListView: View {
    @Environment(\.openWindow) var openWindow
    @Environment(GridThumbnailViewModel.self) var gridthumbnailviewmodel

    @Bindable var viewModel: RawCullViewModel
    @Binding var showhorizontalvertical: Bool

    @Binding var cgImage: CGImage?
    @Binding var nsImage: NSImage?

    @State var showInspector: Bool = true
    @State var showGridThumbnail: Bool = false

    var body: some View {
        // let _ = Self._printChanges()

        if showGridThumbnail {
            GridThumbnailView(
                viewModel: viewModel,
                isPresented: $showGridThumbnail,
                nsImage: $nsImage,
                cgImage: $cgImage,
            )
        } else {
            if let file = viewModel.selectedFile {
                VStack(spacing: 20) {
                    MainThumbnailImageView(
                        url: file.url,
                        file: file,
                    )
                    .padding()
                }
                .inspector(isPresented: $showInspector) {
                    FileInspectorView(
                        file: $viewModel.selectedFile,
                    )
                }
                .padding()
                .onTapGesture(count: 2) {
                    guard let selectedID = viewModel.selectedFile?.id,
                          let file = files.first(where: { $0.id == selectedID }) else { return }

                    viewModel.zoomExtractionTask?.cancel()
                    viewModel.zoomExtractionTask = ZoomPreviewHandler.handle(
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
                    description: Text("Select an image to view its details."),
                )
            }

            Spacer()

            ImageTableHorizontalView(
                viewModel: viewModel,
            )
            .padding()
            .toolbar { toolbarContent }
            // .focusedSceneValue(\.tagimage, $viewModel.focustagimage)

            if viewModel.focustagimage == true {
                TagImageFocusView(
                    focustagimage: $viewModel.focustagimage,
                    files: viewModel.files,
                    selectedFileID: viewModel.selectedFileID,
                    handleToggleSelection: handleToggleSelection,
                )
            }
        }
    }

    private func handleToggleSelection(for file: FileItem) {
        Task {
            viewModel.selectFile(file)
            await viewModel.toggleTag(for: file)
        }
    }

    var files: [FileItem] {
        viewModel.files
    }
}

extension HorizontalMainThumbnailsListView {
    var toolbarContent: some ToolbarContent {
        SharedMainToolbarContent(
            viewModel: viewModel,
            isHorizontal: true,
            toggleLayout: toggleshowhorizontal,
            toggleInspector: toggleshowinspector,
            openGridThumbnail: openGridThumbnailWindow,
        )
    }

    func toggleshowinspector() {
        showInspector.toggle()
    }

    func toggleshowhorizontal() {
        showhorizontalvertical.toggle()
    }

    func openGridThumbnailWindow() {
        viewModel.ratingFilter = .all
        Task(priority: .background) { await viewModel.handleSortOrderChange() }
        gridthumbnailviewmodel.open(
            cullingModel: viewModel.cullingModel,
            selectedSource: viewModel.selectedSource,
            filteredFiles: viewModel.filteredFiles,
        )
        showGridThumbnail = true
    }
}
