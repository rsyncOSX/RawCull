//
//  HorizontalMainThumbnailsListView.swift
//  RawCull
//
//  Created by Thomas Evensen on 07/03/2026.
//

import SwiftUI

struct HorizontalMainThumbnailsListView: View {
    @Environment(\.openWindow) var openWindow
    @Environment(GridThumbnailViewModel.self) var gridthumbnailviewmodel

    @Bindable var viewModel: RawCullViewModel
    @Binding var showhorizontalvertical: Bool

    @Binding var cgImage: CGImage?
    @Binding var nsImage: NSImage?
    @Binding var scale: CGFloat
    @Binding var lastScale: CGFloat
    @Binding var offset: CGSize

    @State var showInspector: Bool = true
    @State var showGridThumbnail: Bool = false

    var body: some View {
        // let _ = Self._printChanges()

        if showGridThumbnail {
            GridThumbnailView(
                viewModel: viewModel,
                isPresented: $showGridThumbnail,
                nsImage: $nsImage,
                cgImage: $cgImage,
            )
        } else {
            if let file = viewModel.selectedFile {
                VStack(spacing: 20) {
                    MainThumbnailImageView(
                        scale: $scale,
                        lastScale: $lastScale,
                        offset: $offset,
                        url: file.url,
                        file: file,
                    )
                    .padding()
                }
                .inspector(isPresented: $showInspector) {
                    FileInspectorView(
                        file: $viewModel.selectedFile,
                    )
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
                    description: Text("Select an image to view its details."),
                )
            }

            Spacer()

            ImageTableHorizontalView(
                viewModel: viewModel,
                selectedSource: viewModel.selectedSource,
            )
            .padding()
            .toolbar { toolbarContent }
            // .focusedSceneValue(\.tagimage, $viewModel.focustagimage)

            if viewModel.focustagimage == true {
                TagImageFocusView(
                    focustagimage: $viewModel.focustagimage,
                    files: viewModel.files,
                    selectedFileID: viewModel.selectedFileID,
                    handleToggleSelection: handleToggleSelection,
                )
            }
        }
    }

    private func handleToggleSelection(for file: FileItem) {
        Task {
            viewModel.selectFile(file)
            await viewModel.toggleTag(for: file)
        }
    }

    var files: [FileItem] {
        viewModel.files
    }

    var cullingModel: CullingModel {
        viewModel.cullingModel
    }
}

extension HorizontalMainThumbnailsListView {
    @ToolbarContentBuilder
    var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .status) {
            Button(action: openCopyView) {
                Label("Copy", systemImage: "document.on.document")
            }
            .disabled(viewModel.creatingthumbnails || viewModel.selectedSource == nil)
            .help("Copy tagged images to destination...")
        }

        ToolbarItem(placement: .status) {
            Button(action: openGridThumbnailWindow) {
                Label("Grid View", systemImage: "square.grid.2x2")
            }
            .disabled(viewModel.selectedSource == nil || viewModel.filteredFiles.isEmpty)
            .help("Open thumbnail grid view")
        }

        ToolbarItem(placement: .status) {
            Button(action: opentaggedGridThumbnailWindow) {
                Label("Grid Tagged Images", systemImage: "square.grid.2x2.fill")
            }
            .disabled(viewModel.selectedSource == nil || viewModel.filteredFiles.isEmpty || showGridtaggedThumbnailWindow() == false)
            .help("Open tagged thumbnail grid view")
        }

        ToolbarItem(placement: .status) {
            Button(action: toggleshowhorizontal) {
                Label("Horizontal", systemImage: "arrow.up.and.down.text.horizontal")
            }
            .disabled(viewModel.selectedSource == nil || viewModel.filteredFiles.isEmpty)
            .help("Show Vertical thumbnails")
            .labelStyle(.iconOnly)
        }

        ToolbarItem(placement: .status) {
            Button(action: toggleshowsavedfiles) {
                Label("Saved Files", systemImage: "square.and.arrow.down")
            }
            .help("Show saved files")
        }

        ToolbarItem(placement: .status) {
            Button(action: toggleshowinspector) {
                Label("Toggle Inspector", systemImage: "rectangle.portrait.and.arrow.right")
            }
            .disabled(viewModel.selectedSource == nil || viewModel.filteredFiles.isEmpty)
            .help("Show inspector")
            .labelStyle(.iconOnly)
        }

        ToolbarItem(placement: .status) {
            Toggle(isOn: $viewModel.sharpnessModel.sortBySharpness) {
                Label("Sharpness", systemImage: "arrow.up.arrow.down")
            }
            .disabled(viewModel.selectedSource == nil || viewModel.filteredFiles.isEmpty || viewModel.sharpnessModel.scores.isEmpty)
            .labelStyle(.iconOnly)
            .help("Sort thumbnails sharpest-first")
            .onChange(of: viewModel.sharpnessModel.sortBySharpness) { _, _ in
                Task(priority: .background) {
                    await viewModel.handleSortOrderChange()
                }
            }
        }

        ToolbarItem(placement: .status) {
            HStack(spacing: 4) {
                ForEach([(-1, Color.red), (2, Color.yellow), (3, Color.green), (4, Color.blue), (5, Color.purple)], id: \.0) { rating, color in
                    Button { applyRatingFilter(rating) } label: {
                        Circle()
                            .fill(color.opacity(isRatingFilterActive(rating) ? 1.0 : 0.25))
                            .frame(width: 14, height: 14)
                    }
                    .buttonStyle(.borderless)
                    .contentShape(Rectangle())
                    .help(rating == -1 ? "Show only rejected images" : "Show only \(rating)-star images")
                }

                // Keepers button (rating == 0)
                Button { applyRatingFilter(0) } label: {
                    Text("P")
                        .font(.system(size: 11, weight: .semibold, design: .monospaced))
                        .foregroundStyle(viewModel.ratingFilter == .keepers ? .white : .secondary)
                        .frame(width: 18, height: 18)
                        .background(
                            Circle()
                                .fill(viewModel.ratingFilter == .keepers ? Color.accentColor : Color.secondary.opacity(0.2))
                        )
                }
                .buttonStyle(.borderless)
                .contentShape(Rectangle())
                .help("Show only keepers (rating 0)")

                if viewModel.ratingFilter != .all {
                    Button {
                        viewModel.ratingFilter = .all
                        Task(priority: .background) { await viewModel.handleSortOrderChange() }
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.borderless)
                    .contentShape(Rectangle())
                    .help("Show all thumbnails")
                }
            }
            .disabled(viewModel.selectedSource == nil)
        }

        if viewModel.filteredFiles.isEmpty {
            ToolbarItem(placement: .status) {
                Button(action: resetApertureSelection) {
                    Label("Reset Sharpness", systemImage: "arrow.counterclockwise")
                }
                .help("Reset Sharpness Model")
                .labelStyle(.iconOnly)
            }
        }
    }

    func resetApertureSelection() {
        viewModel.sharpnessModel.reset()
    }

    func applyRatingFilter(_ rating: Int) {
        let newFilter: RatingFilter = switch rating {
        case -1: .rejected
        case 0: .keepers
        default: .minimum(rating)
        }
        viewModel.ratingFilter = viewModel.ratingFilter == newFilter ? .all : newFilter
        Task(priority: .background) { await viewModel.handleSortOrderChange() }
    }

    func isRatingFilterActive(_ rating: Int) -> Bool {
        switch rating {
        case -1: viewModel.ratingFilter == .rejected
        case 0: viewModel.ratingFilter == .keepers
        default: viewModel.ratingFilter == .minimum(rating)
        }
    }

    func openCopyView() {
        viewModel.sheetType = .copytasksview
        viewModel.showcopyARWFilesView = true
    }

    func toggleshowinspector() {
        showInspector.toggle()
    }

    func toggleshowhorizontal() {
        showhorizontalvertical.toggle()
    }

    func openGridThumbnailWindow() {
        gridthumbnailviewmodel.open(
            cullingModel: viewModel.cullingModel,
            selectedSource: viewModel.selectedSource,
            filteredFiles: viewModel.filteredFiles,
        )
        showGridThumbnail = true
    }

    func opentaggedGridThumbnailWindow() {
        openWindow(id: WindowIdentifier.gridTaggedThumbnails.rawValue)
    }

    private func showGridtaggedThumbnailWindow() -> Bool {
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

    func toggleshowsavedfiles() {
        viewModel.showSavedFiles.toggle()
    }
}
