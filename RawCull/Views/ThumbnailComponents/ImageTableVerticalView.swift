//
//  ImageTableVerticalView.swift
//  RawCull
//
//  Created by Thomas Evensen on 12/03/2026.
//

import AppKit
import OSLog
import SwiftUI
import UniformTypeIdentifiers

struct ImageTableVerticalView: View {
    private var settings: SettingsViewModel {
        SettingsViewModel.shared
    }

    @Bindable var viewModel: RawCullViewModel
    @State private var hoveredFileID: FileItem.ID?

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
                                        isHovered: hoveredFileID == file.id,
                                        thumbnailSize: settings.thumbnailSizeGrid,
                                        onSelect: {
                                            viewModel.selectFile(file)
                                        },
                                        /*
                                            // Double clik for tag Image
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
                            .padding(.vertical)
                            .padding(.horizontal, 20)
                            .frame(maxWidth: .infinity, alignment: .center)

                            Spacer(minLength: 0)
                        }
                        .frame(maxWidth: .infinity, minHeight: geo.size.height, alignment: .center)
                        .onAppear(perform: {
                            // Defer one run loop so LazyVStack IDs are registered in scroll geometry
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
                    }
                }
                .overlay(alignment: .trailing) {
                    VStack(spacing: 8) {
                        Button {
                            moveSelectionUp()
                        } label: {
                            Image(systemName: "chevron.up")
                                .font(.caption)
                        }
                        .buttonStyle(.plain)
                        .help("Scroll up")

                        Button {
                            moveSelectionDown()
                        } label: {
                            Image(systemName: "chevron.down")
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
        .thumbnailKeyNavigation(viewModel: viewModel, axis: .vertical)
    }

    // MARK: - Private Helpers

    private var filteredFiles: [FileItem] {
        viewModel.filteredFiles.filter { viewModel.passesRatingFilter($0) }
    }

    private var sortedFiles: [FileItem] {
        guard !viewModel.sharpnessModel.sortBySharpness else { return filteredFiles }
        return filteredFiles.sorted { lhs, rhs in
            lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
        }
    }

    private func selectAndScroll(file: FileItem) {
        viewModel.selectFile(file)
        // Scrolling is handled by onChange(of: viewModel.selectedFileID) to avoid double animation
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
}
