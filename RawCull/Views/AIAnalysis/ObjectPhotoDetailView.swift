import AppKit
import SwiftUI

struct ObjectPhotoDetailView: View {
    let result: ObjectPhotoAnalysisResult?
    let file: FileItem?
    let feature: RawCullObjectAnalysisFeature
    let focusMaskModel: FocusMaskModel
    let focusConfig: FocusDetectorConfig
    @State private var preview = ObjectPhotoPreviewModel()
    @State private var selectedObjectID: String?

    private struct LoadIdentity: Equatable {
        let result: ObjectPhotoAnalysisResult?
        let fileURL: URL?
    }

    private var selectedCrop: CGImage? {
        guard let image = preview.image,
              let descriptor = result?.instances.first(where: { $0.id == selectedObjectID })
        else { return nil }
        let rect = ObjectReviewBoardRenderer.crop(
            for: descriptor.normalizedBoundingBox,
            width: image.width, height: image.height,
        )
        return image.cropping(to: rect)
    }

    var body: some View {
        Group {
            if let result {
                ScrollView {
                    VStack(alignment: .leading, spacing: 12) {
                        Text(result.fileName).font(.headline)
                        if let image = preview.image {
                            ObjectOverviewImage(
                                image: image, instances: result.instances,
                                outlines: preview.outlines, focusMap: preview.focusMap,
                                autofocusPoint: preview.autofocusPoint,
                            )
                            .frame(height: 420)
                        }
                        if let failure = result.failure {
                            AIAnalysisErrorView(message: failure)
                        }
                        if result.instances.isEmpty, result.failure == nil {
                            ContentUnavailableView(
                                "No Matching Objects",
                                systemImage: "square.dashed",
                                description: Text("Try a different concept or photograph."),
                            )
                        } else if !result.instances.isEmpty {
                            ObjectInstanceList(
                                instances: result.instances, spatialEvidence: preview.spatialEvidence,
                                selectedObjectID: $selectedObjectID,
                            )
                            if let selectedCrop {
                                Image(decorative: selectedCrop, scale: 1)
                                    .resizable().scaledToFit()
                                    .frame(maxHeight: 240)
                                    .accessibilityLabel("Cropped view of selected object")
                            }
                            if let assessment = result.assessment {
                                ObjectPhotoAssessmentSection(
                                    assessment: assessment, selectedObjectID: selectedObjectID,
                                    selectedEvidence: selectedObjectID.flatMap { preview.spatialEvidence[$0] },
                                )
                            } else if let response = result.freeformResponse {
                                Text("Rejected Qwen assessment").font(.headline)
                                Text(response)
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding()
                }
            } else {
                ContentUnavailableView(
                    "Select an Image",
                    systemImage: "photo",
                    description: Text("Choose an analyzed photograph to inspect its objects."),
                )
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .task(id: LoadIdentity(result: result, fileURL: file?.url)) {
            selectedObjectID = result?.instances.first?.id
            await preview.load(
                result: result, file: file, feature: feature,
                focusMaskModel: focusMaskModel, focusConfig: focusConfig,
            )
        }
    }
}
