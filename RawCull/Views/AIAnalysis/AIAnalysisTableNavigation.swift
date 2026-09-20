import SwiftUI

nonisolated enum AIAnalysisSelectionNavigation {
    static func previous<ID: Equatable>(from selection: ID?, in ids: [ID]) -> ID? {
        guard let selection,
              let index = ids.firstIndex(of: selection),
              index > ids.startIndex else { return selection }
        return ids[ids.index(before: index)]
    }

    static func next<ID: Equatable>(from selection: ID?, in ids: [ID]) -> ID? {
        guard !ids.isEmpty else { return selection }
        guard let selection,
              let index = ids.firstIndex(of: selection) else { return ids.first }
        let nextIndex = ids.index(after: index)
        guard nextIndex < ids.endIndex else { return selection }
        return ids[nextIndex]
    }
}

struct AIAnalysisTableNavigationButtons<ID: Hashable>: View {
    let ids: [ID]
    @Binding var selection: ID?

    var body: some View {
        VStack(spacing: 8) {
            Button("Previous Row", systemImage: "chevron.up") {
                selection = AIAnalysisSelectionNavigation.previous(from: selection, in: ids)
            }
            .labelStyle(.iconOnly)
            .buttonStyle(.plain)
            .disabled(!canSelectPrevious)
            .help("Select previous row")

            Button("Next Row", systemImage: "chevron.down") {
                selection = AIAnalysisSelectionNavigation.next(from: selection, in: ids)
            }
            .labelStyle(.iconOnly)
            .buttonStyle(.plain)
            .disabled(!canSelectNext)
            .help("Select next row")
        }
        .padding(8)
        .background(.regularMaterial, in: Capsule())
        .overlay {
            Capsule()
                .strokeBorder(.primary.opacity(0.1), lineWidth: 0.5)
        }
        .padding(.trailing, 6)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Table row navigation")
    }

    private var selectedIndex: Int? {
        selection.flatMap(ids.firstIndex(of:))
    }

    private var canSelectPrevious: Bool {
        guard let selectedIndex else { return false }
        return selectedIndex > ids.startIndex
    }

    private var canSelectNext: Bool {
        guard !ids.isEmpty else { return false }
        guard let selectedIndex else { return true }
        return ids.index(after: selectedIndex) < ids.endIndex
    }
}

extension View {
    func aiAnalysisTableNavigation<ID: Hashable>(
        ids: [ID],
        selection: Binding<ID?>,
    ) -> some View {
        overlay(alignment: .trailing) {
            AIAnalysisTableNavigationButtons(ids: ids, selection: selection)
        }
    }
}
