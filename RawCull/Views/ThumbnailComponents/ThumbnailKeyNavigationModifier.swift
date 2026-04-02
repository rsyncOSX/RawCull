//
//  ThumbnailKeyNavigationModifier.swift
//  RawCull
//

import AppKit
import SwiftUI

enum ThumbnailNavigationAxis {
    case vertical   // ↑ 126 / ↓ 125
    case horizontal // ← 123 / → 124
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

                    let filtered = viewModel.filteredFiles.filter { viewModel.getRating(for: $0) >= viewModel.rating }
                    let files: [FileItem] = viewModel.sharpnessModel.sortBySharpness
                        ? filtered
                        : filtered.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }

                    let prevKey: UInt16 = axis == .vertical ? 126 : 123
                    let nextKey: UInt16 = axis == .vertical ? 125 : 124

                    switch event.keyCode {
                    case prevKey:
                        guard let current = viewModel.selectedFile,
                              let idx = files.firstIndex(where: { $0.id == current.id }),
                              idx > 0 else { return nil }
                        viewModel.selectedFile = files[idx - 1]
                        viewModel.selectedFileID = files[idx - 1].id
                        return nil

                    case nextKey:
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
    }
}

extension View {
    func thumbnailKeyNavigation(viewModel: RawCullViewModel, axis: ThumbnailNavigationAxis) -> some View {
        modifier(ThumbnailKeyNavigationModifier(viewModel: viewModel, axis: axis))
    }
}
