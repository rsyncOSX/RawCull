//
//  DetailOnlyView.swift
//  RawCull
//
//  Created by Thomas Evensen on 07/03/2026.
//

import SwiftUI

struct DetailOnlyView: View {
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
        if let file = viewModel.selectedFile {
            VStack(spacing: 20) {
                CachedThumbnailView(
                    scale: $scale,
                    lastScale: $lastScale,
                    offset: $offset,
                    url: file.url
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

                JPGPreviewHandler.handle(
                    file: file,
                    setNSImage: { nsImage = $0 },
                    setCGImage: { cgImage = $0 },
                    openWindow: { id in openWindow(id: id) }
                )
            }
        } else {
            ContentUnavailableView(
                "No Selection",
                systemImage: "doc.text",
                description: Text("Select a file to view its properties.")
            )
        }

        Spacer()

        ARWFileTableImageView(
            viewModel: viewModel,
            files: viewModel.files,
            selectedSource: viewModel.selectedSource
        )
        .padding()
        .toolbar { toolbarContent }
    }

    var files: [FileItem] {
        viewModel.files
    }

    var focusPoints: [FocusPoint]? {
        viewModel.getFocusPoints()
    }

    var cullingModel: CullingModel {
        viewModel.cullingModel
    }

    private func handleToggleSelection(for file: FileItem) {
        Task {
            await cullingModel.toggleSelectionSavedFiles(
                in: file.url,
                toggledfilename: file.name
            )
        }
    }
}

extension DetailOnlyView {
    @ToolbarContentBuilder
    var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .navigation) {
            Button(action: toggleshowinspector) {
                Label("Toggle Inspector", systemImage: "rectangle.portrait.and.arrow.right")
            }
            .disabled(viewModel.selectedSource == nil || viewModel.filteredFiles.isEmpty)
            .help("Toggle Inspector")
        }

        ToolbarItem(placement: .navigation) {
            Button(action: toggleshowdetailonly) {
                Label("Details", systemImage: "return")
            }
            .disabled(viewModel.selectedSource == nil || viewModel.filteredFiles.isEmpty)
            .help("Close Details")
        }
    }

    func toggleshowinspector() {
        showInspector.toggle()
    }

    func toggleshowdetailonly() {
        showDetailOnly.toggle()
    }
}
