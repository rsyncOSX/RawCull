import RawCullCore
import SwiftUI

struct ComparisonPager<Pane: View>: View {
    let files: [FileItem]
    let selectedFileID: FileItem.ID?
    let select: (FileItem.ID) -> Void
    @ViewBuilder let pane: (FileItem) -> Pane
    @State private var scrollPositionID: FileItem.ID?
    @State private var scrollSettleTask: Task<Void, Never>?

    var body: some View {
        GeometryReader { geometry in
            ScrollView(.horizontal) {
                LazyHStack(spacing: 0) {
                    ForEach(files) { file in
                        pane(file)
                            .frame(width: geometry.size.width, height: geometry.size.height)
                            .id(file.id)
                    }
                }
                .scrollTargetLayout()
            }
            .scrollIndicators(.hidden)
            .scrollTargetBehavior(.viewAligned(limitBehavior: .alwaysByOne))
            .scrollPosition(id: $scrollPositionID, anchor: .center)
            .onChange(of: selectedFileID, initial: true) { _, newID in
                guard let newID,
                    scrollPositionID != newID,
                    files.contains(where: { $0.id == newID })
                else { return }
                withAnimation(.easeOut(duration: 0.15)) {
                    scrollPositionID = newID
                }
            }
            .onChange(of: scrollPositionID) { _, newID in
                // Debounce: .viewAligned scroll position can update several
                // times mid-drag. Only commit selectedFileID once the value
                // has been stable for a short beat, so heavy recomputation
                // (rating lookups, sharpness breakdown dictionaries) doesn't
                // run on every intermediate frame of a swipe.
                scrollSettleTask?.cancel()
                scrollSettleTask = Task {
                    try? await Task.sleep(for: .milliseconds(120))
                    guard !Task.isCancelled, let newID,
                        selectedFileID != newID,
                        files.contains(where: { $0.id == newID })
                    else { return }
                    select(newID)
                }
            }
        }
        .onDisappear { scrollSettleTask?.cancel() }
    }
}
