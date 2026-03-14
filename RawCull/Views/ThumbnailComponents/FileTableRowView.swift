//
//  FileTableRowView.swift
//  RawCull
//

import OSLog
import SwiftUI
import UniformTypeIdentifiers

struct FileTableRowView: View {
    @Bindable var viewModel: RawCullViewModel

    @Binding var nsImage: NSImage?
    @Binding var cgImage: CGImage?
    @Binding var zoomCGImageWindowFocused: Bool
    @Binding var zoomNSImageWindowFocused: Bool

    var openWindow: (String) -> Void

    var body: some View {
        let filteredFiles = viewModel.filteredFiles.compactMap { file in
            (viewModel.getRating(for: file) >= viewModel.rating) ? file : nil
        }

        VStack(alignment: .leading) {
            Table(
                filteredFiles,
                selection: $viewModel.selectedFileID,
                sortOrder: $viewModel.sortOrder,
            ) {
                TableColumn("", value: \.id) { file in
                    Button(action: {
                        handleToggleSelection(for: file)
                    }, label: {
                        Image(systemName: marktoggle(for: file) ? "checkmark.square.fill" : "square")
                            .foregroundStyle(.blue)
                    })
                    .buttonStyle(.plain)
                }
                .width(30)

                TableColumn("Rating") { file in
                    RatingView(
                        rating: viewModel.getRating(for: file),
                        onChange: { newRating in
                            if !marktoggle(for: file) {
                                handleToggleSelection(for: file)
                            }
                            viewModel.updateRating(for: file, rating: newRating)
                        },
                    )
                }
                .width(90)

                TableColumn("Name", value: \.name) { file in
                    HStack(spacing: 8) {
                        if file.id == viewModel.previouslySelectedFileID {
                            VStack {
                                Spacer()
                                RoundedRectangle(cornerRadius: 2)
                                    .fill(.blue)
                                    .frame(width: 3)
                                Spacer()
                            }
                        }
                        Text(file.name)
                    }
                }

                TableColumn("Size", value: \.size) { file in
                    Text(file.formattedSize).monospacedDigit()
                }
                .width(75)

                TableColumn("Created", value: \.dateModified) { file in
                    Text(file.dateModified, style: .date)
                }
            }
        }
        .onChange(of: viewModel.selectedFileID) { _, _ in
            if viewModel.selectedFileID != nil {
                viewModel.previouslySelectedFileID = viewModel.selectedFileID
            }

            if let index = viewModel.files.firstIndex(where: { $0.id == viewModel.selectedFileID }) {
                viewModel.selectedFileID = viewModel.files[index].id
                viewModel.selectedFile = viewModel.files[index]

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

    private func handleToggleSelection(for file: FileItem) {
        Task {
            await viewModel.cullingModel.toggleSelectionSavedFiles(
                in: file.url,
                toggledfilename: file.name,
            )
        }
    }
}
