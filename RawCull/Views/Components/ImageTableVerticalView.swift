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
        VStack(alignment: .leading) {
            ScrollViewReader { proxy in
                GeometryReader { geo in
                    ScrollView(.vertical) {
                        VStack {
                            Spacer(minLength: 0)
                            LazyVStack(alignment: .center, spacing: 10) {
                                ForEach(sortedFiles, id: \.id) { file in
                                    PhotoItemView(
                                        photo: file.name,
                                        photoURL: file.url,
                                        onSelected: {
                                            selectAndScroll(file: file, proxy: proxy)
                                        },
                                        cullingModel: viewModel.cullingModel,
                                    )
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 6)
                                            .stroke(Color.accentColor, lineWidth: isSelected(file) ? 2 : 0),
                                    )
                                    .shadow(
                                        color: isSelected(file) ? Color.accentColor.opacity(0.4) : .clear,
                                        radius: isSelected(file) ? 4 : 0,
                                    )
                                    .id(file.id)
                                }
                            }
                            .padding(.vertical)
                            Spacer(minLength: 0)
                        }
                        .frame(minHeight: geo.size.height)
                    }
                    .onChange(of: viewModel.selectedFileID) { _, newID in
                        if let newID {
                            withAnimation(.easeInOut(duration: 0.2)) {
                                proxy.scrollTo(newID, anchor: .center)
                            }
                        }
                    }
                    .overlay(alignment: .trailing) {
                        VStack(spacing: 8) {
                            Button {
                                moveSelectionUp(proxy: proxy)
                            } label: {
                                Image(systemName: "chevron.up")
                                    .font(.caption)
                            }
                            .buttonStyle(.plain)
                            .help("Scroll up")

                            Button {
                                moveSelectionDown(proxy: proxy)
                            } label: {
                                Image(systemName: "chevron.down")
                                    .font(.caption)
                            }
                            .buttonStyle(.plain)
                            .help("Scroll down")
                        }
                        .padding(8)
                        .background(.ultraThinMaterial, in: Capsule())
                        .overlay { Capsule().strokeBorder(.primary.opacity(0.1), lineWidth: 0.5) }
                        .padding(.trailing, 6)
                    }
                }
            }

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
        .focusable()
        .focusEffectDisabled(true)
        .onKeyPress(.upArrow) { navigateToUp(); return .handled }
        .onKeyPress(.downArrow) { navigateDown(); return .handled }
    }

    // MARK: - Private Helpers
    
    private func navigateToUp() {
        guard let current = viewModel.selectedFile,
              let index = sortedFiles.firstIndex(where: { $0.id == current.id }),
              index - 1 >= 0 else { return }
        viewModel.selectedFile = sortedFiles[index - 1]
        viewModel.selectedFileID = sortedFiles[index - 1].id
    }
    
    private func navigateDown() {
        guard let current = viewModel.selectedFile,
              let index = sortedFiles.firstIndex(where: { $0.id == current.id }),
              index + 1 < sortedFiles.count else { return }
        viewModel.selectedFile = sortedFiles[index + 1]
        viewModel.selectedFileID = sortedFiles[index + 1].id
    }

    private var filteredFiles: [FileItem] {
        viewModel.filteredFiles.filter { file in
            viewModel.getRating(for: file) >= viewModel.rating
        }
    }

    private var sortedFiles: [FileItem] {
        filteredFiles.sorted { lhs, rhs in
            lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
        }
    }

    private func scrollTo(_ file: FileItem, proxy: ScrollViewProxy) {
        withAnimation(.easeInOut(duration: 0.2)) {
            proxy.scrollTo(file.id, anchor: .center)
        }
    }

    private func selectAndScroll(file: FileItem, proxy: ScrollViewProxy) {
        selectFile(file)
        scrollTo(file, proxy: proxy)
    }

    private func moveSelectionUp(proxy: ScrollViewProxy) {
        guard !sortedFiles.isEmpty else { return }
        let currentIndex = sortedFiles.firstIndex { $0.id == viewModel.selectedFileID } ?? 0
        let nextIndex = max(0, currentIndex - 1)
        let file = sortedFiles[nextIndex]
        selectAndScroll(file: file, proxy: proxy)
    }

    private func moveSelectionDown(proxy: ScrollViewProxy) {
        guard !sortedFiles.isEmpty else { return }
        let currentIndex = sortedFiles.firstIndex { $0.id == viewModel.selectedFileID } ?? -1
        let nextIndex = min(sortedFiles.count - 1, currentIndex + 1)
        let file = sortedFiles[nextIndex]
        selectAndScroll(file: file, proxy: proxy)
    }

    private func selectFile(_ file: FileItem) {
        viewModel.selectedFileID = file.id
        viewModel.selectedFile = file
        viewModel.isInspectorPresented = true
    }

    private func isSelected(_ file: FileItem) -> Bool {
        viewModel.selectedFileID == file.id
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

}
