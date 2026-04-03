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

struct ThumbnailKeyNavigationModifier: ViewModifier {
    let viewModel: RawCullViewModel
    let axis: ThumbnailNavigationAxis
    @State private var keyMonitor: Any?

    func body(content: Content) -> some View {
        content
            .onAppear {
                keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
                    guard !(NSApp.keyWindow?.firstResponder is NSText),
                          viewModel.selectedFile != nil else { return event }

                    let filtered = viewModel.filteredFiles.filter { viewModel.passesRatingFilter($0) }
                    let files: [FileItem] = viewModel.sharpnessModel.sortBySharpness
                        ? filtered
                        : filtered.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }

                    let isPrev = axis == .vertical ? event.keyCode == 126
                        : axis == .horizontal ? event.keyCode == 123
                        : event.keyCode == 126 || event.keyCode == 123 // grid: ↑ or ←
                    let isNext = axis == .vertical ? event.keyCode == 125
                        : axis == .horizontal ? event.keyCode == 124
                        : event.keyCode == 125 || event.keyCode == 124 // grid: ↓ or →

                    switch event.keyCode {
                    case _ where isPrev:
                        guard let current = viewModel.selectedFile,
                              let idx = files.firstIndex(where: { $0.id == current.id }),
                              idx > 0 else { return nil }
                        viewModel.selectedFile = files[idx - 1]
                        viewModel.selectedFileID = files[idx - 1].id
                        return nil

                    case _ where isNext:
                        guard let current = viewModel.selectedFile,
                              let idx = files.firstIndex(where: { $0.id == current.id }),
                              idx + 1 < files.count else { return nil }
                        viewModel.selectedFile = files[idx + 1]
                        viewModel.selectedFileID = files[idx + 1].id
                        return nil

                    case 7: // x / X — reject (rating −1, red), advance to next
                        guard let current = viewModel.selectedFile,
                              let idx = files.firstIndex(where: { $0.id == current.id }) else { return nil }
                        viewModel.updateRating(for: current, rating: -1)
                        if idx + 1 < files.count {
                            viewModel.selectedFile = files[idx + 1]
                            viewModel.selectedFileID = files[idx + 1].id
                        }
                        return nil

                    case 35: // p / P — keep (rating 0), advance to next
                        guard let current = viewModel.selectedFile,
                              let idx = files.firstIndex(where: { $0.id == current.id }) else { return nil }
                        viewModel.updateRating(for: current, rating: 0)
                        if idx + 1 < files.count {
                            viewModel.selectedFile = files[idx + 1]
                            viewModel.selectedFileID = files[idx + 1].id
                        }
                        return nil

                    case 29: // 0 — keep (rating 0)
                        if let file = viewModel.selectedFile {
                            viewModel.updateRating(for: file, rating: 0)
                        }
                        return nil

                    case 18, 19, 20, 21, 23: // 1→2, 2, 3, 4, 5 — set rating and advance to next
                        guard let current = viewModel.selectedFile,
                              let idx = files.firstIndex(where: { $0.id == current.id }) else { return nil }
                        let rating = switch event.keyCode {
                        case 18: 2 // key 1 maps to rating 2 (rating 1 retired)
                        case 19: 2
                        case 20: 3
                        case 21: 4
                        default: 5 // 23
                        }
                        viewModel.updateRating(for: current, rating: rating)
                        if idx + 1 < files.count {
                            viewModel.selectedFile = files[idx + 1]
                            viewModel.selectedFileID = files[idx + 1].id
                        }
                        return nil

                    case 17: // t — default tag (rating 3, green)
                        if let file = viewModel.selectedFile {
                            viewModel.updateRating(for: file, rating: 3)
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
    }
}

extension View {
    func thumbnailKeyNavigation(viewModel: RawCullViewModel, axis: ThumbnailNavigationAxis) -> some View {
        modifier(ThumbnailKeyNavigationModifier(viewModel: viewModel, axis: axis))
    }
}
