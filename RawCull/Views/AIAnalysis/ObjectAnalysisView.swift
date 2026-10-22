import AppKit
import SwiftUI

struct ObjectAnalysisView: View {
    @Bindable var feature: RawCullObjectAnalysisFeature
    let files: [FileItem]
    @Binding var selection: UUID?
    let focusMaskModel: FocusMaskModel
    let focusConfig: FocusDetectorConfig

    private var pendingFiles: [FileItem] {
        feature.filesNeedingAnalysis(from: files)
    }

    private var selectedResult: ObjectPhotoAnalysisResult? {
        selection.flatMap { id in feature.results.first { $0.fileID == id } }
    }

    var body: some View {
        VStack(spacing: 12) {
            ObjectAnalysisControls(feature: feature, files: files, pendingFiles: pendingFiles)
            if let progress = feature.progress {
                AIAnalysisProgressView(
                    completedCount: progress.completedCount,
                    totalCount: progress.totalCount,
                    message: "\(progress.currentFileName): \(progress.stage.label)",
                )
            }
            if let failure = feature.failureMessage {
                AIAnalysisErrorView(message: failure)
            }
            if feature.results.isEmpty {
                ContentUnavailableView(
                    "Ready to Analyze",
                    systemImage: "square.3.layers.3d",
                    description: Text("Analyze selected or tagged photographs to inspect objects and their details."),
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .aiAnalysisResultsContainer()
            } else {
                HSplitView {
                    ObjectPhotoResultsTable(results: feature.results, selection: $selection)
                        .frame(minWidth: 400, idealWidth: 550, maxHeight: .infinity)
                    ObjectPhotoDetailView(
                        result: selectedResult,
                        file: files.first { $0.id == selectedResult?.fileID },
                        feature: feature, focusMaskModel: focusMaskModel,
                        focusConfig: focusConfig,
                    )
                    .frame(minWidth: 330, idealWidth: 420, maxHeight: .infinity)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .padding(16)
        .task(id: feature.results.map(\.id)) {
            if selection == nil {
                selection = feature.results.first?.id
            }
        }
    }
}
