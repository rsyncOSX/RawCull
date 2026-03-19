//
//  ImageTableHorizontalView.swift
//  RawCull
//
//  Created by Thomas Evensen on 06/03/2026.
//

import SwiftUI

struct ImageTableHorizontalView: View {
    @Bindable var viewModel: RawCullViewModel

    let selectedSource: ARWSourceCatalog?

    @State private var hoveredFileID: FileItem.ID?
    @State private var savedSettings: SavedSettings?

    var body: some View {
        VStack(spacing: 0) {
            ScrollViewReader { proxy in
                if let savedSettings {
                    ScrollView(.horizontal) {
                        LazyHStack(spacing: 4) {
                            ForEach(sortedFiles, id: \.id) { file in
                                ImageItemView(
                                    viewModel: viewModel,
                                    file: file,
                                    selectedSource: selectedSource,
                                    isHovered: hoveredFileID == file.id,
                                    thumbnailSize: savedSettings.thumbnailSizeGrid,

                                    // One click for select only
                                    onToggle: { handleToggleSelection(for: file) },
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
                            }
                        }
                    }
                    .frame(height: CGFloat(savedSettings.thumbnailSizeGrid) + 40)
                    .onChange(of: viewModel.selectedFile?.id) { _, newID in
                        if let newID {
                            withAnimation {
                                proxy.scrollTo(newID, anchor: .center)
                            }
                        }
                    }
                    .task(id: viewModel.selectedSource) {
                        await ThumbnailLoader.shared.cancelAll()
                    }
                    .overlay(alignment: .top) {
                        HStack(spacing: 8) {
                            Button {
                                moveSelectionUp(proxy: proxy)
                            } label: {
                                Image(systemName: "chevron.left")
                                    .font(.caption)
                            }
                            .buttonStyle(.plain)
                            .help("Scroll up")

                            Button {
                                moveSelectionDown(proxy: proxy)
                            } label: {
                                Image(systemName: "chevron.right")
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
        }
        .task {
            savedSettings = await SettingsViewModel.shared.asyncgetsettings()
        }
        .focusable()
        .focusEffectDisabled(true)
        .onKeyPress(.leftArrow) { navigateToPrevious(); return .handled }
        .onKeyPress(.rightArrow) { navigateToNext(); return .handled }
    }

    private func handleToggleSelection(for file: FileItem) {
        viewModel.selectedFileID = file.id
        viewModel.selectedFile = file
    }

    private func navigateToNext() {
        guard let current = viewModel.selectedFile,
              let index = sortedFiles.firstIndex(where: { $0.id == current.id }),
              index + 1 < sortedFiles.count else { return }
        viewModel.selectedFile = sortedFiles[index + 1]
        viewModel.selectedFileID = sortedFiles[index + 1].id
    }

    private func navigateToPrevious() {
        guard let current = viewModel.selectedFile,
              let index = sortedFiles.firstIndex(where: { $0.id == current.id }),
              index - 1 >= 0 else { return }
        viewModel.selectedFile = sortedFiles[index - 1]
        viewModel.selectedFileID = sortedFiles[index - 1].id
    }

    private func scrollTo(_ file: FileItem, proxy: ScrollViewProxy) {
        withAnimation(.easeInOut(duration: 0.2)) {
            proxy.scrollTo(file.id, anchor: .center)
        }
    }

    private func selectAndScroll(file: FileItem, proxy: ScrollViewProxy) {
        viewModel.selectFile(file)
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
}
