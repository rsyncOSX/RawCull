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
    @Environment(SettingsViewModel.self) private var settings

    @Bindable var viewModel: RawCullViewModel
    @State private var hoveredFileID: FileItem.ID?
    @State private var keyMonitor: Any?

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
                                        onSelect: {
                                            viewModel.selectFile(file)
                                        },
                                        onTag: {
                                            Task { await viewModel.toggleTag(for: file) }
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
                    .background(.ultraThinMaterial, in: Capsule())
                    .overlay { Capsule().strokeBorder(.primary.opacity(0.1), lineWidth: 0.5) }
                    .padding(.trailing, 6)
                }
            }
        }
        .onAppear {
            keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
                // Don't steal events from text inputs
                guard !(NSApp.keyWindow?.firstResponder is NSText),
                      viewModel.selectedFile != nil else { return event }

                let filtered = viewModel.filteredFiles.filter { viewModel.getRating(for: $0) >= viewModel.rating }
                let files: [FileItem] = viewModel.sharpnessModel.sortBySharpness
                    ? filtered
                    : filtered.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }

                switch event.keyCode {
                case 126: // ↑ up arrow
                    guard let current = viewModel.selectedFile,
                          let idx = files.firstIndex(where: { $0.id == current.id }),
                          idx > 0 else { return nil }
                    viewModel.selectedFile = files[idx - 1]
                    viewModel.selectedFileID = files[idx - 1].id
                    return nil

                case 125: // ↓ down arrow
                    guard let current = viewModel.selectedFile,
                          let idx = files.firstIndex(where: { $0.id == current.id }),
                          idx + 1 < files.count else { return nil }
                    viewModel.selectedFile = files[idx + 1]
                    viewModel.selectedFileID = files[idx + 1].id
                    return nil

                case 17: // t — toggle tag
                    if let file = viewModel.selectedFile {
                        Task { await viewModel.toggleTag(for: file) }
                    }
                    return nil

                default:
                    return event
                }
            }
        }
        .onDisappear {
            if let monitor = keyMonitor {
                NSEvent.removeMonitor(monitor)
                keyMonitor = nil
            }
        }
        // .focusedSceneValue(\.tagimage, $viewModel.focustagimage)
    }

    // MARK: - Private Helpers

    var cullingModel: CullingModel {
        viewModel.cullingModel
    }

    private var filteredFiles: [FileItem] {
        viewModel.filteredFiles.filter { file in
            viewModel.getRating(for: file) >= viewModel.rating
        }
    }

    private var sortedFiles: [FileItem] {
        guard !viewModel.sharpnessModel.sortBySharpness else { return filteredFiles }
        return filteredFiles.sorted { lhs, rhs in
            lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
        }
    }

    private func scrollTo(_ file: FileItem, proxy: ScrollViewProxy) {
        withAnimation(.easeInOut(duration: 0.2)) {
            proxy.scrollTo(file.id, anchor: .center)
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
