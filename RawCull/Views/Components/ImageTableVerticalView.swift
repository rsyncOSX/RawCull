//
//  ImageTableVerticalView.swift
//  RawCull
//
//  Created by Thomas Evensen on 12/03/2026.
//

import OSLog
import SwiftUI
import UniformTypeIdentifiers

struct ImageTableVerticalView: View {
    @Bindable var viewModel: RawCullViewModel

    @Binding var nsImage: NSImage?
    @Binding var cgImage: CGImage?
    @Binding var zoomCGImageWindowFocused: Bool
    @Binding var zoomNSImageWindowFocused: Bool

    var openWindow: (String) -> Void

    var body: some View {
        let filteredFiles = viewModel.filteredFiles.filter { file in
            viewModel.getRating(for: file) >= viewModel.rating
        }
        let sortedFiles = filteredFiles.sorted { lhs, rhs in
            lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
        }

        VStack(alignment: .leading) {
            ScrollView(.vertical) {
                LazyVStack(spacing: 2) {
                    ForEach(sortedFiles, id: \.id) { file in
                        PhotoItemView(
                            photo: file.name,
                            photoURL: file.url,
                            onSelected: {
                                handleToggleSelection(for: file)
                            },
                            cullingModel: viewModel.cullingModel,
                        )
                    }
                }
            }
            .fixedSize(horizontal: true, vertical: false)
            .padding()

            // Bottom row tagged Images.
            if showPhotoGridView() {
                Divider()

                PhotoGridView(
                    cullingModel: viewModel.cullingModel,
                    files: viewModel.filteredFiles,
                    photoURL: viewModel.selectedSource?.url,
                    onPhotoSelected: { file in
                        viewModel.selectedFileID = file.id
                        viewModel.selectedFile = file
                        viewModel.isInspectorPresented = true
                    },
                )
            }
        }
        .onChange(of: viewModel.selectedFileID) { _, _ in
            if viewModel.selectedFileID != nil {
                viewModel.previouslySelectedFileID = viewModel.selectedFileID
            }

            if let index = viewModel.files.firstIndex(where: { $0.id == viewModel.selectedFileID }) {
                viewModel.selectedFileID = viewModel.files[index].id
                viewModel.selectedFile = viewModel.files[index]
                viewModel.isInspectorPresented = true

                let file = viewModel.files[index]
                if zoomCGImageWindowFocused || zoomNSImageWindowFocused {
                    ZoomPreviewHandler.handle(
                        file: file,
                        useThumbnailAsZoomPreview: viewModel.useThumbnailAsZoomPreview,
                        setNSImage: { nsImage = $0 },
                        setCGImage: { cgImage = $0 },
                        openWindow: { _ in },
                    )
                }
            } else {
                viewModel.isInspectorPresented = false
            }
        }
        .contextMenu(forSelectionType: FileItem.ID.self) { _ in
        } primaryAction: { _ in
            guard let selectedID = viewModel.selectedFileID,
                  let file = viewModel.files.first(where: { $0.id == selectedID }) else { return }

            ZoomPreviewHandler.handle(
                file: file,
                useThumbnailAsZoomPreview: viewModel.useThumbnailAsZoomPreview,
                setNSImage: { nsImage = $0 },
                setCGImage: { cgImage = $0 },
                openWindow: { id in openWindow(id) },
            )
        }
        .onKeyPress(.space) {
            guard let selectedID = viewModel.selectedFileID,
                  let file = viewModel.files.first(where: { $0.id == selectedID }) else { return .handled }

            ZoomPreviewHandler.handle(
                file: file,
                useThumbnailAsZoomPreview: viewModel.useThumbnailAsZoomPreview,
                setNSImage: { nsImage = $0 },
                setCGImage: { cgImage = $0 },
                openWindow: { id in openWindow(id) },
            )
            return .handled
        }
    }

    // MARK: - Private Helpers

    private func marktoggle(for file: FileItem) -> Bool {
        if let index = viewModel.cullingModel.savedFiles.firstIndex(where: { $0.catalog == viewModel.selectedSource?.url }),
           let filerecords = viewModel.cullingModel.savedFiles[index].filerecords {
            return filerecords.contains { $0.fileName == file.name }
        }
        return false
    }

    private func showPhotoGridView() -> Bool {
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

    private func handleToggleSelection(for file: FileItem) {
        Task {
            await viewModel.cullingModel.toggleSelectionSavedFiles(
                in: file.url,
                toggledfilename: file.name,
            )
        }
    }
}
