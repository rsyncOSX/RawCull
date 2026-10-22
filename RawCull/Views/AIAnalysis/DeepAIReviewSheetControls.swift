import SwiftUI

struct DeepAIReviewSheetControls: View {
    @Bindable var controller: DeepAIReviewController
    let canRun: Bool
    let onRun: () -> Void
    let onCancel: () -> Void
    let imageCount: Int

    var body: some View {
        AIAnalysisControlBar {
            Picker("", selection: $controller.preset) {
                Text("Auto").tag(DeepAIReviewPreset.auto)
                Text("Full Subject").tag(DeepAIReviewPreset.fullSubject)
                Text("Head / Face").tag(DeepAIReviewPreset.headFace)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .accessibilityLabel("Subject target")
            .frame(minWidth: 300, maxWidth: 420)
            .disabled(controller.isRunning)
            .accessibilityHint("Selects the subject target used for local detail review.")
        } actions: {
            if controller.isRunning {
                Button("Cancel", systemImage: "stop.circle", role: .cancel, action: onCancel)
                    .buttonStyle(.bordered)
                    .accessibilityHint("Cancels the active Deep Review.")
            } else {
                Button("Analyze \(imageCount) Images", systemImage: "sparkles", action: onRun)
                    .buttonStyle(.borderedProminent)
                    .disabled(!canRun)
                    .accessibilityHint("Runs local AI subject-detail analysis for this burst group.")
            }
        } status: {
            SAM3ModelAvailabilityView(status: controller.modelStatus)
        }
    }
}
