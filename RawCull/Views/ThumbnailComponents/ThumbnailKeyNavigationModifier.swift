//
//  ThumbnailKeyNavigationModifier.swift
//  RawCull
//

import AppKit
import SwiftUI

enum ThumbnailNavigationAxis {
    case vertical // ↑ 126 / ↓ 125
    case horizontal // ← 123 / → 124
    case grid // ↑← prev / ↓→ next
}

nonisolated enum ThumbnailKeyAction: Equatable {
    case inspectActualPixels

    nonisolated static func resolve(characters: String?) -> ThumbnailKeyAction? {
        switch characters {
        case "z", "Z":
            .inspectActualPixels

        default:
            nil
        }
    }
}

/// Resolves burst ownership before rating shortcuts. A reserved but unavailable
/// command is still consumed so it cannot fall through into a rating change.
enum ThumbnailKeyboardRouting {
    static func handleBurstCommand(
        _ characters: String?,
        showsBurstGroups: Bool,
        perform: ((String) -> KeyPress.Result)?,
    ) -> Bool {
        guard showsBurstGroups,
              let characters,
              ["\r", "\u{1b}", "b", "B", "2", "u", "U"].contains(characters)
        else { return false }
        _ = perform?(characters)
        return true
    }
}

struct ThumbnailKeyNavigationModifier: ViewModifier {
    let viewModel: RawCullViewModel
    let axis: ThumbnailNavigationAxis
    let filesOverride: (() -> [FileItem])?
    let onBurstKeyPress: ((String) -> KeyPress.Result)?
    @State private var keyboardScope = ReviewKeyboardScope()
    @State private var keyMonitor: Any?

    func body(content: Content) -> some View {
        content
            .background(ReviewKeyboardScopeReader(scope: keyboardScope))
            .onAppear {
                guard keyMonitor == nil else { return }
                keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
                    guard keyboardScope.accepts(event),
                          viewModel.navigation.mainViewMode != .comparisonGrid,
                          !viewModel.zoomOverlay.isVisible,
                          event.modifierFlags.intersection([.command, .control, .option]).isEmpty else { return event }

                    if ThumbnailKeyboardRouting.handleBurstCommand(
                        event.charactersIgnoringModifiers,
                        showsBurstGroups: axis == .grid && viewModel.navigation.showsBurstGroups,
                        perform: onBurstKeyPress,
                    ) {
                        return nil
                    }

                    guard viewModel.selectedFile != nil else { return event }

                    let files: [FileItem] = {
                        if let filesOverride {
                            return filesOverride()
                        }
                        let filtered = viewModel.catalog.filteredFiles.filter { viewModel.ratings.passesRatingFilter($0) }
                        if axis == .grid,
                           viewModel.navigation.showsBurstGroups,
                           !viewModel.similarityFeature.burstGroups.isEmpty {
                            let visible = Dictionary(uniqueKeysWithValues: filtered.map { ($0.id, $0) })
                            if !viewModel.selection.cullingGridRenderedFileIDs.isEmpty {
                                return viewModel.selection.cullingGridRenderedFileIDs.compactMap { visible[$0] }
                            }
                            return viewModel.similarityFeature.burstGroups.flatMap { group in
                                group.fileIDs.compactMap { visible[$0] }
                            }
                        }
                        let usesAnalysisSortOrder = viewModel.sharpnessModel.sortBySharpness
                            || viewModel.similarityFeature.isSimilaritySortingActive
                        return usesAnalysisSortOrder
                            ? filtered
                            : filtered.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
                    }()

                    let isPrev = axis == .vertical ? event.keyCode == 126
                        : axis == .horizontal ? event.keyCode == 123
                        : event.keyCode == 126 || event.keyCode == 123 // grid: ↑ or ←
                    let isNext = axis == .vertical ? event.keyCode == 125
                        : axis == .horizontal ? event.keyCode == 124
                        : event.keyCode == 125 || event.keyCode == 124 // grid: ↓ or →

                    switch event.keyCode {
                    case _ where ThumbnailKeyAction.resolve(characters: event.characters) == .inspectActualPixels:
                        viewModel.navigation.openZoomOverlay(
                            navigationIDs: files.map(\.id),
                            initialSource: .embeddedJPG,
                            initialZoomMode: .actualPixels,
                            showFocusPointsOnOpen: true,
                        )
                        return nil

                    case _ where isPrev:
                        guard let current = viewModel.selectedFile,
                              let idx = files.firstIndex(where: { $0.id == current.id }),
                              idx > 0 else { return nil }
                        viewModel.selection.selectedFileID = files[idx - 1].id
                        return nil

                    case _ where isNext:
                        guard let current = viewModel.selectedFile,
                              let idx = files.firstIndex(where: { $0.id == current.id }),
                              idx + 1 < files.count else { return nil }
                        viewModel.selection.selectedFileID = files[idx + 1].id
                        return nil

                    case 7: // x / X — reject (rating −1, red), advance to next
                        let multiIDs = viewModel.selection.selectedFileIDs
                        if multiIDs.count > 1 {
                            viewModel.culling.updateRating(for: files.filter { multiIDs.contains($0.id) }, rating: -1)
                            viewModel.selection.selectedFileIDs = []
                            return nil
                        }
                        guard let current = viewModel.selectedFile,
                              files.contains(where: { $0.id == current.id }) else { return nil }
                        viewModel.culling.updateRatingAndAdvance(for: current, rating: -1, in: files)
                        return nil

                    case 35: // p / P — keep (rating 0), advance to next
                        let multiIDs = viewModel.selection.selectedFileIDs
                        if multiIDs.count > 1 {
                            viewModel.culling.updateRating(for: files.filter { multiIDs.contains($0.id) }, rating: 0)
                            viewModel.selection.selectedFileIDs = []
                            return nil
                        }
                        guard let current = viewModel.selectedFile,
                              files.contains(where: { $0.id == current.id }) else { return nil }
                        viewModel.culling.updateRatingAndAdvance(for: current, rating: 0, in: files)
                        return nil

                    case 29: // 0 — keep (rating 0), advance to next
                        let multiIDs = viewModel.selection.selectedFileIDs
                        if multiIDs.count > 1 {
                            viewModel.culling.updateRating(for: files.filter { multiIDs.contains($0.id) }, rating: 0)
                            viewModel.selection.selectedFileIDs = []
                            return nil
                        }
                        guard let current = viewModel.selectedFile,
                              files.contains(where: { $0.id == current.id }) else { return nil }
                        viewModel.culling.updateRatingAndAdvance(for: current, rating: 0, in: files)
                        return nil

                    case 18, 19, 20, 21, 23: // 1→2, 2, 3, 4, 5 — set rating and advance to next
                        let rating = switch event.keyCode {
                        case 18: 2 // key 1 maps to rating 2 (rating 1 retired)
                        case 19: 2
                        case 20: 3
                        case 21: 4
                        default: 5 // 23
                        }
                        let multiIDs = viewModel.selection.selectedFileIDs
                        if multiIDs.count > 1 {
                            viewModel.culling.updateRating(for: files.filter { multiIDs.contains($0.id) }, rating: rating)
                            viewModel.selection.selectedFileIDs = []
                            return nil
                        }
                        guard let current = viewModel.selectedFile,
                              files.contains(where: { $0.id == current.id }) else { return nil }
                        viewModel.culling.updateRatingAndAdvance(for: current, rating: rating, in: files)
                        return nil

                    case 17: // t — default tag (rating 3, green), advance to next
                        let multiIDs = viewModel.selection.selectedFileIDs
                        if multiIDs.count > 1 {
                            viewModel.culling.updateRating(for: files.filter { multiIDs.contains($0.id) }, rating: 3)
                            viewModel.selection.selectedFileIDs = []
                            return nil
                        }
                        guard let current = viewModel.selectedFile,
                              files.contains(where: { $0.id == current.id }) else { return nil }
                        viewModel.culling.updateRatingAndAdvance(for: current, rating: 3, in: files)
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
    }
}

extension View {
    func thumbnailKeyNavigation(
        viewModel: RawCullViewModel,
        axis: ThumbnailNavigationAxis,
        files: (() -> [FileItem])? = nil,
        onBurstKeyPress: ((String) -> KeyPress.Result)? = nil,
    ) -> some View {
        modifier(ThumbnailKeyNavigationModifier(
            viewModel: viewModel, axis: axis, filesOverride: files, onBurstKeyPress: onBurstKeyPress,
        ))
    }
}
