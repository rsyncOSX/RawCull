import SwiftUI

struct AIAnalysisInputPicker: View {
    @Binding var selection: AIAnalysisInputSource
    let selectedCount: Int
    let taggedCount: Int
    let isRunning: Bool
    let preserveGridSelection: () -> Void

    var body: some View {
        Picker("Image source", selection: AIAnalysisInputSelection.binding(
            selection: $selection, preserveGridSelection: preserveGridSelection,
        )) {
            Text("Selected (\(selectedCount))").tag(AIAnalysisInputSource.gridSelection)
            Text("Tagged (\(taggedCount))").tag(AIAnalysisInputSource.taggedImages)
        }
        .pickerStyle(.segmented)
        .labelsHidden()
        .accessibilityLabel("Image source")
        .disabled(isRunning)
    }
}

@MainActor
enum AIAnalysisInputSelection {
    static func binding(
        selection: Binding<AIAnalysisInputSource>,
        preserveGridSelection: @escaping () -> Void,
    ) -> Binding<AIAnalysisInputSource> {
        Binding(
            get: { selection.wrappedValue },
            set: { source in
                if selection.wrappedValue == .gridSelection, source == .taggedImages {
                    preserveGridSelection()
                }
                selection.wrappedValue = source
            },
        )
    }
}
