//
//  ImageTableVerticalView.swift
//  RawCull
//
//  Created by Thomas Evensen on 12/03/2026.
//

import AppKit
import OSLog
import RawCullCore
import SwiftUI
import UniformTypeIdentifiers

struct ImageTableVerticalView: View {
    private var settings: SettingsViewModel {
        SettingsViewModel.shared
    }

    @Environment(CatalogWorkspace.self) private var catalog
    @Environment(SelectionModel.self) private var selection
    @Environment(RatingsModel.self) private var ratings
    @Environment(CatalogController.self) private var catalogController
    @Environment(SharpnessScoringModel.self) private var sharpnessModel
    @Environment(RawCullSimilarityFeature.self) private var similarityFeature

    var body: some View {
        VStack(alignment: .center) {
            ScrollViewReader { proxy in
                GeometryReader { geo in
                    ScrollView(.vertical) {
                        VStack {
                            Spacer(minLength: 0)
                            LazyVStack(alignment: .center, spacing: 10) {
                                ForEach(sortedFiles, id: \.id) { file in
                                    ImageItemView(file: file,
                                        isSelected: selection.selectedFileID == file.id,
                                        thumbnailSize: settings.thumbnailSizeGrid,
                                        ratingValue: ratingValue(for: file),
                                        ratingDisplay: ratingDisplay(for: file),
                                        ratingColor: ratingColor(for: file),
                                        onSelect: {
                                            selection.select(file)
                                        },
                                        /*
                                            // Double clik for tag Image
                                            onSelected: {

                                                 Task {
                                                     selection.select(file)
                                                     // The root's toggleTag(for:) is gone; tagging is a
                                                     // rating change on CullingController (default tag = 3).
                                                     culling.updateRating(for: [file], rating: 3)
                                                 }
                                            },
                                             */
                                    )
                                    .id(file.id)
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
                                if let newID = catalogController.selectedFile?.id {
                                    withAnimation {
                                        proxy.scrollTo(newID, anchor: .center)
                                    }
                                }
                            }
                        })
                        .onChange(of: selection.selectedFileID) { _, newID in
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
        .thumbnailKeyNavigation(axis: .vertical)
    }

    // MARK: - Private Helpers

    private var filteredFiles: [FileItem] {
        catalog.filteredFiles.filter { ratings.passesRatingFilter($0) }
    }

    private var sortedFiles: [FileItem] {
        guard !usesAnalysisSortOrder else { return filteredFiles }
        return filteredFiles.sorted { lhs, rhs in
            lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
        }
    }

    private var usesAnalysisSortOrder: Bool {
        sharpnessModel.sortBySharpness
            || similarityFeature.isSimilaritySortingActive
    }

    private func ratingValue(for file: FileItem) -> Int {
        ratings.getRating(for: file)
    }

    private func ratingDisplay(for file: FileItem) -> RatingDisplay {
        RatingDisplay(
            rating: ratingValue(for: file),
            isExplicit: ratings.taggedNamesCache.contains(file.name),
        )
    }

    private func ratingColor(for file: FileItem) -> Color? {
        switch ratingValue(for: file) {
        case -1: .red
        case 2: .yellow
        case 3: .green
        case 4: .blue
        case 5: .purple
        default: nil
        }
    }

    private func selectAndScroll(file: FileItem) {
        selection.select(file)
        // Scrolling is handled by onChange(of: selection.selectedFileID) to avoid double animation
    }

    private func moveSelectionUp() {
        let files = sortedFiles
        guard !files.isEmpty else { return }
        let currentIndex = files.firstIndex { $0.id == selection.selectedFileID } ?? 0
        let nextIndex = max(0, currentIndex - 1)
        selectAndScroll(file: files[nextIndex])
    }

    private func moveSelectionDown() {
        let files = sortedFiles
        guard !files.isEmpty else { return }
        let currentIndex = files.firstIndex { $0.id == selection.selectedFileID } ?? -1
        let nextIndex = min(files.count - 1, currentIndex + 1)
        selectAndScroll(file: files[nextIndex])
    }
}
