//
//  ImageTableHorizontalView.swift
//  RawCull
//
//  Created by Thomas Evensen on 06/03/2026.
//

import AppKit
import SwiftUI

struct ImageTableHorizontalView: View {
    @Bindable var viewModel: RawCullViewModel
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
                                    isHovered: hoveredFileID == file.id,
                                    thumbnailSize: savedSettings.thumbnailSizeGrid,
                                    onSelect: { handleSelect(for: file) },
                                    // Double clik for tag Image
                                    /*
                                        onSelected: {

                                             Task {
                                                 viewModel.selectFile(file)
                                                 await viewModel.toggleTag(for: file)
                                             }
                                        },
                                         */
                                )
                                .id(file.id)
                                .onHover { isHovered in
                                    hoveredFileID = isHovered ? file.id : nil
                                }
                            }
                        }
                    }
                    .frame(height: CGFloat(savedSettings.thumbnailSizeGrid) + 40)
                    .onAppear(perform: {
                        // Defer one run loop so LazyHStack IDs are registered in scroll geometry
                        DispatchQueue.main.async {
                            if let newID = viewModel.selectedFile?.id {
                                withAnimation {
                                    proxy.scrollTo(newID, anchor: .center)
                                }
                            }
                        }
                    })
                    .onChange(of: viewModel.selectedFileID) { _, newID in
                        guard let newID else { return }
                        withAnimation(.easeInOut(duration: 0.2)) {
                            proxy.scrollTo(newID, anchor: .center)
                        }
                    }
                    .task(id: viewModel.selectedSource) {
                        await ThumbnailLoader.shared.cancelAll()
                    }
                    .overlay(alignment: .top) {
                        HStack(spacing: 8) {
                            Button {
                                moveSelectionUp()
                            } label: {
                                Image(systemName: "chevron.left")
                                    .font(.caption)
                            }
                            .buttonStyle(.plain)
                            .help("Scroll up")

                            Button {
                                moveSelectionDown()
                            } label: {
                                Image(systemName: "chevron.right")
                                    .font(.caption)
                            }
                            .buttonStyle(.plain)
                            .help("Scroll down")
                        }
                        .padding(8)
                        .background(.regularMaterial, in: Capsule())
                        .overlay { Capsule().strokeBorder(.primary.opacity(0.1), lineWidth: 0.5) }
                        .padding(.trailing, 6)
                    }
                }
            }
        }
        .task {
            savedSettings = await SettingsViewModel.shared.asyncgetsettings()
        }
        .thumbnailKeyNavigation(viewModel: viewModel, axis: .horizontal)
        // .focusedSceneValue(\.tagimage, $viewModel.focustagimage)
    }

    private func handleSelect(for file: FileItem) {
        viewModel.selectedFileID = file.id
        viewModel.selectedFile = file
    }

    private func selectAndScroll(file: FileItem) {
        viewModel.selectFile(file)
        // Scrolling is handled by onChange(of: viewModel.selectedFile?.id) to avoid double animation
    }

    private func moveSelectionUp() {
        let files = sortedFiles
        guard !files.isEmpty else { return }
        let currentIndex = files.firstIndex { $0.id == viewModel.selectedFileID } ?? 0
        let nextIndex = max(0, currentIndex - 1)
        selectAndScroll(file: files[nextIndex])
    }

    private func moveSelectionDown() {
        let files = sortedFiles
        guard !files.isEmpty else { return }
        let currentIndex = files.firstIndex { $0.id == viewModel.selectedFileID } ?? -1
        let nextIndex = min(files.count - 1, currentIndex + 1)
        selectAndScroll(file: files[nextIndex])
    }

    private var filteredFiles: [FileItem] {
        viewModel.filteredFiles.filter { viewModel.passesRatingFilter($0) }
    }

    private var sortedFiles: [FileItem] {
        guard !viewModel.sharpnessModel.sortBySharpness else { return filteredFiles }
        return filteredFiles.sorted { lhs, rhs in
            lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
        }
    }
}
