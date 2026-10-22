import AppKit
import SwiftUI

struct ObjectAnalysisControls: View {
    @Bindable var feature: RawCullObjectAnalysisFeature
    let files: [FileItem]
    let pendingFiles: [FileItem]

    var body: some View {
        AIAnalysisControlBar {
            Picker("Object concept mode", selection: $feature.discoveryMode) {
                Text("Automatic").tag(ObjectDiscoveryMode.automatic)
                Text("Specific Concepts").tag(ObjectDiscoveryMode.specificConcepts)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .frame(minWidth: 260, maxWidth: 300)
            .disabled(feature.isRunning)

            if feature.discoveryMode == .specificConcepts {
                TextField("bird, person, car", text: $feature.manualConceptText)
                    .textFieldStyle(.roundedBorder)
                    .frame(minWidth: 180)
                    .labelsHidden()
                    .accessibilityLabel("Specific object concepts, separated by commas")
                    .disabled(feature.isRunning)
            } else {
                TextField("Additional photographic criteria", text: $feature.criteria)
                    .textFieldStyle(.roundedBorder)
                    .frame(minWidth: 180)
                    .labelsHidden()
                    .accessibilityLabel("Additional photographic criteria")
                    .disabled(feature.isRunning)
            }
        } actions: {
            if feature.isRunning {
                Button("Cancel", systemImage: "stop.circle", role: .cancel) {
                    feature.cancel()
                }
                .buttonStyle(.bordered)
            } else {
                Button("Analyze \(pendingFiles.count) Images", systemImage: "sparkles") {
                    Task { await feature.analyze(pendingFiles) }
                }
                .buttonStyle(.borderedProminent)
                .disabled(!feature.canRun || pendingFiles.isEmpty)
                Menu {
                    Button("Retry Failed") { Task { await feature.retryFailed(files) } }
                        .disabled(!feature.canRun || !feature.results.contains { !$0.isSuccessful })
                    Button("Clear Results", role: .destructive) { feature.clearResults() }
                        .disabled(feature.results.isEmpty)
                } label: {
                    Label("More Actions", systemImage: "ellipsis.circle")
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
            }
        } status: {
            ObjectAnalysisAvailabilityView(availability: feature.availability)
        }
    }
}
