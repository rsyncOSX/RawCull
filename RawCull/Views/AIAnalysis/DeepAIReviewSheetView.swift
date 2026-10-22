import SwiftUI

struct DeepAIReviewSheetView: View {
    @Bindable var controller: DeepAIReviewController
    let groupID: Int
    let groupSignature: BurstGroupSignature
    let files: [FileItem]
    @Binding var selection: UUID?
    let focusMaskModel: FocusMaskModel
    let focusConfig: FocusDetectorConfig

    private var result: DeepAIReviewResult? {
        controller.result(for: groupSignature)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            DeepAIReviewSheetControls(
                controller: controller,
                canRun: !files.isEmpty && !controller.isActionUnavailable,
                onRun: {
                    Task {
                        await controller.start(for: files)
                    }
                },
                onCancel: controller.cancel,
                imageCount: files.count,
            )

            DeepAIReviewSheetContent(
                controller: controller,
                files: files,
                completedFiles: controller.completedFiles,
                completedCandidates: controller.completedCandidates,
                state: controller.presentationState(
                    groupID: groupID,
                    groupSignature: groupSignature,
                ),
                selection: $selection,
                focusMaskModel: focusMaskModel,
                focusConfig: focusConfig,
            )
        }
        .padding(16)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .interactiveDismissDisabled(controller.isRunning)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Deep Review")
        .accessibilityValue(RawCullAccessibilityPresentation.deepReviewValue(
            state: controller.presentationState(
                groupID: groupID,
                groupSignature: groupSignature,
            ),
            cachedResult: result,
        ))
    }
}
