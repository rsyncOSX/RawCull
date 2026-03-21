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
    @Environment(SettingsViewModel.self) private var settings

    @Binding var nsImage: NSImage?
    @Binding var cgImage: CGImage?
    @Binding var zoomCGImageWindowFocused: Bool
    @Binding var zoomNSImageWindowFocused: Bool

    @State private var hoveredFileID: FileItem.ID?

    var openWindow: (String) -> Void

    var body: some View {
        VStack(alignment: .center) {
            ScrollViewReader { proxy in
                GeometryReader { geo in
                    ScrollView(.vertical) {
                        VStack {
                            Spacer(minLength: 0)
                            LazyVStack(alignment: .center, spacing: 10) {
                                ForEach(sortedFiles, id: \.id) { file in
                                    ImageItemView(
                                        viewModel: viewModel,
                                        file: file,
                                        selectedSource: viewModel.selectedSource,
                                        isHovered: hoveredFileID == file.id,
                                        thumbnailSize: settings.thumbnailSizeGrid,

                                        // One click for select only
                                        onToggle: {
                                            viewModel.selectFile(file)
                                        },
                                        // Double clik for tag Image
                                        onSelected: {
                                            Task {
                                                viewModel.selectFile(file)
                                                await viewModel.toggleTag(for: file)
                                            }
                                        },
                                    )
                                    .id(file.id)
                                    .onHover { isHovered in
                                        hoveredFileID = isHovered ? file.id : nil
                                    }
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 6)
                                            .stroke(Color.accentColor, lineWidth: isSelected(file) ? 2 : 0),
                                    )
                                    .shadow(
                                        color: isSelected(file) ? Color.accentColor.opacity(0.4) : .clear,
                                        radius: isSelected(file) ? 4 : 0,
                                    )
                                }
                            }
                            .padding(.vertical)
                            .padding(.horizontal, 20)
                            .frame(maxWidth: .infinity, alignment: .center)

                            Spacer(minLength: 0)
                        }
                        .frame(maxWidth: .infinity, minHeight: geo.size.height, alignment: .center)
                        .onChange(of: viewModel.selectedFileID) { _, newID in
                            if let newID {
                                withAnimation(.easeInOut(duration: 0.2)) {
                                    proxy.scrollTo(newID, anchor: .center)
                                }
                            }
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
        .onChange(of: viewModel.selectedFileID) { _, _ in
            if viewModel.selectedFileID != nil {
                viewModel.previouslySelectedFileID = viewModel.selectedFileID
            }

            if let index = viewModel.files.firstIndex(where: { $0.id == viewModel.selectedFileID }) {
                // Do not re-assign selectedFileID — it's already the value we searched for
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
        .focusable()
        .focusEffectDisabled(true)
        .onKeyPress(.upArrow) { navigateToUp(); return .handled }
        .onKeyPress(.downArrow) { navigateDown(); return .handled }
    }

    // MARK: - Private Helpers

    var cullingModel: CullingModel {
        viewModel.cullingModel
    }

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

    private func selectAndScroll(file: FileItem, proxy _: ScrollViewProxy) {
        viewModel.selectFile(file)
        // Scrolling is handled by onChange(of: viewModel.selectedFileID) to avoid double animation
    }

    private func moveSelectionUp(proxy: ScrollViewProxy) {
        let files = sortedFiles
        guard !files.isEmpty else { return }
        let currentIndex = files.firstIndex { $0.id == viewModel.selectedFileID } ?? 0
        let nextIndex = max(0, currentIndex - 1)
        selectAndScroll(file: files[nextIndex], proxy: proxy)
    }

    private func moveSelectionDown(proxy: ScrollViewProxy) {
        let files = sortedFiles
        guard !files.isEmpty else { return }
        let currentIndex = files.firstIndex { $0.id == viewModel.selectedFileID } ?? -1
        let nextIndex = min(files.count - 1, currentIndex + 1)
        selectAndScroll(file: files[nextIndex], proxy: proxy)
    }

    private func isSelected(_ file: FileItem) -> Bool {
        viewModel.selectedFileID == file.id
    }
}
