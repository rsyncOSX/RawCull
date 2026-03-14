//
//  DetailOnlyThumbnailsListView.swift
//  RawCull
//
//  Created by Thomas Evensen on 07/03/2026.
//

import SwiftUI

struct DetailOnlyThumbnailsListView: View {
    @Environment(\.openWindow) var openWindow

    @Bindable var viewModel: RawCullViewModel
    @Binding var showDetailOnly: Bool

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
                FileInspectorView(file: $viewModel.selectedFile)
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

        FileTableImageView(
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
                    handleTagImage(for: fileitem)
                }
            }
    }

    private func handleTagImage(for file: FileItem) {
        Task {
            await cullingModel.toggleSelectionSavedFiles(
                in: file.url,
                toggledfilename: file.name,
            )
        }
    }

    var files: [FileItem] {
        viewModel.files
    }

    var cullingModel: CullingModel {
        viewModel.cullingModel
    }
}

extension DetailOnlyThumbnailsListView {
    @ToolbarContentBuilder
    var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .primaryAction) {
            Button(action: toggleshowinspector) {
                Label("Toggle Inspector", systemImage: "rectangle.portrait.and.arrow.right")
            }
            .disabled(viewModel.selectedSource == nil || viewModel.filteredFiles.isEmpty)
            .help("Toggle Inspector")
            .labelStyle(.iconOnly)
        }

        ToolbarItem(placement: .status) {
            Button(action: toggleshowdetailonly) {
                Label("Details", systemImage: "return")
            }
            .disabled(viewModel.selectedSource == nil || viewModel.filteredFiles.isEmpty)
            .help("Close Details")
            .labelStyle(.iconOnly)
        }
    }

    func toggleshowinspector() {
        showInspector.toggle()
    }

    func toggleshowdetailonly() {
        viewModel.selectedFile = nil
        viewModel.selectedFileID = nil
        showDetailOnly.toggle()
    }
}
